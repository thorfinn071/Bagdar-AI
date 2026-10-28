"""Freeze and restore byte-identical Bagdar research payloads (Python 3.10+)."""

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

from github_source import GitHubReleaseSource, GitHubSourceError


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = Path(__file__).with_name("manifest-v4.json")
SOURCE_CONFIG = Path(__file__).with_name("source.json")
LEGACY_INPUTS = json.loads(
    Path(__file__).with_name("legacy-replay-inputs.json").read_text(encoding="utf-8")
)["files"]
PREFIXES = (
    "test/fixtures/spatial_safety/",
    "docs/_baseline_logs/",
    "android/app/src/research/assets/voice_wake/",
)
MAX_BYTES = 2 * 1024**3
MAX_FILES = 100_000
CHUNK = 1024 * 1024
IDENTIFIER = re.compile(r"[a-z0-9][a-z0-9-]{0,95}")
SHA256 = re.compile(r"[0-9a-f]{64}")
RESERVED = {"CON", "PRN", "AUX", "NUL"} | {
    f"{prefix}{i}" for prefix in ("COM", "LPT") for i in range(1, 10)
}


class DatasetError(ValueError):
    pass


def relative(value, *, payload=False):
    if not isinstance(value, str) or not value or "\\" in value:
        raise DatasetError(f"Invalid relative path: {value!r}")
    parts = value.split("/")
    if any(
        part in ("", ".", "..")
        or part.casefold() == ".git"
        or part[-1:] in (" ", ".")
        or any(ord(c) < 32 or c in ':*?"<>|' for c in part)
        or part.split(".")[0].upper() in RESERVED
        for part in parts
    ):
        raise DatasetError(f"Unsafe relative path: {value!r}")
    if payload and not value.startswith(PREFIXES) and value not in LEGACY_INPUTS:
        raise DatasetError(f"Outside dataset scopes: {value}")
    return value


def local_path(root, name):
    relative(name)
    root = root.resolve()
    path = root
    for part in name.split("/"):
        path = path / part
        if path.is_symlink():
            raise DatasetError(f"Refusing symbolic link: {path}")
    if not path.resolve().is_relative_to(root):
        raise DatasetError(f"Path escapes destination: {name}")
    return path


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def matches(path, row):
    return (
        path.is_file()
        and path.stat().st_size == row["bytes"]
        and digest(path) == row["sha256"]
    )


def bounded_size(value):
    if type(value) is not int or not 0 <= value <= MAX_BYTES:
        raise DatasetError("Invalid or excessive byte count")


def load_manifest(path):
    if path.stat().st_size > 32 * CHUNK:
        raise DatasetError("Manifest is too large")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or not IDENTIFIER.fullmatch(
        data.get("version", "")
    ):
        raise DatasetError("Unsupported manifest schema/version")
    datasets = data.get("datasets")
    if not isinstance(datasets, list) or not datasets:
        raise DatasetError("Manifest needs datasets")
    ids, names, archives = set(), set(), set()
    total_bytes = 0
    for dataset in datasets:
        name = dataset.get("id", "")
        if not IDENTIFIER.fullmatch(name) or name in ids:
            raise DatasetError("Duplicate or invalid dataset id")
        ids.add(name)
        archive = dataset["archive"]
        filename = relative(archive["fileName"])
        if "/" in filename or not filename.endswith(".zip"):
            raise DatasetError("Archive must be a single ZIP filename")
        if filename.casefold() in archives:
            raise DatasetError("Duplicate archive filename")
        archives.add(filename.casefold())
        bounded_size(archive["bytes"])
        if not SHA256.fullmatch(archive["sha256"]):
            raise DatasetError("Invalid archive checksum")
        files = dataset["files"]
        if not isinstance(files, list) or not files:
            raise DatasetError("Empty dataset")
        for row in files:
            name = relative(row["path"], payload=True)
            if name.casefold() in names:
                raise DatasetError(f"Duplicate/case-colliding payload: {name}")
            names.add(name.casefold())
            bounded_size(row["bytes"])
            if type(row.get("retainInGit", False)) is not bool:
                raise DatasetError("Invalid retainInGit flag")
            total_bytes += row["bytes"]
            if not SHA256.fullmatch(row["sha256"]):
                raise DatasetError(f"Invalid payload checksum: {name}")
            if name in LEGACY_INPUTS and row["sha256"] != LEGACY_INPUTS[name]:
                raise DatasetError(f"Legacy evidence must match its recorded hash: {name}")
        if sum(row["bytes"] for row in files) != dataset["totalBytes"]:
            raise DatasetError("Dataset byte total does not match")
    if len(names) > MAX_FILES or total_bytes > 8 * 1024**3:
        raise DatasetError("Manifest exceeds dataset limits")
    # Also reject file/directory collisions before any writes.
    for name in names:
        parts = name.split("/")
        if any("/".join(parts[:i]) in names for i in range(1, len(parts))):
            raise DatasetError(f"File/directory collision: {name}")
    return data


def choose(data, ids):
    selected = set(ids or [d["id"] for d in data["datasets"]])
    known = {d["id"] for d in data["datasets"]}
    if selected - known:
        raise DatasetError(f"Unknown datasets: {sorted(selected - known)}")
    return [d for d in data["datasets"] if d["id"] in selected]


def selected_files(root, selection):
    names = set()
    for name in selection.get("paths", []):
        relative(name, payload=True)
        names.add(name)
    if "root" in selection:
        folder = relative(selection["root"], payload=True)
        names.update(
            path.relative_to(root).as_posix()
            for path in local_path(root, folder).rglob("*")
            if path.is_file() and path.suffix in selection["suffixes"]
        )
    if not names:
        raise DatasetError(f"No files selected for {selection['id']}")
    for name in names:
        relative(name, payload=True)
        if not local_path(root, name).is_file():
            raise DatasetError(f"Missing selected file: {name}")
    return sorted(names)


def create(root, selection_path, version, manifest_path, bundle_dir):
    root = root.resolve()
    if not IDENTIFIER.fullmatch(version):
        raise DatasetError("Invalid dataset version")
    if manifest_path.exists() or bundle_dir.exists():
        raise DatasetError("Use a new manifest path and a new bundle directory")
    policy = json.loads(selection_path.read_text(encoding="utf-8"))
    if policy.get("schemaVersion") != 1:
        raise DatasetError("Unsupported selection schema")
    selections = policy["datasets"]
    ids = [s["id"] for s in selections]
    if len(set(ids)) != len(ids) or not all(IDENTIFIER.fullmatch(i) for i in ids):
        raise DatasetError("Invalid selection ids")
    # Preflight every input before opening output files.
    plans = []
    for selection in selections:
        names = selected_files(root, selection)
        retained = set(selection.get("retainPaths", []))
        if retained - set(names):
            raise DatasetError("Retained files must be included in the bundle")
        plans.append((selection["id"], names, retained))
    bundle_dir.mkdir(parents=True, exist_ok=False)
    data = {"schemaVersion": 1, "version": version, "datasets": []}
    for dataset_id, names, retained in plans:
        filename = f"{version}--{dataset_id}.zip"
        archive_path = bundle_dir / filename
        rows = []
        with zipfile.ZipFile(archive_path, "x", allowZip64=True) as archive:
            for name in names:
                path = local_path(root, name)
                size = path.stat().st_size
                bounded_size(size)
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                info.compress_type = (
                    zipfile.ZIP_STORED
                    if path.suffix in (".gz", ".png", ".gif")
                    else zipfile.ZIP_DEFLATED
                )
                h, count = hashlib.sha256(), 0
                with path.open("rb") as source, archive.open(
                    info, "w", force_zip64=True
                ) as target:
                    for chunk in iter(lambda: source.read(CHUNK), b""):
                        count += len(chunk)
                        h.update(chunk)
                        target.write(chunk)
                if count != size:
                    raise DatasetError(f"Source changed while packaging: {name}")
                row = {"path": name, "bytes": count, "sha256": h.hexdigest()}
                if name in retained:
                    row["retainInGit"] = True
                rows.append(row)
        data["datasets"].append(
            {
                "id": dataset_id,
                "archive": {
                    "fileName": filename,
                    "bytes": archive_path.stat().st_size,
                    "sha256": digest(archive_path),
                },
                "totalBytes": sum(row["bytes"] for row in rows),
                "files": rows,
            }
        )
        print(f"Packed {dataset_id}: {len(rows)} files", flush=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
    load_manifest(manifest_path)
    return data


def check_url(url):
    parsed = urllib.parse.urlsplit(url)
    loopback = parsed.hostname == "localhost"
    try:
        loopback = loopback or ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:
        pass
    if (
        parsed.scheme not in ("https", "http")
        or (parsed.scheme == "http" and not loopback)
        or parsed.username
        or parsed.password
    ):
        raise DatasetError("Use HTTPS (plain HTTP is allowed only on loopback)")


class CheckedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl)
        if urllib.parse.urlsplit(req.full_url).scheme == "https":
            if urllib.parse.urlsplit(newurl).scheme != "https":
                raise DatasetError("Refusing HTTPS downgrade")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def get_archive(source, cache, row, github=None):
    name = row["fileName"]
    if not source.startswith(("https://", "http://", "github-release:")):
        path = local_path(Path(source).resolve(), name)
        if not matches(path, row):
            raise DatasetError(f"Bundle missing or corrupt: {name}")
        return path
    if github is None:
        check_url(source)
        parsed = urllib.parse.urlsplit(source)
        if parsed.query or parsed.fragment:
            raise DatasetError("Source must be a base URL without query/fragment")
    cache.mkdir(parents=True, exist_ok=True)
    # Content-addressed cache avoids collisions across manifests/versions.
    target = local_path(cache, row["sha256"] + ".zip")
    if target.exists():
        if matches(target, row):
            return target
        raise DatasetError(f"Corrupt cache entry; remove it explicitly: {target}")
    url = source.rstrip("/") + "/" + urllib.parse.quote(name)
    opener = urllib.request.build_opener(CheckedRedirect())
    h, count = hashlib.sha256(), 0
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as download:
        temporary = Path(download.name)
        try:
            response = (
                github.open_asset(row) if github else opener.open(url, timeout=30)
            )
            with response:
                for chunk in iter(lambda: response.read(CHUNK), b""):
                    count += len(chunk)
                    if count > row["bytes"]:
                        raise DatasetError("Download exceeds declared size")
                    h.update(chunk)
                    download.write(chunk)
            if count != row["bytes"] or h.hexdigest() != row["sha256"]:
                raise DatasetError(f"Download checksum/size mismatch: {name}")
        except BaseException:
            download.close()
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


def preflight(root, datasets, *, require_all):
    missing = []
    for dataset in datasets:
        for row in dataset["files"]:
            path = local_path(root, row["path"])
            if not path.exists():
                missing.append(row["path"])
            elif not matches(path, row):
                raise DatasetError(f"Existing file differs; not overwritten: {row['path']}")
    if require_all and missing:
        raise DatasetError(
            f"{len(missing)} payloads missing; first: {missing[0]}. "
            "Run restore with an explicit bundle source."
        )
    return missing


def restore_bundle(root, archive_path, dataset):
    expected = {row["path"]: row for row in dataset["files"]}
    # Stage and validate a complete bundle before installing any of its files.
    with tempfile.TemporaryDirectory(prefix=".bagdar-restore-", dir=root) as folder:
        staging = Path(folder)
        with zipfile.ZipFile(archive_path) as archive:
            entries = archive.infolist()
            if len(entries) != len(expected) or len({i.filename for i in entries}) != len(entries):
                raise DatasetError("Duplicate or unexpected archive members")
            for info in entries:
                row = expected.get(info.filename)
                if (
                    row is None
                    or info.file_size != row["bytes"]
                    or info.is_dir()
                    or stat.S_ISLNK(info.external_attr >> 16)
                    or info.flag_bits & 1
                    or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                ):
                    raise DatasetError(f"Invalid archive member: {info.filename}")
                path = local_path(staging, info.filename)
                path.parent.mkdir(parents=True, exist_ok=True)
                h, count = hashlib.sha256(), 0
                with archive.open(info) as source, path.open("xb") as target:
                    for chunk in iter(lambda: source.read(CHUNK), b""):
                        count += len(chunk)
                        if count > row["bytes"]:
                            raise DatasetError("Expanded payload exceeds declared size")
                        h.update(chunk)
                        target.write(chunk)
                if count != row["bytes"] or h.hexdigest() != row["sha256"]:
                    raise DatasetError(f"Payload checksum mismatch: {info.filename}")
        preflight(root, [dataset], require_all=False)
        for row in dataset["files"]:
            target = local_path(root, row["path"])
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            # An atomic hard link installs the verified file without replacing
            # a concurrent local edit or leaving a partially copied payload.
            os.link(local_path(staging, row["path"]), target)


def restore(root, data, source, ids=None):
    if not root.is_dir():
        raise DatasetError("Destination root must already exist")
    datasets = choose(data, ids)
    missing = set(preflight(root, datasets, require_all=False))
    cache = local_path(root, "output/dataset-cache")
    github = (
        GitHubReleaseSource(source, ROOT)
        if missing and source.startswith("github-release:")
        else None
    )
    for dataset in datasets:
        if not any(row["path"] in missing for row in dataset["files"]):
            print(f"Verified {dataset['id']}: already present", flush=True)
            continue
        archive = get_archive(source, cache, dataset["archive"], github=github)
        restore_bundle(root, archive, dataset)
        print(f"Restored {dataset['id']}", flush=True)
    preflight(root, datasets, require_all=True)


def configured_source(manifest):
    if not SOURCE_CONFIG.exists():
        raise DatasetError("No configured release; provide --source")
    config = json.loads(SOURCE_CONFIG.read_text(encoding="utf-8"))
    if (
        config.get("schemaVersion") != 1
        or config.get("manifestSha256") != digest(manifest)
    ):
        raise DatasetError("Configured source does not match this manifest")
    return config["source"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("verify", "restore", "list"):
        command = commands.add_parser(name)
        command.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
        command.add_argument("--root", type=Path, default=ROOT)
        command.add_argument("--dataset", action="append")
        if name == "restore":
            command.add_argument(
                "--source",
                help="Bundle directory, HTTPS base URL or github-release:OWNER/REPO@TAG",
            )
    command = commands.add_parser("create")
    command.add_argument("--root", type=Path, default=ROOT)
    command.add_argument("--selection", type=Path, required=True)
    command.add_argument("--version", required=True)
    command.add_argument("--manifest", type=Path, required=True)
    command.add_argument("--bundle-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "create":
            create(args.root, args.selection, args.version, args.manifest, args.bundle_dir)
        else:
            data = load_manifest(args.manifest)
            datasets = choose(data, args.dataset)
            if args.command == "restore":
                source = args.source
                if source is None:
                    source = configured_source(args.manifest)
                restore(args.root.resolve(), data, source, args.dataset)
            elif args.command == "verify":
                preflight(args.root.resolve(), datasets, require_all=True)
                print(f"Verified {sum(len(d['files']) for d in datasets)} payloads")
            else:
                for dataset in datasets:
                    print(
                        f"{dataset['id']}: {len(dataset['files'])} files, "
                        f"{dataset['totalBytes'] / 1024**2:.2f} MiB"
                    )
        return 0
    except (
        DatasetError, GitHubSourceError, OSError, KeyError, TypeError,
        json.JSONDecodeError, zipfile.BadZipFile,
    ) as error:
        print(f"Dataset error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

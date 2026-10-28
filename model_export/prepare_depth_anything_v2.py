"""Fetch immutable official DA-V2 Small source/weights, outside app assets.

Run with model_export/venv/Scripts/python.exe. No mutable main/latest downloads;
an existing mismatched file is rejected rather than silently replaced.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "model_export/depth_anything_v2"
SOURCE_COMMIT = "a561b849ebae10a6f5ef49e26c83cbbcd36c71bf"
MODEL_REVISION = "03876f8651c73a60fe4c2c48294e09fcb6838fcf"
WEIGHT_SHA256 = "715fade13be8f229f8a70cc02066f656f2423a59effd0579197bbf57860e1378"
MODEL_REPO = "depth-anything/Depth-Anything-V2-Small"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest_path = DEST / "source-manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if (manifest["sourceCommit"] != SOURCE_COMMIT or
                manifest["checkpointRevision"] != MODEL_REVISION or
                manifest["checkpointSha256"] != WEIGHT_SHA256):
            raise ValueError("pinned DA-V2 source identity mismatch")
        for relative, digest in manifest["files"].items():
            path = (DEST / relative).resolve()
            if not path.is_relative_to(DEST.resolve()) or sha(path) != digest:
                raise ValueError("DA-V2 source/checkpoint drift: " + relative)
        print("DA-V2 Small source and checkpoint hashes verified", flush=True)
        return
    if args.check:
        raise FileNotFoundError(manifest_path)
    DEST.mkdir(parents=True, exist_ok=True)
    source_url = f"https://api.github.com/repos/DepthAnything/Depth-Anything-V2/git/trees/{SOURCE_COMMIT}?recursive=1"
    tree_bytes = fetch(source_url)
    tree = json.loads(tree_bytes)
    if tree.get("truncated"):
        raise ValueError("source tree was truncated")
    files = {}
    for member in tree["tree"]:
        relative = Path(member["path"])
        if member["type"] != "blob" or not (
                (relative.parts[0] == "depth_anything_v2" and relative.suffix == ".py") or
                relative.as_posix() in {"LICENSE", "README.md"}):
            continue
        target = (DEST / "upstream" / relative).resolve()
        if not target.is_relative_to((DEST / "upstream").resolve()):
            raise ValueError("source path escapes source directory")
        url = f"https://raw.githubusercontent.com/DepthAnything/Depth-Anything-V2/{SOURCE_COMMIT}/{relative.as_posix()}"
        content = fetch(url)
        git_hash = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        if git_hash != member["sha"]:
            raise ValueError("upstream source blob hash mismatch")
        if target.exists() and target.read_bytes() != content:
            raise ValueError("existing source differs: " + str(relative))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        files[target.relative_to(DEST).as_posix()] = sha(target)
        print("Source " + relative.as_posix(), flush=True)
    checkpoint = DEST / "depth_anything_v2_vits.pth"
    checkpoint_url = f"https://huggingface.co/{MODEL_REPO}/resolve/{MODEL_REVISION}/{checkpoint.name}"
    if not checkpoint.exists():
        print("Downloading official DA-V2 Small checkpoint (99.2 MB)", flush=True)
        payload = fetch(checkpoint_url)
        if hashlib.sha256(payload).hexdigest() != WEIGHT_SHA256:
            raise ValueError("downloaded checkpoint hash mismatch")
        checkpoint.write_bytes(payload)
    if sha(checkpoint) != WEIGHT_SHA256:
        raise ValueError("existing checkpoint hash mismatch")
    files[checkpoint.name] = WEIGHT_SHA256
    manifest = {
        "schemaVersion": 1, "modelId": "depth-anything-v2-small-relative-experiment",
        "sourceCommit": SOURCE_COMMIT, "sourceUrl": source_url,
        "sourceTreeSha256": hashlib.sha256(tree_bytes).hexdigest(),
        "checkpointRepository": MODEL_REPO, "checkpointRevision": MODEL_REVISION,
        "checkpointUrl": checkpoint_url, "checkpointSha256": WEIGHT_SHA256,
        "license": "Apache-2.0 (official Small checkpoint and source LICENSE)",
        "semantics": "relative inverse depth; larger is nearer; never metres",
        "promotionAllowed": False, "files": dict(sorted(files.items())),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Prepared immutable DA-V2 Small source/weights", flush=True)


if __name__ == "__main__":
    main()

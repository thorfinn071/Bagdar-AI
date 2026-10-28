import copy
import functools
import http.server
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock
import zipfile

import datasets as ds


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class DatasetTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "original"
        self.root.mkdir()
        self.paths = [
            "test/fixtures/spatial_safety/example/a.gz",
            "test/fixtures/spatial_safety/example/nested/b.png",
        ]
        for i, name in enumerate(self.paths):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(bytes(range(256)) * (i + 1))
        self.selection = self.base / "selection.json"
        self.selection.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "datasets": [
                        {
                            "id": "example",
                            "root": "test/fixtures/spatial_safety/example",
                            "suffixes": [".gz", ".png"],
                        }
                    ],
                }
            )
        )
        self.manifest = self.base / "manifest.json"
        self.bundles = self.base / "bundles"
        self.data = ds.create(
            self.root, self.selection, "test-v1", self.manifest, self.bundles
        )
        self.target = self.base / "target"
        self.target.mkdir()

    def archive(self):
        return self.bundles / self.data["datasets"][0]["archive"]["fileName"]

    def repin_archive(self):
        archive = self.data["datasets"][0]["archive"]
        archive["bytes"] = self.archive().stat().st_size
        archive["sha256"] = ds.digest(self.archive())

    def write_zip(self, entries):
        with zipfile.ZipFile(self.archive(), "w") as archive:
            for name, content in entries:
                archive.writestr(name, content)
        self.repin_archive()

    def test_roundtrip_same_paths_bytes_and_idempotent_without_source(self):
        data = ds.load_manifest(self.manifest)
        ds.restore(self.target, data, str(self.bundles))
        for name in self.paths:
            self.assertEqual((self.root / name).read_bytes(), (self.target / name).read_bytes())
        ds.restore(self.target, data, str(self.base / "missing-source"))
        self.assertFalse(list(self.target.glob(".bagdar-restore-*")))

    def test_deterministic_bundles_and_manifest_no_overwrite(self):
        second_manifest = self.base / "second.json"
        second = ds.create(
            self.root, self.selection, "test-v1", second_manifest, self.base / "second"
        )
        self.assertEqual(self.data, second)
        with self.assertRaises(ds.DatasetError):
            ds.create(self.root, self.selection, "test-v1", self.manifest, self.bundles)

    def test_existing_local_edit_is_preserved_before_any_restore(self):
        path = self.target / self.paths[-1]
        path.parent.mkdir(parents=True)
        path.write_bytes(b"local edit")
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))
        self.assertEqual(path.read_bytes(), b"local edit")
        self.assertFalse((self.target / self.paths[0]).exists())

    def test_archive_checksum_mismatch_leaves_destination_empty(self):
        with self.archive().open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))
        self.assertEqual(list(self.target.iterdir()), [])

    def test_member_checksum_mismatch_installs_none_of_the_bundle(self):
        self.write_zip(
            [
                (self.paths[0], (self.root / self.paths[0]).read_bytes()),
                (self.paths[1], b"x" * (self.root / self.paths[1]).stat().st_size),
            ]
        )
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))
        self.assertEqual(list(self.target.iterdir()), [])

    def test_unexpected_traversal_member_is_not_extracted(self):
        self.write_zip([("../escaped", b"bad"), (self.paths[0], b"bad")])
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))
        self.assertFalse((self.base / "escaped").exists())
        self.assertEqual(list(self.target.iterdir()), [])

    def test_duplicate_and_oversized_members_are_rejected(self):
        for entries in (
            [(self.paths[0], b"a"), (self.paths[0], b"b")],
            [(self.paths[0], b"too short"), (self.paths[1], b"also short")],
        ):
            with self.subTest(entries=entries):
                self.write_zip(entries)
                with self.assertRaises(ds.DatasetError):
                    ds.restore(self.target, self.data, str(self.bundles))
                self.assertEqual(list(self.target.iterdir()), [])

    def test_zip_symlink_is_rejected(self):
        with zipfile.ZipFile(self.archive(), "w") as archive:
            for i, name in enumerate(self.paths):
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.external_attr = (
                    (stat.S_IFLNK | 0o777) if i == 0 else (stat.S_IFREG | 0o644)
                ) << 16
                archive.writestr(info, (self.root / name).read_bytes())
        self.repin_archive()
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))

    def test_manifest_rejects_unsafe_paths_collisions_and_bad_hashes(self):
        mutations = [
            lambda d: d["datasets"][0]["files"][0].update(path="../escape"),
            lambda d: d["datasets"][0]["files"][0].update(path="lib/main.dart"),
            lambda d: d["datasets"][0]["files"][0].update(path="test/fixtures/spatial_safety/.git/config"),
            lambda d: d["datasets"][0]["files"][0].update(path="test/fixtures/spatial_safety/CON/a.gz"),
            lambda d: d["datasets"][0]["files"][0].update(sha256="bad"),
            lambda d: d["datasets"][0]["files"][0].update(bytes=-1),
            lambda d: d["datasets"][0]["archive"].update(fileName="../bundle.zip"),
            lambda d: d["datasets"].append(copy.deepcopy(d["datasets"][0])),
            lambda d: d["datasets"][0]["files"][1].update(path=self.paths[0].upper()),
            lambda d: d["datasets"][0]["files"][1].update(path=self.paths[0] + "/child"),
        ]
        for mutate in mutations:
            data = copy.deepcopy(self.data)
            mutate(data)
            self.manifest.write_text(json.dumps(data))
            with self.subTest(data=data), self.assertRaises(ds.DatasetError):
                ds.load_manifest(self.manifest)

    def test_selection_cannot_capture_source_or_secrets(self):
        self.selection.write_text(
            json.dumps({"schemaVersion": 1, "datasets": [{"id": "bad", "paths": [".env"]}]})
        )
        with self.assertRaises(ds.DatasetError):
            ds.create(self.root, self.selection, "test-v2", self.base / "bad.json", self.base / "bad")
        self.assertFalse((self.base / "bad").exists())

    def test_legacy_scope_allows_only_exact_recorded_paths_and_hashes(self):
        name = next(iter(ds.LEGACY_INPUTS))
        self.assertEqual(ds.relative(name, payload=True), name)
        with self.assertRaises(ds.DatasetError):
            ds.relative("scratch/private-recordings/clip.wav", payload=True)
        data = copy.deepcopy(self.data)
        data["datasets"][0]["files"][0]["path"] = name
        self.manifest.write_text(json.dumps(data))
        with self.assertRaises(ds.DatasetError):
            ds.load_manifest(self.manifest)

    def test_licenses_travel_with_bundle_and_can_remain_in_git(self):
        notice = "android/app/src/research/assets/voice_wake/LICENSE.txt"
        path = self.root / notice
        path.parent.mkdir(parents=True)
        path.write_bytes(b"License notice")
        selection = {
            "schemaVersion": 1,
            "datasets": [{"id": "license", "paths": [notice], "retainPaths": [notice]}],
        }
        self.selection.write_text(json.dumps(selection))
        result = ds.create(
            self.root, self.selection, "license-v1",
            self.base / "license.json", self.base / "licensed-bundle",
        )
        self.assertTrue(result["datasets"][0]["files"][0]["retainInGit"])
        ds.restore(self.target, result, str(self.base / "licensed-bundle"))
        self.assertEqual((self.target / notice).read_bytes(), b"License notice")

    def test_existing_directory_in_place_of_file_and_symlink_parent(self):
        (self.target / self.paths[0]).mkdir(parents=True)
        with self.assertRaises(ds.DatasetError):
            ds.restore(self.target, self.data, str(self.bundles))
        # Exercise link rejection without requiring Windows symlink privileges.
        with mock.patch.object(Path, "is_symlink", return_value=True):
            with self.assertRaises(ds.DatasetError):
                ds.local_path(self.target, self.paths[0])

    def test_missing_data_fails_verify_and_cli_returns_nonzero(self):
        with self.assertRaises(ds.DatasetError):
            ds.preflight(self.target, self.data["datasets"], require_all=True)
        result = subprocess.run(
            [
                sys.executable, str(Path(ds.__file__)), "verify",
                "--manifest", str(self.manifest), "--root", str(self.target),
            ],
            capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("payloads missing", result.stderr)
        with self.assertRaises(ds.DatasetError):
            ds.choose(self.data, ["unknown"])

    def test_http_fetch_and_content_addressed_cache(self):
        handler = functools.partial(QuietHandler, directory=str(self.bundles))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            ds.restore(self.target, self.data, f"http://127.0.0.1:{server.server_port}")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        cache = self.target / "output/dataset-cache"
        self.assertEqual(len(list(cache.glob("*.zip"))), 1)
        for name in self.paths:
            (self.target / name).unlink()
        ds.restore(self.target, self.data, f"http://127.0.0.1:{server.server_port}")
        self.assertFalse(list(cache.glob("tmp*")))

    def test_download_corruption_is_not_cached_or_installed(self):
        self.archive().write_bytes(b"invalid")
        handler = functools.partial(QuietHandler, directory=str(self.bundles))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.assertRaises(ds.DatasetError):
                ds.restore(self.target, self.data, f"http://127.0.0.1:{server.server_port}")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        self.assertEqual(list((self.target / "output/dataset-cache").iterdir()), [])
        self.assertFalse((self.target / self.paths[0]).exists())

    def test_requires_https_except_loopback_and_rejects_downgrade(self):
        for url in ("http://example.com/bundles", "ftp://example.com/bundles", "https://user:pass@example.com"):
            with self.subTest(url=url), self.assertRaises(ds.DatasetError):
                ds.check_url(url)
        request = ds.urllib.request.Request("https://example.com/archive.zip")
        with self.assertRaises(ds.DatasetError):
            ds.CheckedRedirect().redirect_request(
                request, None, 302, "", {}, "http://127.0.0.1/archive.zip"
            )


if __name__ == "__main__":
    unittest.main()

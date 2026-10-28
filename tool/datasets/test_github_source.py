import copy
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import urllib.request

import datasets as ds
import github_source as gh


class GitHubSourceTest(unittest.TestCase):
    def source(self):
        assets = [{
            "name": "bundle.zip", "size": 42, "id": 7, "state": "uploaded",
            "digest": "sha256:" + "a" * 64,
            "browser_download_url": "https://untrusted.example/file",
        }]
        with mock.patch.object(gh, "credential_token", return_value="unit-test-secret"):
            with mock.patch.object(
                gh.GitHubReleaseSource, "read_json",
                side_effect=[{"id": 9, "draft": False}, assets],
            ):
                return gh.GitHubReleaseSource("github-release:owner/repo@data-v4", Path.cwd())

    def test_environment_credentials_do_not_call_git(self):
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "unit-test-secret"}, clear=True):
            with mock.patch.object(gh.subprocess, "run") as command:
                self.assertEqual(gh.credential_token("owner/repo", Path.cwd()), "unit-test-secret")
                command.assert_not_called()

    def test_git_helper_receives_host_and_never_interacts(self):
        result = SimpleNamespace(returncode=0, stdout="username=user\npassword=unit-test-secret\n")
        with mock.patch.dict(os.environ, {}, clear=True):
            with mock.patch.object(gh.subprocess, "run", return_value=result) as command:
                self.assertEqual(gh.credential_token("owner/repo", Path.cwd()), "unit-test-secret")
                args = command.call_args.kwargs
                self.assertIn("host=github.com", args["input"])
                self.assertEqual(args["env"]["GCM_INTERACTIVE"], "never")
                self.assertNotIn("unit-test-secret", str(command.call_args))

    def test_missing_credentials_fail_without_echoing_helper_output(self):
        result = SimpleNamespace(returncode=1, stdout="diagnostic=unit-test-secret")
        with mock.patch.dict(os.environ, {}, clear=True):
            with mock.patch.object(gh.subprocess, "run", return_value=result):
                with self.assertRaises(gh.GitHubSourceError) as error:
                    gh.credential_token("owner/repo", Path.cwd())
                self.assertNotIn("unit-test-secret", str(error.exception))

    def test_credentials_are_not_forwarded_to_signed_asset_url(self):
        source = self.source()
        request = source.request(source.base + "/releases/assets/7", "application/octet-stream")
        self.assertEqual(request.unredirected_hdrs["Authorization"], "Bearer unit-test-secret")
        redirected = gh.ReleaseRedirect().redirect_request(
            request, None, 302, "", {}, "https://release-assets.githubusercontent.com/file"
        )
        self.assertIsNone(redirected.get_header("Authorization"))
        with self.assertRaises(gh.GitHubSourceError):
            gh.ReleaseRedirect().redirect_request(request, None, 302, "", {}, "http://example.com/file")

    def test_asset_uses_authenticated_api_not_server_supplied_url(self):
        source = self.source()
        row = {"fileName": "bundle.zip", "bytes": 42, "sha256": "a" * 64}
        with mock.patch.object(source.opener, "open", return_value=io.BytesIO(b"data")) as opened:
            source.open_asset(row)
        request = opened.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.github.com/repos/owner/repo/releases/assets/7")
        self.assertEqual(request.get_header("Accept"), "application/octet-stream")
        with self.assertRaises(gh.GitHubSourceError):
            source.request("https://untrusted.example/file", "application/octet-stream")

    def test_asset_size_digest_state_and_identity_checked_before_network(self):
        row = {"fileName": "bundle.zip", "bytes": 42, "sha256": "a" * 64}
        for change in ({"size": 43}, {"digest": "sha256:bad"}, {"state": "starter"}, {"id": -1}):
            source = self.source()
            source.assets["bundle.zip"].update(change)
            with mock.patch.object(source.opener, "open") as opened:
                with self.assertRaises(gh.GitHubSourceError):
                    source.open_asset(row)
                opened.assert_not_called()

    def test_invalid_release_selectors_are_rejected(self):
        for value in ("github-release:owner/repo@../tag", "github-release:https://example.com@tag"):
            with self.assertRaises(gh.GitHubSourceError):
                gh.GitHubReleaseSource(value, Path.cwd())
        with mock.patch.object(gh, "credential_token", return_value="unit-test-secret"):
            with mock.patch.object(gh.GitHubReleaseSource, "read_json", return_value={"id": 9, "draft": True}):
                with self.assertRaises(gh.GitHubSourceError):
                    gh.GitHubReleaseSource("github-release:owner/repo@tag", Path.cwd())

    def test_default_source_is_bound_to_exact_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = root / "manifest.json"
            manifest.write_bytes(b"manifest bytes")
            config = root / "source.json"
            config.write_text(json.dumps({
                "schemaVersion": 1, "source": "github-release:owner/repo@tag",
                "manifestSha256": ds.digest(manifest),
            }))
            with mock.patch.object(ds, "SOURCE_CONFIG", config):
                self.assertEqual(ds.configured_source(manifest), "github-release:owner/repo@tag")
                manifest.write_bytes(b"changed")
                with self.assertRaises(ds.DatasetError):
                    ds.configured_source(manifest)

    def test_authenticated_archive_still_requires_manifest_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder) / "cache"
            provider = mock.Mock()
            provider.open_asset.return_value = io.BytesIO(b"wrong bytes")
            row = {"fileName": "bundle.zip", "bytes": 11, "sha256": "a" * 64}
            with self.assertRaises(ds.DatasetError):
                ds.get_archive("github-release:owner/repo@tag", cache, row, github=provider)
            self.assertEqual(list(cache.iterdir()), [])


if __name__ == "__main__":
    unittest.main()

"""Authenticated GitHub release downloads without storing credentials in files."""

import json
import os
import re
import subprocess
import urllib.parse
import urllib.request


SOURCE = re.compile(
    r"github-release:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([A-Za-z0-9_.-]+)"
)


class GitHubSourceError(ValueError):
    pass


def credential_token(repository, root):
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    environment = os.environ.copy()
    environment.update(GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
    try:
        result = subprocess.run(
            ["git", "credential", "fill"],
            input=f"protocol=https\nhost=github.com\npath={repository}.git\n\n",
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GitHubSourceError("Git credential helper is unavailable") from error
    fields = dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )
    if result.returncode or not fields.get("password"):
        raise GitHubSourceError(
            "Authenticate Git with github.com or provide GITHUB_TOKEN with "
            "read access to the repository; credentials are never stored here."
        )
    return fields["password"]


class ReleaseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise GitHubSourceError("Refusing a non-HTTPS release redirect")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        # Signed asset URLs require no GitHub credentials.
        if redirected:
            redirected.remove_header("Authorization")
        return redirected


class GitHubReleaseSource:
    def __init__(self, source, root):
        match = SOURCE.fullmatch(source)
        if not match:
            raise GitHubSourceError("Expected github-release:OWNER/REPO@TAG")
        repository, tag = match.groups()
        self.base = f"https://api.github.com/repos/{repository}"
        self.token = credential_token(repository, root)
        self.opener = urllib.request.build_opener(ReleaseRedirect())
        release = self.read_json(
            f"{self.base}/releases/tags/{urllib.parse.quote(tag, safe='')}"
        )
        release_id = release.get("id")
        if type(release_id) is not int or release_id <= 0 or release.get("draft"):
            raise GitHubSourceError("Release is missing or still a draft")
        assets = self.read_json(
            f"{self.base}/releases/{release_id}/assets?per_page=100"
        )
        if not isinstance(assets, list) or len(assets) >= 100:
            raise GitHubSourceError("Invalid or excessive release asset listing")
        self.assets = {}
        for asset in assets:
            name = asset.get("name")
            if not isinstance(name, str) or name in self.assets:
                raise GitHubSourceError("Duplicate/invalid release asset name")
            self.assets[name] = asset

    def request(self, url, accept):
        if not url.startswith(self.base + "/"):
            raise GitHubSourceError("Release request escaped its repository")
        request = urllib.request.Request(
            url,
            headers={
                "Accept": accept,
                "User-Agent": "Bagdar-research-datasets",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        # urllib does not copy unredirected headers to the signed download URL.
        request.add_unredirected_header("Authorization", "Bearer " + self.token)
        return request

    def read_json(self, url):
        with self.opener.open(
            self.request(url, "application/vnd.github+json"), timeout=30
        ) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise GitHubSourceError("Release metadata is too large")
        return json.loads(raw)

    def open_asset(self, row):
        asset = self.assets.get(row["fileName"])
        if not asset or asset.get("size") != row["bytes"]:
            raise GitHubSourceError("Release asset is missing or has a different size")
        if asset.get("state") != "uploaded":
            raise GitHubSourceError("Release asset upload is incomplete")
        digest = asset.get("digest")
        if digest and digest != "sha256:" + row["sha256"]:
            raise GitHubSourceError("Release asset digest differs from the manifest")
        asset_id = asset.get("id")
        if type(asset_id) is not int or asset_id <= 0:
            raise GitHubSourceError("Invalid release asset identity")
        return self.opener.open(
            self.request(
                f"{self.base}/releases/assets/{asset_id}",
                "application/octet-stream",
            ),
            timeout=120,
        )

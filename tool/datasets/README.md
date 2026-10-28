# Research dataset bundles

Python 3.10+; standard library only. Run commands from the repository root.

## Published research release

The 23 bundles are published in the repository's
[private research release](https://github.com/thorfinn071/Bagdar-AI/releases/tag/research-data-2026-10-28-v4).
Repository visibility is unchanged. `source.json` binds that release to the exact
manifest. Payloads are provisioned at their original paths and excluded from
ordinary Git; metadata, source and small fixtures remain in the checkout.

The reviewed bundle directory also contains a copy of `manifest-v4.json` and
`SHA256SUMS.txt` for later publication and independent archive checks.

`manifest-v4.json` pins the version, original repository paths, sizes and SHA-256
hashes of every archived file and every ZIP. `selection-v4.json` records the
explicit scope used to prepare it. Sources, small fixtures, corpus metadata,
licenses, receipts and frozen source snapshots stay in Git.

The Vosk bundle includes its license, notices, README and model manifest.
These four files have `retainInGit: true`: they also remain directly available
in the repository.

The selection also contains exactly named legacy replay inputs and synthetic
history/depth corpora previously available only under ignored `scratch/`, plus
the three candidate ONNX artifacts required by the model-contract test.
`legacy-replay-inputs.json` locks their permitted paths and hashes. No arbitrary
scratch files or recordings are selected. One historical profiling executable
is retained for its recorded integrity check; the restore tool executes no
archive contents. Candidate models keep their existing provenance-review status.

## Verify the current data

```powershell
python tool/datasets/datasets.py list
python tool/datasets/datasets.py verify
```

Verification fails on missing or changed payloads. It does not skip tests,
regenerate evidence, change thresholds or establish physical-device readiness.

## Restore into a checkout

From a checkout with Python and Git available:

```powershell
python tool/datasets/datasets.py restore
```

Use `--root C:/path/to/checkout` to restore into another checkout. The destination
directory must already exist. All datasets are selected by default; add
`--dataset camera-visible-passage-v1` (repeatable) to choose particular bundles.
The complete developer/replay suites can require the complete corpus.

Override the configured source with `--source` and a local bundle directory,
an HTTPS base URL containing the exact archive filenames, or a GitHub release
selector described below. Remote downloads are cached by checksum under
`output/dataset-cache/`. HTTP is supported only on loopback for local testing.

The tool verifies the complete archive and every member before installing any
file from a bundle. It rejects unexpected/duplicate members, unsafe paths,
symbolic links, invalid sizes and checksum mismatches. Matching existing files
are retained; differing local files cause an error and are never overwritten.
Verified files are installed atomically using hard links on the destination
filesystem (for example NTFS or ext4). Completed bundles remain available if a
later bundle fails. Rerun the same command to continue.

The manifest is the trusted reference committed with the code; a download URL
does not authenticate a replacement manifest. Preserve the manifest in Git.

Private GitHub releases are supported with
`--source github-release:OWNER/REPO@TAG`. Authentication uses `GITHUB_TOKEN`,
`GH_TOKEN`, or Git's configured credential helper. Tokens are held in memory
and sent only to the GitHub API; signed asset redirects receive no credentials.
The repository visibility is unchanged. See
[the research notices](THIRD_PARTY_NOTICES.md) for bundled model provenance.

## Prepare a new version

First review the explicit selection. It covers large synthetic fixture families,
named large replay reports and the research speech model, not arbitrary
recordings or output directories.

```powershell
python tool/datasets/datasets.py create --selection tool/datasets/selection-v4.json --version NEW-VERSION --manifest PATH-TO-NEW-MANIFEST.json --bundle-dir output/research-data/NEW-VERSION
```

Replace the example values; version identifiers use lowercase letters, digits
and hyphens. Both output paths must be new. Creation never overwrites an
existing manifest or bundle directory. Sorted paths, fixed ZIP timestamps and
permissions make repeated builds deterministic with the same inputs/toolchain.
Already compressed payloads are stored without recompression.

Keep published versions immutable. A changed dataset gets a new selection,
manifest and version; do not update historical checksums to hide a mismatch.

## Publish a new dataset version

1. Preserve and review the prepared bundles and their licenses.
2. Publish the exact archive bytes to a durable, versioned download source.
3. Restore through that source into a checkout lacking the payloads; verify every
   hash, the full Flutter developer suite and relevant strict Core checks.
4. Only then add precise payload exclusions/remove those payloads from tracking.
   Keep metadata, small fixtures and frozen source snapshots in Git.
5. Update setup instructions with the verified source and review the commit.

Do not blanket-ignore `test/fixtures/` or `docs/_baseline_logs/`. Current replay
contracts depend on exact paths and identities. The repository's Git attributes
disable line-ending conversion for frozen evidence and packaged assets so a
Windows checkout preserves those identities.

Some live replay sources are also hash-pinned. Their targeted `-text` Git
attributes preserve the recorded bytes; ordinary source files keep the normal
line-ending policy. Do not rewrite historical checksums to accommodate checkout
conversion.

## Tool tests

```powershell
python -m unittest discover -s tool/datasets -p "test_*.py" -v
```

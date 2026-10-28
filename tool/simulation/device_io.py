"""ADB transport into the debuggable simulation app's own private directory."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tarfile
from pathlib import Path

PACKAGE = 'com.example.bagdar.simulation'


def adb_call(adb, serial, *args, **kwargs):
    return subprocess.run([str(adb), '-s', serial, *args], check=True, **kwargs)


def cache_matches(marker, manifest_hash, asset_count):
    return (isinstance(marker, dict) and marker.get('schemaVersion') == 1 and marker.get('manifestSha256') == manifest_hash
            and marker.get('assetCount') == asset_count)


def write_ready(adb, serial, manifest_hash, asset_count):
    import tempfile
    with tempfile.TemporaryDirectory(prefix='bagdar-ready-') as folder:
        path = Path(folder)/'inputs-ready.json'
        path.write_text(json.dumps({'schemaVersion': 1, 'manifestSha256': manifest_hash,
                                   'assetCount': asset_count}), encoding='utf-8')
        remote = '/data/local/tmp/bagdar-simulation-ready.json'
        adb_call(adb, serial, 'push', str(path), remote, capture_output=True)
        adb_call(adb, serial, 'shell', 'run-as', PACKAGE, 'cp', remote, 'files/simulation/inputs-ready.json')


def push(adb, serial, root):
    root = root.resolve()
    manifest = json.loads((root/'manifest.json').read_text(encoding='utf-8-sig'))
    paths = {'manifest.json', 'control.json'}
    for sequence in manifest['sequences']:
        for frame in sequence['frames']:
            paths.update(frame[k]['path'] for k in ('yuv', 'preview'))
    manifest_hash = hashlib.sha256((root/'manifest.json').read_bytes()).hexdigest()
    asset_count = len(paths)-2
    probe = subprocess.run([str(adb), '-s', serial, 'shell', '-T', 'run-as', PACKAGE,
                           'cat', 'files/simulation/inputs-ready.json'], capture_output=True)
    try:
        ready = json.loads(probe.stdout) if not probe.returncode else {}
    except json.JSONDecodeError:
        ready = {}
    reuse = cache_matches(ready, manifest_hash, asset_count)
    if reuse:
        paths = {'control.json'}
    adb_call(adb, serial, 'shell', 'run-as', PACKAGE, 'mkdir', '-p', 'files/simulation')
    # A regular archive avoids Windows console/ADB stdin transformations.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='bagdar-simulation-') as temporary:
        archive = Path(temporary)/'inputs.tar.gz'
        with tarfile.open(archive, mode='w:gz', compresslevel=1) as tar:
            for relative in sorted(paths):
                path = (root/relative).resolve()
                if not path.is_relative_to(root) or not path.is_file():
                    raise ValueError('Unsafe runtime asset path')
                tar.add(path, arcname=relative, recursive=False)
        remote_archive = '/data/local/tmp/bagdar-simulation-inputs.tar.gz'
        adb_call(adb, serial, 'push', str(archive), remote_archive)
        adb_call(adb, serial, 'shell', 'run-as', PACKAGE, 'tar', '-xzf', remote_archive, '-C', 'files/simulation')
    remote = adb_call(adb, serial, 'exec-out', 'run-as', PACKAGE, 'cat',
                      'files/simulation/manifest.json', capture_output=True).stdout
    if hashlib.sha256(remote).digest() != hashlib.sha256((root/'manifest.json').read_bytes()).digest():
        raise ValueError('ADB transport did not preserve the manifest')
    write_ready(adb, serial, manifest_hash, asset_count)
    print(f'Pushed {len(paths)} inputs into {PACKAGE}/files/simulation; cached pixels reused={reuse}')


def certify_cache(adb, serial, corpus):
    evaluation = json.loads((corpus/'evaluation.json').read_text(encoding='utf-8'))
    if not evaluation.get('allSelectedReceiptsComplete') or evaluation['selectedSequences'] != evaluation['expectedSequences']:
        raise ValueError('A complete corpus run is required to certify an existing cache')
    manifest_path = corpus/'runtime/manifest.json'
    digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    if evaluation['runtimeManifestSha256'] != digest:
        raise ValueError('Evaluation belongs to a different input corpus')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    paths = {f[k]['path'] for s in manifest['sequences'] for f in s['frames'] for k in ('yuv', 'preview')}
    remote = adb_call(adb, serial, 'shell', '-T', 'run-as', PACKAGE, 'sha256sum',
                      'files/simulation/manifest.json', capture_output=True).stdout.decode().split()[0]
    if remote != digest:
        raise ValueError('Emulator contains a different corpus')
    write_ready(adb, serial, digest, len(paths))
    print('Existing app-validated inputs certified for reuse')


def collect(adb, serial, corpus):
    manifest = json.loads((corpus/'runtime/manifest.json').read_text(encoding='utf-8-sig'))
    folder = corpus/'app-reports'
    folder.mkdir(exist_ok=True)
    count = 0
    for sequence in manifest['sequences']:
        identifier = sequence['id']
        if not identifier or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in identifier):
            raise ValueError('Unsafe sequence identifier')
        result = subprocess.run([str(adb), '-s', serial, 'shell', '-T', 'run-as', PACKAGE,
            'cat', f'files/simulation/run-{identifier}.json'], capture_output=True)
        if result.returncode:
            continue
        report = json.loads(result.stdout)
        if report['sequenceId'] != identifier:
            raise ValueError('Unexpected report identity')
        (folder/f'run-{identifier}.json').write_bytes(result.stdout)
        count += 1
    print(f'Collected {count}/{len(manifest["sequences"])} application receipts')
    for name in ('batch-progress.json', 'batch-complete.json'):
        result = subprocess.run([str(adb), '-s', serial, 'shell', '-T', 'run-as', PACKAGE,
            'cat', f'files/simulation/{name}'], capture_output=True)
        if not result.returncode:
            json.loads(result.stdout)
            (folder/name).write_bytes(result.stdout)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['push', 'collect', 'certify-cache'])
    p.add_argument('root', type=Path)
    p.add_argument('--adb', required=True, type=Path)
    p.add_argument('--serial', default='emulator-5554')
    a = p.parse_args()
    {'push': push, 'collect': collect, 'certify-cache': certify_cache}[a.action](a.adb, a.serial, a.root)

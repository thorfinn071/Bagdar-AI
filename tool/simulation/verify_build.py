"""Bind source hashes, the built APK and the APK actually installed in the emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def verify(receipt, adb, serial):
    data = json.loads(receipt.read_text(encoding='utf-8-sig'))
    for relative, expected in data['sourceHashes'].items():
        path = (ROOT/relative).resolve()
        if not path.is_relative_to(ROOT) or digest(path) != expected:
            raise ValueError(f'Build source changed: {relative}')
    apk = ROOT/'build/app/outputs/flutter-apk/app-simulation-debug.apk'
    if digest(apk) != data['apkSha256']:
        raise ValueError('Built APK does not match the build receipt')
    base = [str(adb), '-s', serial, 'shell']
    packages = subprocess.check_output(base+['pm', 'path', 'com.example.bagdar.simulation'], text=True, timeout=30)
    paths = [p.removeprefix('package:').strip() for p in packages.splitlines() if p.startswith('package:')]
    if len(paths) != 1 or not paths[0].endswith('/base.apk'):
        raise ValueError('Expected one installed simulation APK')
    installed = subprocess.check_output(base+['sha256sum', paths[0]], text=True, timeout=60).split()[0]
    if installed != data['apkSha256']:
        raise ValueError('Installed APK differs from the verified build')
    result = {'apkSha256': installed, 'sourceFilesVerified': len(data['sourceHashes']),
              'installedPackage': 'com.example.bagdar.simulation', 'device': serial,
              'physicalDeviceValidation': 'not_run', 'promotionAllowed': False}
    target = receipt.with_name('installed-build-verification.json')
    target.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--receipt', required=True, type=Path)
    p.add_argument('--adb', required=True, type=Path)
    p.add_argument('--serial', default='emulator-5554')
    a = p.parse_args()
    verify(a.receipt, a.adb, a.serial)

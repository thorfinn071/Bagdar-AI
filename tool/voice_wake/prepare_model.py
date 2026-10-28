"""Install only the pinned candidate into research assets; never downloads at runtime."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

POLICY = json.loads(Path(__file__).with_name('policy.json').read_text(encoding='utf-8'))

def prepare(archive: Path, destination: Path):
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != POLICY['archiveSha256']:
        raise ValueError('archive SHA-256 mismatch')
    model_id = POLICY['modelId']
    files = []
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            parts = PurePosixPath(entry.filename).parts
            if not parts or parts[0] != model_id or '..' in parts or '\\' in entry.filename:
                raise ValueError('unexpected archive path')
            if entry.is_dir():
                continue
            relative = PurePosixPath(*parts[1:])
            if not relative.parts or entry.file_size > 200_000_000:
                raise ValueError('invalid model file')
            data = source.read(entry)
            files.append({'path': str(relative), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
            target = destination / str(relative)
            if target.exists() and target.read_bytes() != data:
                raise ValueError(f'refusing to overwrite different file: {target}')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    manifest = dict(POLICY, files=files)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return {'modelId': model_id, 'files': len(files), 'bytes': sum(f['bytes'] for f in files), 'archiveSha256': digest}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--destination', type=Path, default=Path('android/app/src/research/assets/voice_wake'))
    args = parser.parse_args()
    print(json.dumps(prepare(args.archive, args.destination), indent=2))

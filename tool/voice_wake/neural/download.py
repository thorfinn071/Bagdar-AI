"""Fetch public synthesis/data sources at pinned revisions; no app runtime downloads."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).parent
def fetch(url, target, expected_md5=None):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        temporary = target.with_name(target.name + '.partial')
        with urllib.request.urlopen(url, timeout=90) as response, temporary.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        temporary.replace(target)
    data = target.read_bytes()
    if expected_md5 and hashlib.md5(data).hexdigest() != expected_md5:
        raise ValueError(f'source digest mismatch: {target.name}')
    return {'path': str(target), 'url': url, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

def download(output):
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    files = []
    def voice(item):
        key, metadata = item
        results = []
        for name, entry in metadata['files'].items():
            url = f"https://huggingface.co/{sources['repo']}/resolve/{sources['revision']}/{name}"
            record = fetch(url, output / 'voices' / key / Path(name).name, entry['md5_digest'])
            results.append(dict(record, voice=key))
        print('downloaded', key, flush=True)
        return results
    with ThreadPoolExecutor(max_workers=3) as pool:
        for results in pool.map(voice, sources['voices'].items()):
            files.extend(results)
    url = f"https://codeload.github.com/Jakobovski/free-spoken-digit-dataset/zip/{sources['fsddRevision']}"
    archive = output / 'fsdd.zip'
    files.append(fetch(url, archive))
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            parts = Path(member.filename).parts
            if member.is_dir() or not (member.filename.endswith('.wav') or Path(member.filename).name in ['README.md', 'metadata.py', 'LICENSE']):
                continue
            if '..' in parts or member.filename.startswith('/'):
                raise ValueError('invalid public dataset path')
            target = output / 'fsdd' / Path(*parts[1:])
            if not target.resolve().is_relative_to((output / 'fsdd').resolve()) or member.file_size > 5_000_000:
                raise ValueError('public dataset entry outside expected directory or size limit')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read(member))
    result = {'schema': 1, 'piperRevision': sources['revision'], 'fsddRevision': sources['fsddRevision'], 'files': files}
    (output / 'download-lock.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('pinned public sources ready', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    download(parser.parse_args().output)

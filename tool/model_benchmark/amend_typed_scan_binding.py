"""Preserve rejected v1 evidence and seal the metadata-binding correction."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/typed-scan-transport-2026-10-11'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


v1_path = OUT / 'preregistration-v1.json'
v1 = json.loads(v1_path.read_bytes())
assert (OUT / 'preregistration.json').read_bytes() == v1_path.read_bytes()
assert not (OUT / 'preregistration-v2.json').exists()
redirects = {}
paths = set()
for relative, digest in v1['sources'].items():
    current = ROOT / relative
    if sha(current) != digest:
        archived = OUT / 'sources-v1' / (relative.replace('/', '__') + '.snapshot')
        assert sha(archived) == digest, relative
        redirect = archived.relative_to(ROOT).as_posix()
        redirects[relative] = redirect
        paths.add(redirect)
        paths.add(relative)
    else:
        paths.add(relative)
for p in (OUT / 'sources-v1').iterdir():
    paths.add(p.relative_to(ROOT).as_posix())
paths.update([
    'test/camera_typed_binding_regression_test.dart',
    'tool/model_benchmark/amend_typed_scan_binding.py',
    'scratch/typed-scan-transport-binding-before-fix.log',
])
for name in ['preregistration-v1.json', 'parity-v1.json', 'parity-validation-v1.json',
             'elapsed-v1.json', 'elapsed-validation-v1.json', 'profile-typed-scan-v1.exe']:
    paths.add((OUT / name).relative_to(ROOT).as_posix())
amendment = {'reason': 'v1 allowed accidental metadata/payload pairing mismatch; nine pre-fix regressions failed',
    'correction': '32-byte fingerprint binds original complete metadata bits to published payload; receiver rejects mismatch',
    'notAuthentication': True, 'pixelValuesOrModelsChanged': False,
    'ttlChanged': False, 'scoringCasesChanged': False,
    'v1SourceRedirects': redirects, 'priorPreregistrationSha256': sha(v1_path),
    'promotionAllowed': False}
amendment_path = OUT / 'binding-amendment.json'
with amendment_path.open('x', encoding='utf-8') as f:
    f.write(json.dumps(amendment, indent=2) + '\n')
paths.add(amendment_path.relative_to(ROOT).as_posix())
result = {'scope': 'v2 metadata-bound immutable typed publication; full ordinary-camera objective remains open',
    'amendmentSha256': sha(amendment_path), 'promotionAllowed': False,
    'sources': {p: sha(ROOT / p) for p in sorted(paths)}}
encoded = (json.dumps(result, indent=2) + '\n').encode()
(OUT / 'preregistration-v2.json').write_bytes(encoded)
(OUT / 'preregistration.json').write_bytes(encoded)
print(json.dumps({'frozenFiles': len(paths), 'changedSources': list(redirects),
    'v1Archived': True, 'promotionAllowed': False}, indent=2))

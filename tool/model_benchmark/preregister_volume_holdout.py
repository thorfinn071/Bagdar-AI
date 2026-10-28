"""Seal source identities before producing any holdout capture."""
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/volume-holdout-2026-10-10'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    target = OUT / 'preregistration.json'
    assert not target.exists(), 'Preregistration is immutable'
    assert not (OUT / 'corpus').exists(), 'Must precede capture export'
    prior = ROOT / 'scratch/evidence-authority-fix-2026-10-10/validation.json'
    validated = json.loads(prior.read_text())
    assert validated['passed'] and validated['promotionAllowed'] is False
    for p, h in validated['sourceSha256'].items():
        assert sha(ROOT / p) == h, f'Prior validated source drift: {p}'
    frozen = dict(validated['sourceSha256'])
    for p in sorted((ROOT / 'lib').rglob('*.dart')):
        frozen[p.relative_to(ROOT).as_posix()] = sha(p)
    generator = ROOT / 'tool/blender/generate_volume_holdout.py'
    source_list = next(ast.literal_eval(node.value) for node in ast.parse(generator.read_text()).body
                       if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'SOURCES' for t in node.targets))
    OUT.mkdir(parents=True, exist_ok=True)
    receipt = {'schemaVersion': 1, 'sealedAtUtc': datetime.now(timezone.utc).isoformat(),
               'priorValidationSha256': sha(prior), 'preregisterToolSha256': sha(__file__),
               'frozenSourceSha256': frozen,
               'generatorSourceSha256': {p: sha(ROOT / p) for p in source_list},
               'captureCount': 84, 'noRuntimeTuningAfterSeal': True,
               'promotionAllowed': False, 'ordinaryCameraWired': False}
    target.write_text(json.dumps(receipt, indent=2) + '\n')
    print('SEALED', len(frozen), 'runtime/prior source files before holdout export')


if __name__ == '__main__': main()

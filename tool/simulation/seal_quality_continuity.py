"""Verify and seal the final software experiment without promoting a candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def seal(continuity, output):
    lab = ROOT/'output/simulation-lab'
    quality = lab/'quality-observer-v1'
    observer = json.loads((quality/'observer.json').read_text())
    summary = json.loads((quality/'observer-summary.json').read_text())
    build = json.loads((continuity/'build-receipt.json').read_text(encoding='utf-8-sig'))
    installed = json.loads((continuity/'installed-build-verification.json').read_text())
    evaluation = json.loads((continuity/'continuity-evaluation.json').read_text())
    if (observer['candidateSourceSha256'] != digest(ROOT/'lib/research/image_quality_observer.dart') or
            observer['candidateSourceSha256'] != digest(quality/'candidate-frozen.dart.txt') or
            summary['observerSha256'] != digest(quality/'observer.json')):
        raise ValueError('Candidate/result identity changed')
    if (observer['corpusManifestSha256'] != digest(quality/'manifest.json') or
            observer['protocolSha256'] != digest(quality/'protocol.json') or
            observer['baselineSha256'] != digest(quality/'baseline.json') or
            observer['scorerSourceSha256'] != digest(quality/'scorer-executed.dart.txt')):
        raise ValueError('Frozen experiment/scorer identity changed')
    if digest(ROOT/'lib/utils/blur_detector.dart') != 'd7cbef341199a793a9226b9dd42966d1094dd47f1f2e92ae0c1f0da07956cf0b':
        raise ValueError('Production blur implementation changed')
    for relative, expected in build['sourceHashes'].items():
        path = (ROOT/relative).resolve()
        if not path.is_relative_to(ROOT) or digest(path) != expected:
            raise ValueError(f'Build source drift: {relative}')
    if installed['apkSha256'] != build['apkSha256'] or digest(ROOT/'build/app/outputs/flutter-apk/app-simulation-debug.apk') != build['apkSha256']:
        raise ValueError('APK identity mismatch')
    if evaluation['manifestSha256'] != digest(continuity/'runtime/manifest.json'):
        raise ValueError('Foreign continuity evaluation')
    breadth = json.loads((lab/'breadth-v1/evaluation.json').read_text())
    if (breadth['runtimeManifestSha256'] != digest(lab/'breadth-v1/runtime/manifest.json') or
            not breadth['allSelectedReceiptsComplete']):
        raise ValueError('Incomplete or foreign breadth replay')
    counts = {}
    for name in ('normal', 'simulation'):
        log = (lab/f'observer-flutter-{name}-tests.log').read_text(encoding='utf-8')
        matches = re.findall(r'\+(\d+): All tests passed!', log)
        if not matches or 'Some tests failed.' in log: raise ValueError(f'Incomplete Flutter log: {name}')
        counts[name] = int(matches[-1])
    log = (lab/'observer-python-tests.log').read_text(encoding='utf-8')
    match = re.search(r'Ran (\d+) tests', log)
    if not match or '\nOK\n' not in log.replace('\r\n', '\n'):
        raise ValueError('Python tests did not complete')
    counts['python'] = int(match[1])
    analysis = lab/'observer-analysis.log'
    if 'No issues found!' not in analysis.read_text(): raise ValueError('Analyzer did not pass')
    files = [quality/n for n in ('manifest.json', 'protocol.json', 'candidate-frozen.dart.txt',
             'baseline.json', 'observer.json', 'observer-summary.json', 'report.md', 'scorer-executed.dart.txt')]
    files += [continuity/n for n in ('protocol.json', 'continuity-provenance.json', 'build-receipt.json',
              'installed-build-verification.json', 'continuity-evaluation.json', 'controller-executed.py.txt')]
    files += list((continuity/'app-reports').glob('*.json'))
    files += [lab/n for n in ('observer-flutter-normal-tests.log', 'observer-flutter-simulation-tests.log',
                              'observer-python-tests.log', 'observer-analysis.log')]
    files += [ROOT/'docs/quality-and-continuity-evaluation-2026-10-27.md',
              ROOT/'docs/quality-and-continuity-implementation-plan-2026-10-27.md',
              ROOT/'docs/stationary-device-acceptance-checklist-2026-10-27.md',
              lab/'breadth-v1/render-manifest.json', lab/'breadth-v1/runtime/manifest.json',
              lab/'breadth-v1/annotations.json', lab/'breadth-v1/evaluation.json',
              lab/'breadth-v1/build-receipt.json', lab/'breadth-v1/installed-build-verification.json']
    files += list((lab/'breadth-v1/app-reports').glob('*.json'))
    for folder in ('continuity-v1-run1', 'continuity-v1-run2', 'continuity-v1-run3', 'continuity-v1-run4'):
        files.append(lab/folder/'continuity-evaluation.json')
    files += [lab/'continuity-v1-run5/recovered-evaluation.json', lab/'continuity-v1-run5/run.log']
    result = {'schemaVersion': 1, 'promotionAllowed': False,
              'researchObserver': 'implemented_evaluated_not_suitable_for_production',
              'continuitySoftwareProbe': 'pass' if evaluation['softwareProbeChecksPassed'] else 'failed',
              'continuityRunId': evaluation['runId'], 'apkSha256': build['apkSha256'],
              'sourceFilesVerified': len(build['sourceHashes']), 'checks': counts,
              'breadth': '8/8 app receipts complete, 56 delivered frames; perception quality not established',
              'physicalCamera': 'not_run', 'physicalAudio': 'not_run', 'talkBack': 'not_run',
              'controlledWalking': 'not_run', 'modelCorrectness': 'not_established',
              'fileHashes': {p.relative_to(ROOT).as_posix(): digest(p) for p in files}}
    output.mkdir(parents=True, exist_ok=False)
    (output/'receipt.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'fileHashes'}, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('continuity', type=Path); p.add_argument('output', type=Path)
    a = p.parse_args(); seal(a.continuity.resolve(), a.output.resolve())

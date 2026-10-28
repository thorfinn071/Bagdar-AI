"""Separate elapsed risk availability from cheap unknown/rejected outcomes."""
import json
import platform
from pathlib import Path
from statistics import median
import math

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs'


def percentiles(values):
    values = sorted(values)
    return {'count': len(values), 'p50': median(values) if values else None,
            'p95': values[math.ceil(len(values) * .95) - 1] if values else None,
            'max': values[-1] if values else None}


def summarize(path):
    report = json.loads(path.read_text())
    rows = report['frames']
    risk = lambda r: r['admitted'] and r.get('result', {}).get('addsMotionRisk')
    reference = [r for r in rows if r['functionalReferenceAddsMotionRisk']]
    test = [r for r in reference if r['layoutId'].startswith('test-')]
    fresh = [r for r in reference if risk(r)]
    computations = report.get('computationDiagnostics', [])
    if any(risk(r) and r['ageAtReleaseUs'] > 100000 for r in rows):
        raise ValueError('Stale risk release')
    if report['summary']['freeSpaceCertifiedFrames'] or report['promotionAllowed']:
        raise ValueError('Clearance or promotion authority')
    return {
        'report': path.relative_to(ROOT).as_posix(),
        'frames': len(rows),
        'admitted': report['summary']['admitted'],
        'referenceRiskFrames': len(reference),
        'freshRiskFrames': len(fresh),
        'testReferenceRiskFrames': len(test),
        'testFreshRiskFrames': sum(bool(risk(r)) for r in test),
        'approachRiskPairs': report['summary']['approachRiskPairs'],
        'timingOrPairResetLosses': len(reference) - len(fresh),
        'freshRiskAgeMs': percentiles([r['ageAtReleaseUs'] / 1000 for r in fresh]),
        'allOutcomeAgeMs': report['summary']['ageAtReleaseMs'],
        'nnWaitMs': percentiles([r['nnWaitMs'] for r in rows if r['nnWaitMs'] is not None]),
        'deadlineRepliesMissingAtOutcome': report['summary']['workerComputationsNotReturnedBeforeDeadline'],
        'returnedComputationMs': percentiles([r['workerComputeUs'] / 1000 for r in computations]),
        'lateReturnedComputations': sum(not r['completedBeforeDeadline'] for r in computations),
        'packingMs': percentiles([r['packingUs'] / 1000 for r in computations]),
        'transportQueueAndDeliveryMs': percentiles([r['transportQueueAndDeliveryUs'] / 1000 for r in computations]),
        'stageMs': {key: percentiles([r['stagesUs'][key] / 1000 for r in computations
                                    if key in r['stagesUs']])
                    for key in ('materialize', 'features', 'matchingAndBounds',
                                'nativeMatch', 'nativeFrameCopy')},
        'preparationTotalMs': report['summary']['numericPreparationTotalMs'],
        'ownerTimerEvents': report['summary']['ownerEventsDuringCompute'],
        'diagnosticOverflow': report.get('diagnosticOverflow'),
        'staleReleases': report['summary']['staleReleases'],
        'clearances': report['summary']['freeSpaceCertifiedFrames'],
    }


def main():
    trials = {}
    for mode in ('elapsed', 'elapsed-nn'):
        trials[mode] = {name: [summarize(OUT / f'camera_fast_motion_load_{mode}_{name}_{r}.json')
                             for r in range(3)] for name in ('baseline', 'native')}
    native = trials['elapsed-nn']['native']
    gate = all(r['testFreshRiskFrames'] == r['testReferenceRiskFrames'] == 30
               and r['approachRiskPairs'] == 18 and r['freshRiskFrames'] == 54
               and r['staleReleases'] == r['clearances'] == 0 for r in native)
    output = {'scope': 'three alternating desktop trials; known synthetic regression; no phone capture',
              'platform': platform.platform(), 'alternatingOrder': True, 'measuredRounds': 3,
              'promotionAllowed': False, 'newIndependentHoldout': False,
              'timelyRiskGateMet': gate, 'trials': trials}
    (OUT / 'camera_fast_motion_load_comparison.json').write_text(
        json.dumps(output, indent=2) + '\n')
    for mode, names in trials.items():
        for name, runs in names.items():
            print(mode, name, 'test timely:', [r['testFreshRiskFrames'] for r in runs],
                  'all timely:', [r['freshRiskFrames'] for r in runs])
    print('Timely known-risk gate:', gate)


if __name__ == '__main__':
    main()

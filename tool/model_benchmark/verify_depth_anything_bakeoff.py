"""Recheck every artifact and parity result without rerunning neural inference."""
from pathlib import Path

import numpy as np

from depth_candidate_common import (CORPUS, EXPERIMENT, MODEL_ROOT, ROOT, checked,
                                    load_frames, parity, read, save, sha)


def verify():
    inference = read(EXPERIMENT / 'inference-report.json')
    replay = read(EXPERIMENT / 'shadow-runtime-report.json')
    exports = read(MODEL_ROOT / 'export-manifest.json')
    source = read(MODEL_ROOT / 'source-manifest.json')
    controls = read(EXPERIMENT / 'production-controls-before.json')
    corpus, frames = load_frames()
    assert inference['promotionAllowed'] is False and replay['promotionAllowed'] is False
    assert exports['promotionAllowed'] is False and source['promotionAllowed'] is False
    assert inference.get('failedVariant') is None and inference['allConversionParityPassed']
    for key, path in (('sourceManifestSha256', MODEL_ROOT / 'source-manifest.json'),
                      ('exportManifestSha256', MODEL_ROOT / 'export-manifest.json'),
                      ('corpusManifestSha256', CORPUS / 'corpus-manifest.json'),
                      ('scriptSha256', ROOT / 'tool/model_benchmark/run_depth_anything_bakeoff.py'),
                      ('helperSha256', ROOT / 'tool/model_benchmark/depth_candidate_common.py')):
        assert inference[key] == sha(path), (key, path)
    for relative, digest in source['files'].items():
        checked(MODEL_ROOT, relative, digest)
    for artifact in exports['artifacts'].values():
        if 'paramPath' in artifact:
            checked(ROOT, artifact['paramPath'], artifact['paramSha256'])
            checked(ROOT, artifact['binPath'], artifact['binSha256'])
            stem = Path(artifact['paramPath']).stem
            log = EXPERIMENT / f'conversion_logs/{stem}.txt'
            assert sha(log) == artifact['conversionLogSha256']
            assert not any(s in log.read_text() for s in
                           ('not supported', 'not implemented', 'unsupported operator'))
        else:
            checked(ROOT, artifact['path'], artifact['sha256'])
    for relative, digest in controls.items():
        checked(ROOT, relative, digest)
    source_frames = {(f['sceneId'], f['frameIndex']): f for f in frames}
    variants = {v['variantId']: v for v in inference['variants']}
    assert len(variants) == 10
    maps = {}
    for identity, variant in variants.items():
        seen = set()
        for row in variant['frames']:
            key = (row['sceneId'], row['frameIndex'])
            assert key not in seen
            seen.add(key)
            source_frame = source_frames[key]
            assert row['rgbSha256'] == source_frame['rgb']['sha256']
            assert row['expectedAction'] == source_frame['expectedAction']
            assert row['capturedOffsetMs'] == source_frame['capturedOffsetMs']
            path = checked(EXPERIMENT, row['mapPath'], row['mapSha256'])
            maps[(identity, key)] = np.fromfile(path, dtype='<f4').reshape(256, 256)
        assert seen == source_frames.keys()
    parity_rows = []
    for identity, variant in variants.items():
        if variant['backend'] in ('torch', 'midas'):
            continue
        for row in variant['frames']:
            key = (row['sceneId'], row['frameIndex'])
            reference = f"dav2_torch_short{variant['shortSide']}"
            result = parity(maps[(reference, key)], maps[(identity, key)])
            assert result['passed'], (identity, key, result)
            assert result == row['conversionParity']
            parity_rows.append(result)
    for key, path in (('inferenceReportSha256', EXPERIMENT / 'inference-report.json'),
                      ('testSha256', ROOT / 'test/depth_anything_shadow_bakeoff_test.dart'),
                      ('adapterSha256', ROOT / 'lib/services/experimental_relative_depth_replay_provider.dart'),
                      ('yoloDiagnosticSha256', ROOT / 'docs/_baseline_logs/blender_context_detector_diagnostic.json')):
        assert replay[key] == sha(path), (key, path)
    assert replay['corpusManifestSha256'] == inference['corpusManifestSha256']
    assert len(replay['variants']) == 5
    control = next(v['summary'] for v in replay['variants'] if v['variantId'] == 'midas_ncnn_control')
    assert control['unsafeContinueFrames'] == 0
    table = []
    for variant in replay['variants']:
        rows = variant['frames']
        assert {(r['sceneId'], r['frameIndex']) for r in rows} == source_frames.keys()
        assert len(rows) == 18 and all(r['delivery'] == 'shadow' for r in rows)
        hazards = [r for r in rows if r['expectedAction'] == 'stopNow']
        safe = [r for r in rows if r['expectedAction'] == 'continueForward']
        stopped = sum(r['plannedAction'] == 'stopNow' for r in hazards)
        unsafe = sum(r['plannedAction'] == 'continueForward' for r in hazards)
        false_stops = sum(r['plannedAction'] == 'stopNow' for r in safe)
        expected = {'hazardFrames': len(hazards), 'hazardFramesWithStop': stopped,
                    'hazardFramesWithoutStop': len(hazards) - stopped,
                    'unsafeContinueFrames': unsafe, 'passableFrames': len(safe),
                    'falseStopFrames': false_stops}
        assert variant['summary'] == expected
        reasons = []
        if unsafe:
            reasons.append('unsafe-continue-on-hazard')
        if stopped < control['hazardFramesWithStop']:
            reasons.append('hazard-stop-regression')
        if false_stops > control['falseStopFrames']:
            reasons.append('false-stop-regression')
        assert variant['qualityAdmission']['passed'] == (not reasons)
        assert variant['qualityAdmission']['rejectionReasons'] == reasons
        model = variants[variant['variantId']]
        table.append({'variantId': variant['variantId'], **expected, **model['summary'],
                      'qualityAdmission': variant['qualityAdmission']})
    receipt = {'schemaVersion': 1, 'verifiedMaps': len(maps),
               'verifiedConversionComparisons': len(parity_rows),
               'verifiedShadowFrames': sum(len(v['frames']) for v in replay['variants']),
               'minimumParityRho': min(r['rankRho'] for r in parity_rows),
               'maximumParityNormalizedMAE': max(r['normalizedMeanAbsoluteError'] for r in parity_rows),
               'maximumParityNormalizedP99': max(r['normalizedP99AbsoluteError'] for r in parity_rows),
               'inferenceReportSha256': sha(EXPERIMENT / 'inference-report.json'),
               'shadowReportSha256': sha(EXPERIMENT / 'shadow-runtime-report.json'),
               'verifierSha256': sha(Path(__file__)), 'productionControlsUnchanged': True,
               'promotionAllowed': False, 'androidDevice': 'not_run', 'comparison': table}
    save(EXPERIMENT / 'verification-receipt.json', receipt)
    print(f"Verified {len(maps)} real maps, {len(parity_rows)} conversion comparisons, 90 shadow frames")
    for row in table:
        print(f"{row['variantId']}: stop {row['hazardFramesWithStop']}/12, "
              f"false stop {row['falseStopFrames']}/6, unsafe continue {row['unsafeContinueFrames']}; "
              f"desktop p50/p95 {row['imageToMapP50Ms']:.1f}/{row['imageToMapP95Ms']:.1f} ms")


if __name__ == '__main__':
    verify()

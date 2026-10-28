"""Prepare and evaluate one stationary ARKit capture; never authorize guidance.

Mount measurements describe nominal, conditional geometry. Their tolerances
are retained but not converted into physical calibration or whole-pixel bounds.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

from arkit_capture import AUTHORITY, CaptureError, audit, load_json, pose_matrix, require
from arkit_experiment import protocol

ROOT = Path(__file__).resolve().parents[2]
MISSING_EVIDENCE = [
    'physical_metric_error_bounds', 'physical_rgb_depth_alignment',
    'independent_floor_reference', 'native_clock_binding',
    'whole_pixel_first_return_bounds', 'current_whole_body_and_floor_coverage',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    with path.open('x', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, indent=2, allow_nan=False)
        f.write('\n')


def multiply(a, b):
    return [sum(a[4*r+k]*b[4*k+c] for k in range(4)) for r in range(4) for c in range(4)]


def rigid_inverse(m):
    result = [0.] * 16
    for r in range(3):
        for c in range(3):
            result[4*r+c] = m[4*c+r]
        result[4*r+3] = -sum(m[4*k+r]*m[4*k+3] for k in range(3))
    result[15] = 1.
    return result


def rotation(axis, degrees):
    t = math.radians(degrees)
    c, s = math.cos(t), math.sin(t)
    if axis == 'x':
        return [1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1]
    return [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def finite(value, name):
    require(type(value) in (int, float) and math.isfinite(value), f'invalid {name}')
    return float(value)


def placement_profile(measurements, manifest, frames, receipt):
    require(type(measurements.get('schemaVersion')) is int and measurements['schemaVersion'] == 1 and
            measurements.get('scope') == 'independent-stationary-mount-measurement', 'wrong placement schema')
    require(measurements.get('recordingId') == receipt['recordingId'] and
            measurements.get('captureManifestSha256') == receipt['manifestSha256'], 'placement/capture mismatch')
    require(measurements.get('independentReferenceAssertion') is True,
            'independent mount measurement assertion required')
    require(isinstance(measurements.get('referenceMethod'), str) and measurements['referenceMethod'].strip(),
            'independent reference method required')
    require(type(measurements.get('frameId')) is int, 'reference frame required')
    selected = next((r for r in frames if r['frameId'] == measurements['frameId']), None)
    require(selected is not None, 'unknown reference frame')
    origin = measurements.get('cameraOriginWalkingM')
    tolerance = measurements.get('originToleranceM')
    require(isinstance(origin, list) and len(origin) == 3 and
            isinstance(tolerance, list) and len(tolerance) == 3, 'three measured coordinates/tolerances required')
    origin = [finite(v, 'mount origin') for v in origin]
    require(origin[2] > 0, 'camera must be above the measured floor')
    require(all(finite(v, 'origin tolerance') > 0 for v in tolerance), 'positive origin tolerances required')
    angles = {k: finite(measurements.get(k), k) for k in
              ('yawRightDeg', 'pitchDownDeg', 'rollClockwiseDeg')}
    require(all(abs(v) <= 180 for v in angles.values()), 'angles must be degrees in [-180,180]')
    require(finite(measurements.get('angleToleranceDeg'), 'angle tolerance') > 0,
            'positive angle tolerance required')
    require(not any(measurements.get(k) is True for k in (*AUTHORITY,
            'wholePixelBoundsValidated', 'metricScaleValidated', 'canAuthorizeMovement')),
            'placement cannot self-grant physical authority')
    # Native image right/down/forward -> walking lateral/forward/height.
    level = [1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1]
    image_to_walking = multiply(rotation('z', -angles['yawRightDeg']),
        multiply(rotation('x', -angles['pitchDownDeg']),
                 multiply(level, rotation('z', angles['rollClockwiseDeg']))))
    # ARKit camera is right/up/back. The recorded camera transform maps that
    # basis to ARKit world. The measured mount, not depth, fixes walking origin.
    arkit_to_image = [1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,0,1]
    camera_to_walking = multiply(image_to_walking, arkit_to_image)
    for r in range(3):
        camera_to_walking[4*r+3] = origin[r]
    world_camera = [selected['cameraTransform'][4*c+r] for r in range(4) for c in range(4)]
    result = multiply(camera_to_walking, rigid_inverse(world_camera))
    pose_matrix([result[4*r+c] for c in range(4) for r in range(4)])
    identity = hashlib.sha256(json.dumps(measurements, sort_keys=True, allow_nan=False).encode()).hexdigest()
    return {
        'format': 'bagdar-physical-evidence-profile-v1', 'schemaVersion': 1,
        'id': f'nominal-mount-{identity}', 'recordingId': manifest['recordingId'],
        'captureManifestSha256': receipt['manifestSha256'],
        'scope': 'operator-supplied-nominal-placement-only',
        'diagnosticWorldToWalkingRowMajor': result,
        'placementMeasurements': measurements,
        'referenceMeasurementsAuthenticated': False,
        'placementUncertaintyPropagated': False,
        'wholePixelBoundsAvailable': False, 'supportsPassageClearance': False,
        **AUTHORITY,
    }


def base_report(status):
    return {
        'schemaVersion': 1, 'trialId': 'first-stationary-capture-v1', 'status': status,
        'request': protocol()['request'], 'maximumAgeUs': 100000,
        'physicalGatePassed': False, 'behaviouralCollectionAllowed': False,
        'runtimeComparisonAllowed': False, 'falseStopReductionEstablished': False,
        'captureToDecisionMs': None, 'namedDeviceRuntime': 'not_run',
        'controlledWalking': 'not_run', 'genericObstacleDelivery': 'shadow',
        'implementationSha256': {p: sha(ROOT/p) for p in (
            'tool/research_capture/first_capture_trial.py',
            'tool/research_capture/arkit_capture.py',
            'tool/research_capture/arkit_experiment.py',
            'tool/research_capture/analyze_arkit.dart',
            'lib/research/recorded_rgbd.dart',
            'lib/safety/perception/single_camera_observability.dart',
            'tool/research_capture/arkit_protocol.json',
        )},
        'missingPhysicalEvidence': list(MISSING_EVIDENCE), **AUTHORITY,
    }


def prepare(output):
    require(not output.exists(), 'preparation output already exists')
    output.mkdir(parents=True)
    report = base_report('awaiting_capture')
    report.update(captureStatus='not_run', xcodeBuild='not_run', iphoneLifecycle='not_run',
                  hardwareAvailability='not_inventoried_by_this_command')
    write(output/'trial.json', report)
    write(output/'placement.template.json', {
        'schemaVersion': 1, 'scope': 'independent-stationary-mount-measurement',
        'recordingId': None, 'captureManifestSha256': None, 'frameId': None,
        'independentReferenceAssertion': False, 'referenceMethod': None,
        'cameraOriginWalkingM': [None, None, None], 'originToleranceM': [None, None, None],
        'yawRightDeg': None, 'pitchDownDeg': None, 'rollClockwiseDeg': None,
        'angleToleranceDeg': None,
    })
    write(output/'operator-checks.json', {
        'schemaVersion': 1, 'scope': 'unperformed-operator-checks',
        'checks': {k: {'status': 'not_run', 'note': None} for k in (
            'xcode_build_and_native_tests', 'private_room_and_consent',
            'independent_mount_measurement', 'stationary_capture',
            'stop_releases_camera', 'export_selected_recording',
            'recording_id_and_build_identity', 'transfer_outside_git')},
        'physicalGatePassed': False,
    })
    (output/'START_HERE.md').write_text(
        '# Первая неподвижная запись\n\n'
        'Это подготовленный пакет; физическая проверка ещё не выполнена.\n\n'
        '1. На Mac собрать и проверить рекордер по tool/research_capture/README_ARKIT.md.\n'
        '2. В согласованной частной комнате разметить прежний объём: ширина 0,9 м, '
        'высота 1,85 м, вперёд 0,2–3,5 м. Оператор остаётся на месте.\n'
        '3. Независимо измерить положение оптического центра и native image axes '
        'относительно размеченного walking origin и пола; записать допуски. '
        'Глубину телефона не использовать как эталон самой себя.\n'
        '4. Записать до 10 секунд, Stop, затем экспорт выбранного capture-ID. '
        'Проверить остановку камеры. Оригинальный ZIP хранить вне Git.\n'
        '5. Импортировать через arkit_capture.py с точным --expected-recording-id.\n'
        '6. Сначала можно запустить evaluate без placement: он проверит файл, '
        'а охват пометит непроверенным. Затем заполнить копию placement.template.json '
        'настоящими измерениями, ID и SHA-256 manifest.\n\n'
        'Команда из корня проекта (каталог вывода должен быть новым):\n\n'
        '```powershell\npython tool/research_capture/first_capture_trial.py evaluate '
        'C:\\BagdarCaptures\\capture-ID --recording-id capture-ID '
        '--placement C:\\BagdarCaptures\\placement.json '
        '--output C:\\BagdarCaptures\\trial-001\n```\n\n'
        'Exit 2 означает сформированный отчёт с непройденным физическим допуском; '
        'exit 1 — ошибку входа/анализа. Заполненный JSON, покрытие кадра и высокая '
        'confidence не включают measuredClear. Сбор 72 поведенческих записей '
        'остаётся закрыт до отдельного подтверждения физического источника.\n', encoding='utf-8')
    return report


def summarize_analysis(analysis, receipt, placement_supplied):
    require(analysis.get('recordingId') == receipt['recordingId'] and
            analysis.get('captureManifestSha256') == receipt['manifestSha256'], 'analysis/capture mismatch')
    require(all(analysis.get(k) is False for k in
            ('promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished')) and
            analysis.get('measuredClearFrames') == 0 and analysis.get('captureToDecisionMs') is None,
            'unsupported analysis authority')
    rows = analysis.get('frames')
    require(isinstance(rows, list) and len(rows) == receipt['frameCount'], 'incomplete analysis')
    expected = {r['frameId'] for r in receipt['frames']}
    require({r.get('frameId') for r in rows} == expected, 'analysis frame identity mismatch')
    geometry = [r['geometry'] for r in rows if isinstance(r.get('geometry'), dict) and
                r['geometry'].get('inputsAdmitted') is True and
                r['geometry'].get('expiredAfterAnalysis') is False]
    for g in geometry:
        require(type(g.get('entireRequestInView')) is bool and
                all(g.get(k) is False for k in ('canCertifyFreeSpace', 'canAuthorizeMovement',
                                               'placementPhysicallyValidated')),
                'incomplete or unsupported geometry verdict')
    gaps = [g for g in geometry if g.get('entireRequestInView') is False]
    if not placement_supplied:
        status = 'awaiting_independent_placement'
    elif not geometry:
        status = 'nominal_geometry_inconclusive'
    elif gaps:
        status = 'nominal_geometry_gap_observed'
    elif len(geometry) != len(rows):
        status = 'nominal_geometry_inconclusive'
    else:
        status = 'nominal_geometry_possible_physical_evidence_missing'
    report = base_report(status)
    report.update(
        captureIntegrityPassed=True, recordingId=receipt['recordingId'],
        captureManifestSha256=receipt['manifestSha256'], frameCount=receipt['frameCount'],
        manifestOriginAuthenticated=False, recorderBuildTagAuthenticated=False,
        sameFrameCandidates=receipt['sameFrameCandidates'],
        captureStatus='imported_capture_origin_not_authenticated',
        placementSupplied=placement_supplied, placementUncertaintyPropagated=False,
        nominalGeometryFrames=len(geometry), nominalGapFrames=len(gaps),
        geometryUnavailableFrames=len(rows)-len(geometry),
        maximumConditionalNearGapM=max((g['nearGapM'] for g in geometry if g.get('nearGapM') is not None), default=None),
        geometryScope='conditional-on-measured-nominal-mount-and-SDK-intrinsics-only',
        evaluatorReasons=dict(Counter(reason for r in rows for reason in r.get('evaluatorReasons', []))),
    )
    return report


def evaluate(capture, recording_id, output, measurements=None, dart=None):
    capture, output = capture.resolve(), output.resolve()
    require(not output.exists() and not output.is_relative_to(capture),
            'use a new output outside the immutable capture')
    require(not any((p/'.git').exists() for p in (capture, *capture.parents)),
            'raw recordings must stay outside Git repositories')
    receipt = audit(capture, recording_id)
    manifest = load_json(capture/'manifest.json')
    rows = [json.loads(line) for line in (capture/'frames.jsonl').read_text(encoding='utf-8').splitlines() if line.strip()]
    profile = placement_profile(measurements, manifest, rows, receipt) if measurements is not None else None
    dart = dart or shutil.which('dart.bat' if sys.platform == 'win32' else 'dart')
    require(dart is not None, 'Dart runtime not found; use --dart-executable')
    output.mkdir(parents=True)
    write(output/'audit.json', receipt)
    command = [str(dart), 'run', 'tool/research_capture/analyze_arkit.dart',
               str(capture), str(output/'audit.json'), str(output/'analysis')]
    if profile is not None:
        write(output/'placement-profile.json', profile)
        command.append(str(output/'placement-profile.json'))
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=120)
    (output/'analysis-stdout.log').write_text(result.stdout, encoding='utf-8')
    (output/'analysis-stderr.log').write_text(result.stderr, encoding='utf-8')
    require(result.returncode == 2, f'feasibility analysis failed with exit {result.returncode}')
    analysis = load_json(output/'analysis/feasibility.json')
    report = summarize_analysis(analysis, receipt, profile is not None)
    require(audit(capture, recording_id)['manifestSha256'] == receipt['manifestSha256'],
            'capture changed during analysis')
    report['analysisSha256'] = sha(output/'analysis/feasibility.json')
    report['captureDirectoryRedacted'] = True
    report['inputCaptureUnchanged'] = True
    write(output/'trial.json', report)
    (output/'report.md').write_text(render_report(report), encoding='utf-8')
    return report


def render_report(report):
    actions = {
        'awaiting_independent_placement': 'Нужно независимо измеренное положение камеры; охват ещё не оценён.',
        'nominal_geometry_inconclusive': 'Допустимых геометрических кадров недостаточно; проверить tracking, время и входы.',
        'nominal_geometry_gap_observed': 'В номинальной геометрии найден пробел. Проверить измерение положения и схему наблюдения до поведенческого сбора.',
        'nominal_geometry_possible_physical_evidence_missing': 'Номинальная геометрия допускает охват. Требуются отдельные физические свидетельства точности, пола, времени и whole-pixel bounds.',
    }
    return ('# Первая запись: результат предварительной проверки\n\n'
            f"Статус: **{report['status']}**.\n\n{actions[report['status']]}\n\n"
            f"Файловая целостность: {report['captureIntegrityPassed']}; кадров: {report['frameCount']}. "
            f"Условная геометрия: {report['nominalGeometryFrames']} кадров, с пробелом: {report['nominalGapFrames']}.\n\n"
            'Измерения положения — утверждения оператора; допуски сохранены, но не распространены '
            'в физические границы. Положительный геометрический результат не является measuredClear.\n\n'
            'Сравнение STOP и сбор 72 поведенческих записей закрыты. Доставка shadow, '
            'promotionAllowed=false. Точность датчика, физическое выравнивание, границы пола, '
            'связь native clocks и полное покрытие тела/пола не установлены.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare')
    p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('evaluate')
    p.add_argument('capture', type=Path)
    p.add_argument('--recording-id', required=True)
    p.add_argument('--placement', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--dart-executable')
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            report = prepare(args.output)
        else:
            report = evaluate(args.capture, args.recording_id, args.output,
                              load_json(args.placement) if args.placement else None, args.dart_executable)
        print(json.dumps({k: report[k] for k in ('status', 'physicalGatePassed',
                                               'runtimeComparisonAllowed', 'promotionAllowed')}))
        return 0 if args.command == 'prepare' else 2
    except (CaptureError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'First capture trial rejected: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

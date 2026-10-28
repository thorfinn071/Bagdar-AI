"""Trace paired diagnostic pixels through the unchanged APK, with no hazard labels."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')


def package(source, target):
    baseline = json.loads((source/'baseline.json').read_text())
    if baseline['corpusManifestSha256'] != sha((source/'manifest.json').read_bytes()):
        raise ValueError('Foreign diagnostic baseline')
    target.mkdir(parents=True, exist_ok=False)
    runtime = target/'runtime'
    runtime.mkdir()
    sequences, labels = [], []
    for family in ('doorway', 'bricks'):
        for condition in ('sharp', 'defocus-5', 'defocus-5-noise-8'):
            row = next(r for r in baseline['images'] if r['family'] == family and r['condition'] == condition
                       and r['seed'] == 927201 and r['width'] == 320 and r['contrast'] == 1)
            path = (source/row['asset']['path']).resolve()
            luma = path.read_bytes()
            if not path.is_relative_to(source.resolve()) or sha(luma) != row['asset']['sha256']:
                raise ValueError('Changed or unsafe diagnostic pixels')
            identifier = f'q-{family}-{condition}'
            folder = runtime/identifier
            folder.mkdir()
            width, height = row['width'], row['height']
            # Preserve EXACT diagnostic Y bytes. Neutral U/V gives grayscale.
            yuv = luma+bytes([128])*(width*height//2)
            raw = folder/'fixed.i420'
            raw.write_bytes(yuv)
            rgb = np.rint((np.frombuffer(luma, dtype=np.uint8).reshape(height, width).astype(float)-16)*255/219)
            preview = folder/'fixed.png'
            Image.fromarray(rgb.clip(0, 255).astype(np.uint8)).convert('RGB').save(preview)
            def asset(p):
                return {'path': p.relative_to(runtime).as_posix(), 'sha256': sha(p.read_bytes())}
            sequences.append({'id': identifier, 'width': width, 'height': height,
                'rotationDegrees': 0, 'mirrored': False, 'pixelFormat': 'i420-bt601-limited',
                'frames': [{'frameId': i+1, 'offsetUs': round(i*1e6/15), 'deliveryDelayUs': 0,
                            'drop': False, 'yuv': asset(raw), 'preview': asset(preview)} for i in range(31)],
                'sensors': [{'offsetUs': round(i*1e6/60), 'accelerometer': [0, 8.3, 5.2],
                             'gyroscope': [0, 0, 0]} for i in range(121)]})
            labels.append({'sequenceId': identifier, 'sourceImageId': row['id'], 'family': family,
                'condition': condition, 'lumaSha256': row['asset']['sha256'],
                'expectedBlurRejected': row['rejected'], 'expectedSharpnessScore': row['score']})
    write(runtime/'manifest.json', {'schemaVersion': 1, 'synthetic': True, 'promotionAllowed': False,
        'corpusId': 'bagdar-quality-app-probe-v1',
        'scope': 'Repeated fixed diagnostic luma for admission/model-call tracing; not a realistic scene or camera stream',
        'sequences': sequences})
    write(target/'probe-annotations.json', {'schemaVersion': 1,
        'runtimeManifestSha256': sha((runtime/'manifest.json').read_bytes()),
        'sourceBaselineSha256': sha((source/'baseline.json').read_bytes()),
        'productionSourceSha256': baseline['productionSourceSha256'],
        'scope': 'Repeated identical frames, including fixed noise; no obstacle or passable/hazard truth',
        'promotionAllowed': False, 'sequences': labels})
    print(f'QUALITY_APP_PROBE {len(sequences)} episodes; {sum(len(s["frames"]) for s in sequences)} frames')


def evaluate(root, report):
    digest = sha((root/'runtime/manifest.json').read_bytes())
    annotations = json.loads((root/'probe-annotations.json').read_text())
    control = json.loads((root/'runtime/control.json').read_text())
    marker = json.loads((root/'app-reports/process-batch-complete.json').read_text())
    if annotations['runtimeManifestSha256'] != digest or marker['manifestSha256'] != digest or marker['runId'] != control['runId'] or marker.get('completed') is not True:
        raise ValueError('Foreign app probe identity')
    manifest = json.loads((root/'runtime/manifest.json').read_text())
    episodes = {s['sequenceId']: s for s in marker['episodes']}
    rows = []
    for label, sequence in zip(annotations['sequences'], manifest['sequences'], strict=True):
        identifier = sequence['id']
        if label['sequenceId'] != identifier or episodes[identifier]['status'] != 'recorded':
            raise ValueError('Unrecorded/misaligned app probe episode')
        path = root/f'app-reports/run-{identifier}.json'
        receipt = json.loads(path.read_text())
        if receipt['sequenceId'] != identifier or receipt['runId'] != control['runId'] or receipt['manifestSha256'] != digest or receipt['promotionAllowed'] is not False:
            raise ValueError('Foreign app probe receipt')
        events = receipt['events']
        counts = Counter(e['type'] for e in events)
        loaded = [e for e in events if e['type'] == 'models_loaded']
        errors = [e for e in events if e['type'] in ('startup_error', 'callback_error')]
        delivered_ids = [e['frameId'] for e in events if e['type'] == 'frame_delivered']
        expected_ids = [f['frameId'] for f in sequence['frames']]
        complete = bool(receipt['completedInput'] and delivered_ids == expected_ids
            and loaded and loaded[-1]['liveYolo'] and loaded[-1]['liveDepth']
            and loaded[-1]['depthTier'] in ('ncnnCpu', 'ncnnVulkan') and not errors)
        skips = Counter(e['reason'] for e in events if e['type'] == 'quality_skip')
        blur_events = [e for e in events if e['type'] == 'quality_skip' and e['reason'] == 'blur']
        if any(abs(e['sharpness']-label['expectedSharpnessScore']) > 1e-6 for e in blur_events):
            raise ValueError('App and baseline blur scores differ for identical Y bytes')
        gate_matches = (skips['blur'] == len(sequence['frames'])) if label['expectedBlurRejected'] else (skips['blur'] == 0)
        rows.append({**label, 'completed': complete, 'deliveredFrames': counts['frame_delivered'],
            'qualitySkips': dict(skips), 'yoloResults': counts['yolo_result'],
            'depthCalls': sum(e.get('providerCalled', False) for e in events if e['type'] == 'depth_result'),
            'acceptedDepthResults': sum(e.get('accepted', False) for e in events if e['type'] == 'depth_result'),
            'blurSkipsMatchBaseline': gate_matches, 'depthTier': loaded[-1]['depthTier'] if loaded else None,
            'androidAnrObserved': episodes[identifier].get('androidAnrObserved'),
            'receiptSha256': sha(path.read_bytes()), 'errors': errors})
    result = {'schemaVersion': 1, 'runId': control['runId'], 'runtimeManifestSha256': digest,
        'promotionAllowed': False, 'scope': annotations['scope'], 'episodes': rows,
        'allReceiptsComplete': all(r['completed'] for r in rows),
        'allBlurSkipDecisionsMatchBaseline': all(r['blurSkipsMatchBaseline'] for r in rows),
        'modelAccuracy': 'not_measured', 'physicalDeviceValidation': 'not_run'}
    write(root/'probe-evaluation.json', result)
    lines = ['# Bagdar: проверка пар качества в Android-приложении', '',
        '27 октября 2026 года. Использован прежний APK; код приложения и фильтр не изменялись.', '',
        'Шесть независимых двухсекундных эпизодов. Внутри каждого повторяется один и тот же '
        'кадр (включая фиксированный шум) 31 раз. IMU постоянная. Это намеренный диагностический '
        'контроль допуска кадров, а не реалистичная симуляция движения или физической камеры.', '',
        '| Эпизод | Кадры | Пропуски blur | YOLO | Вызовы глубины | Принято глубины |',
        '|---|---:|---:|---:|---:|---:|']
    for row in rows:
        lines.append(f"| {row['sequenceId']} | {row['deliveredFrames']} | {row['qualitySkips'].get('blur', 0)} | "
                     f"{row['yoloResults']} | {row['depthCalls']} | {row['acceptedDepthResults']} |")
    lines.extend(['', f"Все входные отчёты полны: **{result['allReceiptsComplete']}**. "
        f"Пропуски по blur совпали с независимой оценкой: **{result['allBlurSkipDecisionsMatchBaseline']}**.", '',
        'Пропущенное фильтром шумное размытие может запускать модели. '
        'Число вызовов и принятие результата глубины не доказывают распознавание объектов '
        'или пригодность результата для навигации. Разметки опасностей/проходимости у этих полей нет.', '',
        f"Run ID: `{result['runId']}`. Манифест SHA-256: `{digest}`.", '',
        f"Полные отчёты и логи: `{root.as_posix()}/app-reports/`; итог: `probe-evaluation.json`.", '',
        '`promotionAllowed=false`; физическая камера, TalkBack и ходьба не проверялись.', ''])
    report.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'episodes'}, indent=2))
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['package', 'evaluate'])
    p.add_argument('corpus', type=Path)
    p.add_argument('destination', type=Path)
    a = p.parse_args()
    (package if a.action == 'package' else evaluate)(a.corpus, a.destination)

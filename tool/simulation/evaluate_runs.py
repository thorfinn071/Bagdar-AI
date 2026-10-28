"""Evaluate app receipts without giving reference annotations to the app."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def percentiles(values):
    values = sorted(values)
    if not values:
        return {'samples': 0, 'p50Ms': None, 'p95Ms': None}
    return {'samples': len(values), 'method': 'nearest-rank',
            'p50Ms': values[(len(values)*50+99)//100-1]/1000,
            'p95Ms': values[(len(values)*95+99)//100-1]/1000}


def evaluate(root):
    root = root.resolve()
    manifest_path = root/'runtime/manifest.json'
    digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    manifest, truth = read(manifest_path), read(root/'annotations.json')
    if truth['runtimeManifestSha256'] != digest:
        raise ValueError('Annotations do not belong to this runtime manifest')
    annotations = {s['sequenceId']: s for s in truth['sequences']}
    control = read(root/'runtime/control.json') if (root/'runtime/control.json').exists() else {}
    expected_run = control.get('runId')
    corpus_ids = {s['id'] for s in manifest['sequences']}
    if 'sequenceIds' in control:
        requested = control['sequenceIds']
        if not isinstance(requested, list) or not requested or len(set(requested)) != len(requested):
            raise ValueError('Invalid batch selection')
        selected_ids = set(requested)
    elif control.get('sequenceId') and control['sequenceId'] != 'all':
        selected_ids = {control['sequenceId']}
    else:
        selected_ids = corpus_ids
    if not selected_ids <= corpus_ids:
        raise ValueError('Batch selection names an unknown sequence')
    process_marker = root/'app-reports/process-batch-complete.json'
    marker = {}
    for marker_path in (process_marker, root/'app-reports/batch-complete.json'):
        candidate = read(marker_path) if marker_path.exists() else {}
        if expected_run and candidate.get('runId') == expected_run and candidate.get('manifestSha256') == digest:
            marker = candidate
            break
    marker_matches = bool(marker)
    results = []
    for sequence in manifest['sequences']:
        path = root/'app-reports'/f"run-{sequence['id']}.json"
        label = annotations[sequence['id']]
        row = {'sequenceId': sequence['id'], 'layout': label['layout'], 'condition': label['condition'],
               'physicalHazard': label['physicalHazard'], 'expectedFrames': len(sequence['frames'])}
        process_failure = next((r for r in marker.get('episodes', []) if r['sequenceId'] == sequence['id'] and r['status'] == 'timeout'), None) if marker_matches else None
        if process_failure:
            results.append({**row, 'execution': 'failed', 'reason': process_failure['error']})
            continue
        if not path.exists():
            results.append({**row, 'execution': 'not_run'})
            continue
        report = read(path)
        if expected_run and report.get('runId') != expected_run:
            results.append({**row, 'execution': 'not_run', 'reason': 'receipt_from_previous_run'})
            continue
        if report['manifestSha256'] != digest or report['sequenceId'] != sequence['id'] or report['promotionAllowed'] is not False:
            raise ValueError(f'Foreign/invalid app receipt: {path}')
        events = report['events']
        counts = Counter(e['type'] for e in events)
        loaded = [e for e in events if e['type'] == 'models_loaded']
        delivered = {e['captureTimestampUs']: e for e in events if e['type'] == 'frame_delivered'}
        decisions = {}
        for e in events:
            if e['type'] == 'spatial_result' and e.get('sourceTimestampUs') in delivered:
                decisions[delivered[e['sourceTimestampUs']]['frameId']] = e
        planned = Counter(e.get('plannedAction') or 'none' for e in decisions.values())
        input_start = min(delivered, default=None)
        input_end = max((stamp+e.get('deliveryAgeUs', 0) for stamp, e in delivered.items()), default=None)
        runtime_during_input = Counter(e.get('plannedAction') or 'none' for e in events
            if e['type'] in ('spatial_result', 'spatial_tick') and e.get('atUs') is not None
            and input_start is not None and input_start <= e['atUs'] <= input_end)
        imminent = sum('IMMINENT' in (e.get('plannedRuleId') or '') for e in decisions.values())
        protective = sum(e.get('plannedAction') == 'stopNow' for e in decisions.values())
        continues = sum(e.get('plannedAction') == 'continueForward' for e in decisions.values())
        accepted = [e for e in events if e['type'] == 'depth_result' and e['accepted']]
        rejected = Counter(e.get('rejectionReason') or 'none' for e in events if e['type'] == 'depth_result' and not e['accepted'])
        visible = {f['frameId'] for f in label['frames'] if f['visibleHazardWitnesses'] > 0}
        hazardous_continues = sum(e.get('plannedAction') == 'continueForward' for fid, e in decisions.items() if fid in visible)
        errors = [e for e in events if e['type'] in {'startup_error', 'callback_error'}]
        host_episode = next((r for r in marker.get('episodes', []) if r['sequenceId'] == sequence['id']), {}) if marker_matches else {}
        first_visible = min((e['captureTimestampUs'] for e in delivered.values() if e['frameId'] in visible), default=None)
        imminent_times = [e['atUs'] for fid, e in decisions.items() if fid in visible
                          and 'IMMINENT' in (e.get('plannedRuleId') or '') and e.get('plannedAction') == 'stopNow']
        expected_delivered = sum(not f['drop'] for f in sequence['frames'])
        native_depth = bool(loaded and loaded[-1].get('depthTier') in ('ncnnCpu', 'ncnnVulkan'))
        complete = bool(report['completedInput'] and len(delivered) == expected_delivered and loaded
                        and loaded[-1]['liveYolo'] and loaded[-1]['liveDepth'] and native_depth and not errors)
        results.append({**row, 'execution': 'completed' if complete else 'incomplete',
            'depthTier': loaded[-1].get('depthTier') if loaded else None,
            'deliveredFrames': len(delivered), 'droppedFrames': counts['frame_dropped'],
            'qualitySkippedFrames': counts['quality_skip'], 'liveYoloCalls': counts['yolo_result'],
            'depthCalls': sum(e.get('providerCalled', False) for e in events if e['type'] == 'depth_result'),
            'acceptedDepthResults': len(accepted), 'depthRejections': dict(rejected),
            'captureToYoloResult': percentiles([e['captureToResultUs'] for e in events if e['type'] == 'yolo_result']),
            'captureToAcceptedDepthDecision': percentiles([e['captureToDecisionUs'] for e in accepted]),
            'firstImminentAfterVisibleMs': (min(imminent_times)-first_visible)/1000 if imminent_times and first_visible is not None else None,
            'framesWithSpatialDecision': len(decisions), 'plannedActions': dict(planned),
            'framesWithHazardWitness': len(visible) if label['physicalHazard'] else 0,
            'hazardFramesWithDecision': len(visible & set(decisions)) if label['physicalHazard'] else 0,
            'runtimeActionsDuringInput': dict(runtime_during_input),
            'passableEpisodeHadStopDuringInput': runtime_during_input['stopNow'] > 0 if not label['physicalHazard'] else None,
            'protectiveStopFrames': protective, 'imminentRuleFrames': imminent,
            'hazardousContinueFrames': hazardous_continues,
            'passableStopFrames': protective if not label['physicalHazard'] else None,
            'passableHoldFrames': planned['holdAndScan'] if not label['physicalHazard'] else None,
            'passableFramesWithoutDecision': len(sequence['frames'])-len(decisions) if not label['physicalHazard'] else None,
            'passableImminentFrames': imminent if not label['physicalHazard'] else None,
            'hazardFramesWithoutDecision': len(visible-set(decisions)) if label['physicalHazard'] else None,
            'modelHashes': loaded[-1]['modelHashes'] if loaded else {}, 'errors': errors,
            'receiptSha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        results[-1]['androidAnrObserved'] = host_episode.get('androidAnrObserved')
    summary = {'schemaVersion': 1, 'runtimeManifestSha256': digest, 'runId': expected_run, 'promotionAllowed': False,
        'scope': 'synthetic scenes through real app inference; no physical-device or walking evidence',
        'expectedSequences': len(results), 'execution': dict(Counter(r['execution'] for r in results)),
        'selectedSequences': len(selected_ids),
        'batchMarker': marker if marker_matches else None,
        'allSelectedReceiptsComplete': all(r['execution'] == 'completed' for r in results if r['sequenceId'] in selected_ids),
        'liveYoloCalls': sum(r.get('liveYoloCalls', 0) for r in results),
        'depthCalls': sum(r.get('depthCalls', 0) for r in results),
        'sequencesWithYoloCalls': sum(r.get('liveYoloCalls', 0) > 0 for r in results),
        'sequencesWithDepthCalls': sum(r.get('depthCalls', 0) > 0 for r in results),
        'deliveredFrames': sum(r.get('deliveredFrames', 0) for r in results),
        'framesWithSpatialDecision': sum(r.get('framesWithSpatialDecision', 0) for r in results),
        'framesWithHazardWitness': sum(r.get('framesWithHazardWitness', 0) for r in results),
        'hazardFramesWithDecision': sum(r.get('hazardFramesWithDecision', 0) for r in results),
        'hazardFramesWithoutDecision': sum(r.get('hazardFramesWithoutDecision') or 0 for r in results),
        'perceptionQualityEstablished': False,
        'androidAnrObservedSequences': sum(r.get('androidAnrObserved') is True for r in results),
        'hazardousContinueFrames': sum(r.get('hazardousContinueFrames', 0) for r in results),
        'qualityScope': 'A protective stop is not proof of recognition. Sparse pre-effect geometry visibility is not camera recognizability.',
        'physicalDeviceValidation': 'not_run', 'controlledWalking': 'not_run', 'sequences': results}
    (root/'evaluation.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    lines = ['# Bagdar simulation lab results', '', summary['scope']+'.', '',
        f"Execution: {summary['execution']}; YOLO calls: {summary['liveYoloCalls']}; depth calls: {summary['depthCalls']}.", '',
        '| Sequence | Execution | YOLO | Depth | Decisions | Stops on passable frames | Hazardous continues |',
        '|---|---|---:|---:|---:|---:|---:|']
    for r in results:
        lines.append(f"| {r['sequenceId']} | {r['execution']} | {r.get('liveYoloCalls', '-')} | {r.get('depthCalls', '-')} | {r.get('framesWithSpatialDecision', '-')} | {r.get('passableStopFrames', '-')} | {r.get('hazardousContinueFrames', '-')} |")
    lines.extend(['', summary['qualityScope'], '', 'Physical device and controlled walking: **not run**. Promotion: **false**.', ''])
    (root/'evaluation.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({k: v for k, v in summary.items() if k != 'sequences'}, indent=2))
    return summary


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('corpus', type=Path)
    evaluate(p.parse_args().corpus)

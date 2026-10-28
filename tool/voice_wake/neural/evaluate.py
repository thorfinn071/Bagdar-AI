"""One evaluation of a frozen candidate, kept distinct from always-on/device evidence."""
import argparse
import json
import os
from pathlib import Path
import time

os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
import numpy as np
from scipy.stats import chi2
import tensorflow as tf
from corpus import audit, read_pcm, sha256
from features import prepare_window
from train import score

def summarize(records):
    positive = [r for r in records if r['target']]
    negative = [r for r in records if not r['target']]
    false = sum(r['predicted'] for r in negative)
    missed = sum(not r['predicted'] for r in positive)
    hours = sum(r['audioSeconds'] for r in negative) / 3600
    return {'positiveUtterances': len(positive), 'detectedPositiveUtterances': len(positive) - missed,
        'missedPositiveUtterances': missed, 'negativeUtterances': len(negative), 'falsePositiveUtterances': false,
        'inputGateRejectedPositive': sum(not r['eligible'] for r in positive),
        'inputGateRejectedNegative': sum(not r['eligible'] for r in negative),
        'negativeRecordedHours': hours,
        'falsePositiveClipsPerRecordedHour': false / hours if hours else None,
        'poissonOneSided95UpperPerRecordedHour': float(.5 * chi2.ppf(.95, 2 * (false + 1)) / hours) if hours else None,
        'missRate': missed / len(positive) if positive else None}

def evaluate(manifest, candidate, output, external_human_manifest=None):
    metadata = audit(manifest)
    policy_path = candidate / 'frozen-policy.json'
    policy = json.loads(policy_path.read_text(encoding='utf-8'))
    model_path = (candidate / policy['modelFile']).resolve()
    if not model_path.is_relative_to(candidate.resolve()):
        raise ValueError('model path escapes selected candidate')
    if sha256(model_path) != policy['modelSha256'] or sha256(manifest) != policy['corpusSha256']:
        raise ValueError('frozen model or corpus digest mismatch')
    if policy['selectionSplit'] != 'dev' or policy['promotionAllowed'] is not False:
        raise ValueError('invalid frozen policy')
    evaluated_manifest = manifest
    if external_human_manifest is not None:
        external = audit(external_human_manifest)
        if any(r['origin'] != 'human_consented' or r['split'] != 'test' for r in external['recordings']):
            raise ValueError('external evaluation requires human test recordings only')
        old_hashes = {r['sha256'] for r in metadata['recordings']}
        old_speakers = {r['speakerGroup'] for r in metadata['recordings']}
        if any(r['sha256'] in old_hashes or r['speakerGroup'] in old_speakers for r in external['recordings']):
            raise ValueError('external human holdout overlaps original corpus')
        metadata = external
        evaluated_manifest = external_human_manifest
    interpreter = tf.lite.Interpreter(model_path=str(model_path), num_threads=1)
    interpreter.allocate_tensors()
    selected = [r for r in metadata['recordings'] if r['split'] == 'test']
    results, timings = [], []
    for record in selected:
        signal, _ = read_pcm(evaluated_manifest.parent / record['wav'], expected_rate=16000)
        window, eligible = prepare_window(signal)
        scores, elapsed = score(interpreter, [window])
        value = float(scores[0])
        result = {k: record[k] for k in ['id', 'target', 'language', 'origin', 'speakerGroup', 'sha256', 'audioSeconds']}
        results.append(dict(result, eligible=bool(eligible), score=value,
            predicted=bool(eligible and value >= policy['threshold'])))
        timings.extend(elapsed)
    languages = {language: summarize([r for r in results if r['language'] == language]) for language in ['ru', 'kk', 'en']}
    origins = {origin: summarize([r for r in results if r['origin'] == origin]) for origin in sorted({r['origin'] for r in results})}
    observed = policy['selectionFeasible'] and all(v['positiveUtterances'] > 0 and v['missRate'] <= .1 and v['falsePositiveUtterances'] == 0 for v in languages.values())
    report = dict(schema=1, experimentId=policy['experimentId'], frozenPolicySha256=sha256(policy_path),
        modelSha256=policy['modelSha256'], corpusSha256=policy['corpusSha256'], threshold=policy['threshold'],
        evaluationManifestSha256=sha256(evaluated_manifest), externalHuman=external_human_manifest is not None,
        selectionFeasible=policy['selectionFeasible'], evidence=metadata['evidence'],
        unit='one_segmented_utterance_not_continuous_wake_events', summary=summarize(results), languages=languages, origins=origins,
        observedFixtureTargetsMet=bool(observed), evidenceSufficientForTargets=False,
        humanPositiveEvidence='supplied_labels_not_origin_authentication' if external_human_manifest else 'not_available',
        humanRuKkConversationEvidence='not_available',
        desktopTfliteInvocationMs={'p50': float(np.quantile(timings, .5)), 'p95': float(np.quantile(timings, .95))},
        androidLatency='not_run', continuousListening='not_run', promotionAllowed=False, automaticCommandWired=False,
        records=results)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, indent=2), flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--external-human-manifest', type=Path)
    args = parser.parse_args(); evaluate(args.manifest, args.candidate, args.output, args.external_human_manifest)

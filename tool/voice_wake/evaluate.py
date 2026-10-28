"""Offline candidate evaluation. Synthetic/desktop evidence never promotes Android use."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import time
import wave

POLICY = json.loads(Path(__file__).with_name('policy.json').read_text(encoding='utf-8'))

def accepted(result):
    words = result.get('result', [])
    if result.get('text') != 'бағдар' or len(words) != 1:
        return False
    word = words[0]
    confidence, start, end = (word.get(k) for k in ('conf', 'start', 'end'))
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in (confidence, start, end)):
        return False
    return (word.get('word') == 'бағдар' and POLICY['confidenceMin'] <= confidence <= 1
            and start >= 0 and POLICY['wordDurationMinSeconds'] <= end - start <= POLICY['wordDurationMaxSeconds'])

def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)]

def evaluate(model_dir, corpus, output, mode='verified'):
    import psutil
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
    process = psutil.Process()
    baseline = process.memory_info().rss
    before = time.perf_counter()
    model = Model(str(model_dir))
    load_ms = (time.perf_counter() - before) * 1000
    if model.vosk_model_find_word('бағдар') < 0 or model.vosk_model_find_word('[unk]') < 0:
        raise ValueError('required vocabulary unavailable')
    manifest = json.loads((corpus / 'manifest.json').read_text(encoding='utf-8-sig'))
    records = []
    for record in manifest['recordings']:
        wav_path = (corpus / record['wav']).resolve()
        if not wav_path.is_relative_to(corpus.resolve()):
            raise ValueError('audio path outside corpus')
        with wave.open(str(wav_path), 'rb') as audio:
            if audio.getframerate() != 16000 or audio.getnchannels() != 1 or audio.getsampwidth() != 2:
                raise ValueError('expected mono PCM16 at 16kHz')
            pcm = audio.readframes(audio.getnframes())
        recognizer = KaldiRecognizer(model, 16000, json.dumps(POLICY['grammar'], ensure_ascii=False))
        recognizer.SetWords(True)
        detections = []
        candidates = 0
        segment = bytearray()
        cpu_before = time.perf_counter()
        # Include natural trailing silence; do not force FinalResult into an activation.
        padded = pcm + bytes(16000 * 2 * 2)
        for offset in range(0, len(padded), POLICY['chunkSamples'] * 2):
            chunk = padded[offset:offset + POLICY['chunkSamples'] * 2]
            segment.extend(chunk)
            maximum = POLICY['verifierBufferMaxSeconds'] * 32000
            if len(segment) > maximum:
                del segment[:-maximum]
            if recognizer.AcceptWaveform(chunk):
                result = json.loads(recognizer.Result())
                if accepted(result):
                    candidates += 1
                    if mode == 'grammar-only':
                        event_at = min(offset / 2 + POLICY['chunkSamples'], len(padded) / 2) / 16000
                        detections.append({'audioTimeSeconds': event_at, 'afterWordEndMs': (event_at - result['result'][0]['end']) * 1000})
                    else:
                        verifier = KaldiRecognizer(model, 16000)
                        verifier.SetWords(True)
                        verifier.AcceptWaveform(bytes(segment))
                        verified = json.loads(verifier.FinalResult())
                        if accepted(verified):
                            event_at = min(offset / 2 + POLICY['chunkSamples'], len(padded) / 2) / 16000
                            detections.append({'audioTimeSeconds': event_at, 'afterWordEndMs': (event_at - result['result'][0]['end']) * 1000})
                segment.clear()
        elapsed = (time.perf_counter() - cpu_before) * 1000
        duration = len(padded) / 32000
        records.append(dict(record, sha256=hashlib.sha256(wav_path.read_bytes()).hexdigest(), audioSeconds=duration,
                            detections=detections, candidateCount=candidates, processingMs=elapsed, realTimeFactor=elapsed / 1000 / duration))
    positives = [r for r in records if r['target']]
    negatives = [r for r in records if not r['target']]
    negative_seconds = sum(r['audioSeconds'] for r in negatives)
    false_count = sum(len(r['detections']) for r in negatives)
    delays = [r['detections'][0]['afterWordEndMs'] for r in positives if r['detections']]
    report = {
        'schema': 1, 'modelId': POLICY['modelId'], 'mode': mode, 'evidence': manifest['evidence'], 'platform': 'desktop_windows',
        'archiveSha256': POLICY['archiveSha256'],
        'policySha256': hashlib.sha256(Path(__file__).with_name('policy.json').read_bytes()).hexdigest(),
        'counts': {'positive': len(positives), 'detectedPositive': sum(bool(r['detections']) for r in positives),
                   'missedPositive': sum(not r['detections'] for r in positives), 'negative': len(negatives), 'falseActivations': false_count,
                   'negativeRecordingsWithActivation': sum(bool(r['detections']) for r in negatives)},
        'negativeAudioHours': negative_seconds / 3600,
        'falseActivationsPerHour': false_count * 3600 / negative_seconds if negative_seconds else None,
        'missRate': sum(not r['detections'] for r in positives) / len(positives) if positives else None,
        'audioEndpointDelayMs': {'p50': percentile(delays, .5), 'p95': percentile(delays, .95)},
        'processingRealTimeFactorP95': percentile([r['realTimeFactor'] for r in records], .95),
        'modelLoadMs': load_ms, 'rssAfterEvaluationBytes': process.memory_info().rss, 'rssDeltaFromBeforeModelBytes': process.memory_info().rss - baseline,
        'androidLatency': 'not_run', 'battery': 'not_run', 'thermal': 'not_run', 'humanSpeech': 'not_run',
        'promotionAllowed': False, 'ordinaryCoreWired': False, 'records': records,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'records'}, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=['grammar-only', 'verified'], default='verified')
    args = parser.parse_args()
    evaluate(args.model, args.corpus, args.output, args.mode)

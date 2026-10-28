"""Pinned synthetic training corpus and licensed public *negative* human audio."""
import argparse
import gc
import hashlib
import json
import math
from pathlib import Path
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).parent
def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read_pcm(path, expected_rate=None, max_seconds=None):
    with wave.open(str(path), 'rb') as audio:
        rate = audio.getframerate()
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getcomptype() != 'NONE':
            raise ValueError('expected mono PCM16 WAV')
        if expected_rate is not None and rate != expected_rate:
            raise ValueError('incorrect sample rate')
        if max_seconds is not None and audio.getnframes() / rate > max_seconds:
            raise ValueError('recording exceeds single-utterance duration limit')
        data = audio.readframes(audio.getnframes())
    if not data:
        raise ValueError('empty recording')
    return np.frombuffer(data, dtype='<i2').astype(np.float32) / 32768, rate
def write_pcm(path, signal):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(16000)
        audio.writeframes((np.clip(signal, -1, 1) * 32767).astype('<i2').tobytes())
def resample(signal, rate):
    divisor = math.gcd(rate, 16000)
    return resample_poly(signal, 16000 // divisor, rate // divisor).astype(np.float32)

def audit(manifest, verify_audio=True):
    metadata = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if metadata.get('schema') != 1:
        raise ValueError('invalid manifest schema')
    groups, hashes, ids = {}, {}, set()
    for record in metadata['recordings']:
        if record['id'] in ids or record['split'] not in ['train', 'dev', 'test', 'legacy'] or type(record['target']) is not bool or record['language'] not in ['ru', 'kk', 'en']:
            raise ValueError('invalid record or split')
        ids.add(record['id'])
        group = record['speakerGroup']
        if group in groups and groups[group] != record['split']:
            raise ValueError('speaker leakage across splits')
        groups[group] = record['split']
        if record['sha256'] in hashes and hashes[record['sha256']] != record['split']:
            raise ValueError('audio leakage across splits')
        hashes[record['sha256']] = record['split']
        path = (manifest.parent / record['wav']).resolve()
        if not path.is_relative_to(manifest.parent.resolve()):
            raise ValueError('audio path escapes corpus')
        if verify_audio and sha256(path) != record['sha256']:
            raise ValueError('recording SHA-256 mismatch')
        if record['origin'] not in ['synthetic_piper', 'synthetic_sapi', 'public_fsdd', 'human_consented']:
            raise ValueError('unknown recording origin')
        if record['origin'] == 'human_consented' and (
            record.get('consentConfirmed') is not True or record.get('groundTruthConfirmed') is not True
        ):
            raise ValueError('human consent and ground truth must be explicit')
        if record['origin'] == 'public_fsdd' and (record['target'] or record['language'] != 'en'):
            raise ValueError('public digits cannot create positive wake evidence')
    return metadata

def generate(data, output):
    from piper import PiperVoice, SynthesisConfig
    import onnxruntime
    protocol = json.loads((ROOT / 'protocol.json').read_text(encoding='utf-8'))
    onnxruntime.set_seed(protocol['seed'])
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'manifest.json').exists():
        audit(output / 'manifest.json')
        print('existing frozen corpus verified; synthesis skipped', flush=True)
        return
    records = []
    for voice_spec in protocol['voices']:
        key = voice_spec['key']; split = voice_spec['split']; language = voice_spec['language']
        voice = PiperVoice.load(data / 'voices' / key / (key + '.onnx'))
        phrases = [(text, True) for text in protocol['positivePhrases'][language]]
        phrases += [(text, False) for text in protocol['negativePhrases'][language][split]]
        speeds = [.8, 1, 1.2] if split != 'dev' else [.9, 1.1]
        index = 0
        for text, target in phrases:
            for speed in speeds:
                for repetition in range(4 if target and split == 'train' else 3 if target else 1):
                    index += 1
                    identity = f'{split}-{key}-{index:04}'
                    path = output / 'wav' / (identity + '.wav')
                    if not path.exists():
                        config = SynthesisConfig(speaker_id=voice_spec.get('speakerId'), length_scale=speed,
                            noise_scale=.65 + repetition * .04, noise_w_scale=.7, normalize_audio=False)
                        chunks = list(voice.synthesize(text, syn_config=config))
                        if not chunks:
                            raise ValueError('TTS produced no audio')
                        signal = np.concatenate([np.frombuffer(chunk.audio_int16_bytes, dtype='<i2') for chunk in chunks]).astype(np.float32) / 32768
                        write_pcm(path, resample(signal, chunks[0].sample_rate))
                    records.append(dict(id=identity, wav='wav/' + path.name, target=target,
                        language=language, split=split, speakerGroup=voice_spec['speakerGroup'], voice=key,
                        text=text, lengthScale=speed, repetition=repetition, origin='synthetic_piper', sha256=sha256(path)))
        print('synthesized', key, index, flush=True)
        del voice; gc.collect()
    for path in sorted((data / 'fsdd/recordings').glob('*.wav')):
        digit, speaker, index = path.stem.split('_')
        split = next((name for name, speakers in protocol['fsddSpeakers'].items() if speaker in speakers), None)
        if split is None:
            raise ValueError('unexpected FSDD speaker')
        identity = 'fsdd-' + path.stem
        target = output / 'wav' / (identity + '.wav')
        signal, rate = read_pcm(path)
        write_pcm(target, resample(signal, rate))
        records.append(dict(id=identity, wav='wav/' + target.name, target=False, language='en',
            split=split, speakerGroup='fsdd-' + speaker, text=digit, origin='public_fsdd',
            sourceSha256=sha256(path), sha256=sha256(target)))
    sapi = output / 'sapi-manifest.json'
    if not sapi.exists():
        raise ValueError('generate the reserved SAPI test corpus before finalizing')
    records.extend(json.loads(sapi.read_text(encoding='utf-8-sig'))['recordings'])
    for record in records:
        signal, _ = read_pcm(output / record['wav'], expected_rate=16000)
        record['audioSeconds'] = len(signal) / 16000
    result = dict(schema=1, experimentId=protocol['experimentId'], evidence=protocol['corpusEvidence'],
        protocolSha256=sha256(ROOT / 'protocol.json'), downloadLockSha256=sha256(data / 'download-lock.json'), recordings=records)
    manifest = output / 'manifest.json'
    manifest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    audit(manifest)
    print('corpus frozen', len(records), 'records', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(); generate(args.data, args.output)

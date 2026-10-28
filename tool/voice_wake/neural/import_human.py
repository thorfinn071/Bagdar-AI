"""Explicit local import; neither records a microphone nor authenticates capture origin."""
import argparse
import json
from pathlib import Path
import shutil

from corpus import read_pcm, sha256, audit

def import_human(source_manifest, recording_root, output, expected_capture_id):
    metadata = json.loads(source_manifest.read_text(encoding='utf-8-sig'))
    if not expected_capture_id or metadata.get('captureId') != expected_capture_id:
        raise ValueError('selected capture ID does not match manifest')
    if metadata.get('schema') != 1 or metadata.get('consentConfirmed') is not True:
        raise ValueError('explicit consent record required')
    if output.exists() and any(output.iterdir()):
        raise ValueError('destination must be empty; never modify a frozen corpus')
    root = recording_root.resolve()
    records, ids, source_hashes = [], set(), set()
    # Validate the entire selected batch before writing any imported audio.
    for index, record in enumerate(metadata['recordings']):
        identity = record.get('id')
        if not isinstance(identity, str) or not identity or identity in ids:
            raise ValueError('invalid recording identity')
        ids.add(identity)
        if (record.get('language') not in ['ru', 'kk', 'en'] or type(record.get('target')) is not bool or
            record.get('groundTruthConfirmed') is not True or not isinstance(record.get('speakerId'), str) or not record['speakerId']):
            raise ValueError('explicit speaker, language and ground truth required')
        selected = (root / record['wav']).resolve()
        if not selected.is_relative_to(root):
            raise ValueError('recording escapes selected root')
        digest = sha256(selected)
        if digest != record.get('sha256') or digest in source_hashes:
            raise ValueError('recording digest mismatch or duplicate audio')
        source_hashes.add(digest)
        signal, _ = read_pcm(selected, expected_rate=16000, max_seconds=8)
        records.append(dict(id=identity, wav=f'wav/human-{index:05}.wav',
            target=record['target'], language=record['language'], speakerGroup='human-' + record['speakerId'],
            split='test', origin='human_consented', consentConfirmed=True, groundTruthConfirmed=True,
            sha256=digest, audioSeconds=len(signal) / 16000, captureId=expected_capture_id))
    if not records:
        raise ValueError('empty capture batch')
    output.mkdir(parents=True, exist_ok=True)
    for source, imported in zip(metadata['recordings'], records):
        target = output / imported['wav']; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / source['wav'], target)
    manifest = output / 'manifest.json'
    manifest.write_text(json.dumps(dict(schema=1, evidence='human_consent_and_labels_asserted_by_supplier',
        captureId=expected_capture_id, sourceManifestSha256=sha256(source_manifest),
        originAuthenticated=False, recordings=records), indent=2) + '\n', encoding='utf-8')
    audit(manifest)
    return manifest

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--recording-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-capture-id', required=True)
    args = parser.parse_args()
    print(import_human(args.manifest, args.recording_root, args.output, args.expected_capture_id))

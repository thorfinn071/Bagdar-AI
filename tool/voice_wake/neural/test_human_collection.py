"""Generated WAV fixtures only. These tests contain no human recording evidence."""
from array import array
import json
from pathlib import Path
import random
import sys
import tempfile
import unittest
import wave

from human_collection import (PROTOCOL, audit_collection, audio_info, digest, export_corpus,
    import_batch, init_collection, load_plan, read_json, tasks_for, write_json)


def fixture_audio(path, seed=1, rate=16000, channels=1, width=2, frames=160):
    rng = random.Random(seed)
    samples = array('h', [rng.randrange(-5000, 5000) for _ in range(frames * channels)])
    if sys.byteorder != 'little':
        samples.byteswap()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(channels); audio.setsampwidth(width); audio.setframerate(rate)
        audio.writeframes(samples.tobytes())


def replace_json(path, value):
    path.write_text(json.dumps(value), encoding='utf-8')


class HumanCollectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.old = self.root / 'old.json'
        write_json(self.old, dict(schema=1, recordings=[dict(sha256='a' * 64, speakerGroup='seen-voice')]))
        protocol = read_json(PROTOCOL)
        # A smaller fixture roster exercises all roles and languages; never a human pilot.
        protocol['speakersPerLanguage'] = dict(train=1, dev=1, test=1)
        self.protocol = self.root / 'fixture-protocol.json'; write_json(self.protocol, protocol)
        self.pack = self.root / 'pack'
        self.plan_path, self.plan_hash = init_collection(self.pack, [self.old], self.protocol)
        self.plan = load_plan(self.plan_path, self.plan_hash)
        self.data = self.root / 'data'
        self.next_seed = 0

    def supplier_batch(self, speaker=None, session='s1'):
        speaker = speaker or self.plan['participants'][0]['id']
        original = self.pack / 'templates' / speaker / session / 'manifest.json'
        source = read_json(original)
        for field in ('consentConfirmed', 'humanRecordingConfirmed', 'speakerNoveltyConfirmed'):
            source[field] = True
        source['deviceId'] = 'fixture-device'
        for record in source['recordings']:
            self.next_seed += 1
            fixture_audio(original.parent / record['wav'], self.next_seed)
            record['sha256'] = digest(original.parent / record['wav'])
            record['transcript'] = record['textPrompt']
            record['groundTruthConfirmed'] = True
        replace_json(original, source)
        return original, source

    def ingest(self, source, metadata, expected=None):
        replace_json(source, metadata)
        return import_batch(self.plan_path, self.plan_hash, source, source.parent, self.data,
            expected or metadata['captureId'])

    def fill(self):
        for person in self.plan['participants']:
            for session in ('s1', 's2'):
                self.ingest(*self.supplier_batch(person['id'], session))

    def export_dev(self):
        self.fill()
        return export_corpus(self.plan_path, self.plan_hash, self.data, self.root / 'development', 'development')

    def candidate(self, development):
        model = self.root / 'candidate' / 'fixture-model.bin'
        model.parent.mkdir(); model.write_bytes(b'fixture-only-not-a-trained-model')
        policy = model.parent / 'frozen-policy.json'
        write_json(policy, dict(experimentId=self.plan['experimentId'], modelFile=model.name,
            modelSha256=digest(model), corpusSha256=digest(development), threshold=.9,
            selectionSplit='dev', selectionFeasible=True, promotionAllowed=False))
        return policy

    def holdout(self, policy, development):
        return export_corpus(self.plan_path, self.plan_hash, self.data, self.root / 'holdout',
            'holdout', policy, development)

    def test_default_pack_has_24_people_432_clips_and_no_asserted_consent(self):
        pack = self.root / 'default-pack'
        plan_path, plan_hash = init_collection(pack, [self.old])
        plan = load_plan(plan_path, plan_hash)
        self.assertEqual(len(plan['participants']), 24)
        self.assertEqual(sum(len(tasks_for(plan, p)) for p in plan['participants']), 432)
        templates = list(pack.glob('templates/*/*/manifest.json'))
        self.assertEqual(len(templates), 48)
        self.assertEqual((pack / 'plan-sha256.txt').read_text().strip(), plan_hash)
        self.assertIn('Багдар', (pack / 'participant-cards.md').read_text(encoding='utf-8'))
        self.assertIn('h024', (pack / 'roster.md').read_text(encoding='utf-8'))
        for path in templates:
            template = read_json(path)
            self.assertFalse(template['consentConfirmed'])
            self.assertFalse(template['humanRecordingConfirmed'])
            self.assertTrue(all(not r['groundTruthConfirmed'] for r in template['recordings']))

    def test_empty_collection_is_not_ready_and_not_human_evidence(self):
        result = audit_collection(self.plan_path, self.plan_hash, self.data)
        self.assertEqual(result['collectionStatus'], 'not_run')
        self.assertEqual(result['humanPositiveClips'], 0)
        self.assertFalse(result['readyForModelDevelopment'])
        self.assertFalse(result['completeFreshCollection'])
        self.assertFalse(result['promotionAllowed'])

    def test_plan_cannot_be_silently_changed_or_overwritten(self):
        with self.assertRaisesRegex(ValueError, 'already exists'):
            init_collection(self.pack, [self.old], self.protocol)
        changed = read_json(self.plan_path); changed['participants'][0]['split'] = 'test'
        replace_json(self.plan_path, changed)
        with self.assertRaisesRegex(ValueError, 'plan SHA-256 mismatch'):
            load_plan(self.plan_path, self.plan_hash)

    def test_old_material_exclusions_are_required(self):
        with self.assertRaisesRegex(ValueError, 'previously inspected'):
            init_collection(self.root / 'no-exclusions', [], self.protocol)

    def test_partial_batch_is_counted_but_does_not_complete_collection(self):
        path = self.ingest(*self.supplier_batch())
        metadata = read_json(path)
        self.assertEqual(metadata['recordings'][0]['split'], 'train')
        self.assertFalse(metadata['originAuthenticated'])
        self.assertNotIn('transcript', metadata['recordings'][0])
        result = audit_collection(self.plan_path, self.plan_hash, self.data)
        self.assertEqual(result['importedClips'], 9)
        self.assertEqual(result['humanPositiveClips'], 3)
        self.assertFalse(result['readyForModelDevelopment'])

    def test_capture_or_plan_mismatch_makes_no_import_writes(self):
        path, data = self.supplier_batch()
        with self.assertRaisesRegex(ValueError, 'capture ID or collection plan'):
            self.ingest(path, data, 'another-capture')
        data['collectionPlanSha256'] = 'b' * 64
        with self.assertRaisesRegex(ValueError, 'capture ID or collection plan'):
            self.ingest(path, data)
        self.assertFalse(self.data.exists())

    def test_each_supplier_assertion_is_required(self):
        path, data = self.supplier_batch()
        for field in ('consentConfirmed', 'humanRecordingConfirmed', 'speakerNoveltyConfirmed'):
            with self.subTest(field=field):
                data[field] = False
                with self.assertRaisesRegex(ValueError, field):
                    self.ingest(path, data)
                data[field] = True
        self.assertFalse(self.data.exists())

    def test_labels_cannot_be_changed_to_fit_the_classifier(self):
        path, data = self.supplier_batch()
        for field, value in (('target', False), ('language', 'en'), ('speakerId', 'h099'),
                ('promptId', 'other'), ('target', 1)):
            with self.subTest(field=field, value=value):
                old = data['recordings'][0][field]; data['recordings'][0][field] = value
                with self.assertRaisesRegex(ValueError, 'preregistered'):
                    self.ingest(path, data)
                data['recordings'][0][field] = old
        self.assertFalse(self.data.exists())

    def test_listening_and_transcription_are_required(self):
        path, data = self.supplier_batch()
        data['recordings'][0]['groundTruthConfirmed'] = False
        with self.assertRaisesRegex(ValueError, 'ground truth'):
            self.ingest(path, data)
        data['recordings'][0]['groundTruthConfirmed'] = True
        data['recordings'][0]['transcript'] = ''
        with self.assertRaisesRegex(ValueError, 'transcript'):
            self.ingest(path, data)

    def test_invalid_last_record_leaves_no_partially_imported_batch(self):
        path, data = self.supplier_batch()
        data['recordings'][-1]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'recording SHA-256'):
            self.ingest(path, data)
        self.assertFalse(self.data.exists())

    def test_previously_inspected_audio_is_rejected(self):
        path, data = self.supplier_batch()
        plan = read_json(self.plan_path)
        plan['excludedAudioSha256'].append(data['recordings'][0]['sha256'])
        replace_json(self.plan_path, plan); self.plan_hash = digest(self.plan_path)
        data['collectionPlanSha256'] = self.plan_hash
        with self.assertRaisesRegex(ValueError, 'previously inspected'):
            self.ingest(path, data)

    def test_duplicate_audio_across_different_speakers_is_rejected(self):
        source, data = self.supplier_batch(); self.ingest(source, data)
        other, second = self.supplier_batch(self.plan['participants'][1]['id'])
        original = (source.parent / data['recordings'][0]['wav']).read_bytes()
        (other.parent / second['recordings'][0]['wav']).write_bytes(original)
        second['recordings'][0]['sha256'] = data['recordings'][0]['sha256']
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.ingest(other, second)
        self.assertEqual(audit_collection(self.plan_path, self.plan_hash, self.data)['importedClips'], 9)

    def test_capture_is_never_overwritten(self):
        source, data = self.supplier_batch(); result = self.ingest(source, data)
        old_hash = digest(result)
        with self.assertRaisesRegex(ValueError, 'never overwrite'):
            self.ingest(source, data)
        self.assertEqual(old_hash, digest(result))

    def test_escaped_or_absolute_source_paths_are_rejected(self):
        source, data = self.supplier_batch()
        for value in ('../outside.wav', str((self.root / 'outside.wav').resolve())):
            data['recordings'][0]['wav'] = value
            with self.assertRaisesRegex(ValueError, 'escapes|relative selected'):
                self.ingest(source, data)
        self.assertFalse(self.data.exists())

    def test_reaudit_detects_changed_audio_and_split_metadata(self):
        path = self.ingest(*self.supplier_batch()); metadata = read_json(path)
        metadata['recordings'][0]['split'] = 'test'; replace_json(path, metadata)
        with self.assertRaisesRegex(ValueError, 'split changed'):
            audit_collection(self.plan_path, self.plan_hash, self.data)
        metadata['recordings'][0]['split'] = 'train'; replace_json(path, metadata)
        fixture_audio(path.parent / metadata['recordings'][0]['wav'], 90000)
        with self.assertRaisesRegex(ValueError, 'recording SHA-256'):
            audit_collection(self.plan_path, self.plan_hash, self.data)

    def test_wrong_rate_stereo_truncated_or_overlong_wav_is_rejected(self):
        path = self.root / 'invalid.wav'
        for options in (dict(rate=8000), dict(channels=2), dict(width=1), dict(frames=8 * 16000 + 1)):
            fixture_audio(path, **options)
            with self.assertRaises(ValueError):
                audio_info(path)
        fixture_audio(path); raw = path.read_bytes(); path.write_bytes(raw[:-2])
        with self.assertRaisesRegex(ValueError, 'truncated'):
            audio_info(path)

    def test_difficult_valid_audio_is_flagged_and_retained(self):
        path = self.root / 'silence.wav'
        with wave.open(str(path), 'wb') as audio:
            audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(16000)
            audio.writeframes(b'\x00\x00' * 16000)
        info = audio_info(path)
        self.assertEqual(info['audioSeconds'], 1)
        self.assertTrue(info['reviewWarnings'])

    def test_missing_any_session_prevents_export(self):
        self.ingest(*self.supplier_batch())
        with self.assertRaisesRegex(ValueError, 'complete train/dev'):
            export_corpus(self.plan_path, self.plan_hash, self.data, self.root / 'dev', 'development')

    def test_development_export_has_no_test_audio_or_records(self):
        path = self.export_dev(); metadata = read_json(path)
        self.assertEqual(len(metadata['recordings']), 108)
        self.assertEqual({r['split'] for r in metadata['recordings']}, {'train', 'dev'})
        self.assertEqual(len(list(path.parent.glob('wav/*.wav'))), 108)
        result = audit_collection(self.plan_path, self.plan_hash, self.data)
        self.assertTrue(result['completeFreshCollection'])
        self.assertFalse(result['promotionAllowed'])
        with self.assertRaisesRegex(ValueError, 'never overwrite'):
            export_corpus(self.plan_path, self.plan_hash, self.data, path.parent, 'development')

    def test_holdout_is_closed_without_a_feasible_frozen_candidate(self):
        development = self.export_dev()
        with self.assertRaisesRegex(ValueError, 'frozen candidate'):
            self.holdout(None, development)
        policy = self.candidate(development); metadata = read_json(policy)
        metadata['selectionFeasible'] = False; replace_json(policy, metadata)
        with self.assertRaisesRegex(ValueError, 'feasible dev policy'):
            self.holdout(policy, development)
        self.assertFalse((self.root / 'holdout').exists())

    def test_holdout_requires_exact_model_and_development_hashes(self):
        development = self.export_dev(); policy = self.candidate(development); frozen = read_json(policy)
        for field in ('modelSha256', 'corpusSha256'):
            changed = dict(frozen); changed[field] = '0' * 64; replace_json(policy, changed)
            with self.assertRaisesRegex(ValueError, 'frozen candidate'):
                self.holdout(policy, development)

    def test_hash_bound_but_mixed_development_corpus_is_rejected(self):
        development = self.export_dev(); metadata = read_json(development)
        metadata['recordings'][0]['split'] = 'test'; replace_json(development, metadata)
        policy = self.candidate(development)
        with self.assertRaisesRegex(ValueError, 'only the planned train/dev'):
            self.holdout(policy, development)

    def test_hash_bound_but_mislabelled_development_corpus_is_rejected(self):
        development = self.export_dev(); metadata = read_json(development)
        metadata['recordings'][0]['target'] = False; replace_json(development, metadata)
        policy = self.candidate(development)
        with self.assertRaisesRegex(ValueError, 'preregistered target'):
            self.holdout(policy, development)

    def test_holdout_release_binds_policy_without_granting_promotion(self):
        development = self.export_dev(); policy = self.candidate(development)
        result = read_json(self.holdout(policy, development))
        self.assertEqual(len(result['recordings']), 54)
        self.assertEqual({r['split'] for r in result['recordings']}, {'test'})
        self.assertEqual(result['release']['frozenPolicySha256'], digest(policy))
        self.assertFalse(result['promotionAllowed'])
        self.assertFalse(result['release']['blindedExternalEvaluation'])


if __name__ == '__main__':
    unittest.main(verbosity=2)

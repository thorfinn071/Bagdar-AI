import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from corpus import audit, write_pcm, sha256
from features import prepare_window, log_mel
from train import choose_threshold
from evaluate import summarize
from import_human import import_human

class CorpusIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        audio = self.root / 'one.wav'
        write_pcm(audio, np.sin(np.arange(8000) * .1).astype(np.float32) * .1)
        self.record = dict(id='one', wav='one.wav', target=True, split='train',
            speakerGroup='one', sha256=sha256(audio), origin='synthetic_piper', language='ru')
    def check(self, records):
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps(dict(schema=1, recordings=records)), encoding='utf-8')
        return audit(manifest)
    def test_valid_data_has_verified_bytes(self):
        self.assertEqual(len(self.check([self.record])['recordings']), 1)
    def test_changed_waveform_is_rejected(self):
        write_pcm(self.root / 'one.wav', np.zeros(8000, np.float32))
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.check([self.record])
    def test_same_speaker_cannot_cross_splits_even_with_distinct_audio(self):
        other = dict(self.record, id='two', split='test', sha256='b' * 64)
        with self.assertRaisesRegex(ValueError, 'speaker leakage'):
            self.check([self.record, other])
    def test_same_audio_cannot_cross_splits_under_a_different_speaker(self):
        other = dict(self.record, id='two', split='test', speakerGroup='two')
        with self.assertRaisesRegex(ValueError, 'audio leakage'):
            self.check([self.record, other])
    def test_paths_cannot_escape_selected_corpus(self):
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.check([dict(self.record, wav='../outside.wav')])
    def test_string_label_is_not_a_boolean_label(self):
        with self.assertRaisesRegex(ValueError, 'invalid record'):
            self.check([dict(self.record, target='false')])
    def test_public_digits_cannot_become_human_positive_evidence(self):
        with self.assertRaisesRegex(ValueError, 'positive wake'):
            self.check([dict(self.record, origin='public_fsdd', language='en')])
    def test_unknown_provenance_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unknown recording origin'):
            self.check([dict(self.record, origin='human_verified_by_filename')])

class HumanImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.output = self.root / 'imported'
        write_pcm(self.root / 'voice.wav', np.sin(np.arange(8000) * .1).astype(np.float32) * .1)
        self.data = dict(schema=1, captureId='capture-selected', consentConfirmed=True, recordings=[dict(
            id='h01-001', wav='voice.wav', speakerId='h01', language='ru', target=True,
            groundTruthConfirmed=True, sha256=sha256(self.root / 'voice.wav'))])
    def run_import(self, expected='capture-selected'):
        source = self.root / 'selected.json'; source.write_text(json.dumps(self.data), encoding='utf-8')
        return import_human(source, self.root, self.output, expected)
    def test_selected_capture_import_is_audited_and_keeps_origin_unverified(self):
        result = audit(self.run_import())
        self.assertFalse(result['originAuthenticated'])
        self.assertEqual(result['recordings'][0]['split'], 'test')
        self.assertNotIn('text', result['recordings'][0])
    def test_mismatched_selected_capture_is_rejected_without_writes(self):
        with self.assertRaisesRegex(ValueError, 'capture ID'):
            self.run_import('another-capture')
        self.assertFalse(self.output.exists())
    def test_import_does_not_create_consent_or_ground_truth(self):
        self.data['consentConfirmed'] = False
        with self.assertRaisesRegex(ValueError, 'consent'):
            self.run_import()
        self.data['consentConfirmed'] = True
        self.data['recordings'][0]['groundTruthConfirmed'] = False
        with self.assertRaisesRegex(ValueError, 'ground truth'):
            self.run_import()
        self.assertFalse(self.output.exists())
    def test_changed_selected_recording_is_rejected(self):
        self.data['recordings'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.run_import()
    def test_existing_dataset_is_never_overwritten(self):
        self.output.mkdir(); (self.output / 'manifest.json').write_text('frozen')
        with self.assertRaisesRegex(ValueError, 'destination must be empty'):
            self.run_import()
        self.assertEqual((self.output / 'manifest.json').read_text(), 'frozen')
    def test_audio_outside_selected_root_is_rejected(self):
        self.data['recordings'][0]['wav'] = '../outside.wav'
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.run_import()
    def test_continuous_audio_cannot_masquerade_as_a_single_utterance(self):
        write_pcm(self.root / 'voice.wav', np.zeros(9 * 16000, np.float32))
        self.data['recordings'][0]['sha256'] = sha256(self.root / 'voice.wav')
        with self.assertRaisesRegex(ValueError, 'single-utterance'):
            self.run_import()

class SignalAndSelectionTests(unittest.TestCase):
    def test_signal_contract_has_bounded_shape_and_finite_values(self):
        signal = np.sin(np.arange(8000) * .1).astype(np.float32) * .1
        window, eligible = prepare_window(signal)
        self.assertTrue(eligible)
        self.assertEqual(window.shape, (32000,))
        self.assertTrue(np.isfinite(window).all())
        features = log_mel(np.stack([window, np.zeros_like(window)])).numpy()
        self.assertEqual(features.shape, (2, 198, 40, 1))
        self.assertTrue(np.isfinite(features).all())
    def test_invalid_silence_and_oversized_utterances_never_reach_classifier(self):
        invalid = [np.zeros(8000), np.full(8000, np.nan), np.full(8000, 2.0),
                   np.sin(np.arange(40000) * .1).astype(np.float32) * .1, np.array([])]
        for signal in invalid:
            with self.subTest(length=len(signal)):
                window, eligible = prepare_window(signal)
                self.assertFalse(eligible)
                self.assertFalse(np.any(window))
    def dev(self):
        return [dict(split='dev', language=language, target=target)
            for language in ['ru', 'kk', 'en'] for target in [True, False]]
    def test_threshold_selection_refuses_test_records(self):
        records = self.dev(); records[0]['split'] = 'test'
        with self.assertRaisesRegex(ValueError, 'dev only'):
            choose_threshold(records, [.9] * 6, [True] * 6, [.5, .9])
    def test_threshold_must_satisfy_each_language(self):
        result = choose_threshold(self.dev(), [.95, .75] * 3, [True] * 6, [.5, .8, .99])
        self.assertTrue(result['selectionFeasible'])
        self.assertEqual(result['threshold'], .8)
        bad_language = choose_threshold(self.dev(), [.95, .1, .95, .1, .4, .1], [True] * 6, [.5, .9])
        self.assertFalse(bad_language['selectionFeasible'])
    def test_ineligible_positive_counts_as_a_miss_not_a_removed_case(self):
        rows = [dict(target=True, predicted=False, eligible=False, audioSeconds=1),
                dict(target=False, predicted=False, eligible=False, audioSeconds=1)]
        result = summarize(rows)
        self.assertEqual(result['missedPositiveUtterances'], 1)
        self.assertEqual(result['inputGateRejectedPositive'], 1)
        self.assertEqual(result['negativeUtterances'], 1)
    def test_zero_false_positives_in_short_audio_does_not_prove_hourly_target(self):
        rows = [dict(target=False, predicted=False, eligible=True, audioSeconds=60)]
        result = summarize(rows)
        self.assertEqual(result['falsePositiveClipsPerRecordedHour'], 0)
        self.assertGreater(result['poissonOneSided95UpperPerRecordedHour'], .5)

if __name__ == '__main__':
    unittest.main(verbosity=2)

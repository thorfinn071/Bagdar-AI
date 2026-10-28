import copy
import hashlib
import json
import math
import os
import subprocess
import sys
import unittest

from arkit_capture import AUTHORITY, CaptureError, audit
from first_capture_trial import (evaluate, multiply, placement_profile, prepare,
                                 rigid_inverse, summarize_analysis)
import test_arkit_capture as contract_fixture


def transform(matrix, point):
    return [sum(matrix[4*r+c]*point[c] for c in range(4)) for r in range(4)]


class FirstCaptureTrialTest(unittest.TestCase):
    def setUp(self):
        self.fixture = contract_fixture.ArkitCaptureTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.seal()
        self.base = self.fixture.base
        self.receipt = audit(self.fixture.root, self.fixture.rid)
        self.measurements = {
            'schemaVersion': 1, 'scope': 'independent-stationary-mount-measurement',
            'recordingId': self.fixture.rid,
            'captureManifestSha256': self.receipt['manifestSha256'], 'frameId': 1,
            'independentReferenceAssertion': True, 'referenceMethod': 'SYNTHETIC UNIT REFERENCE',
            'cameraOriginWalkingM': [0, 0, 1.42], 'originToleranceM': [.01, .01, .01],
            'yawRightDeg': 0, 'pitchDownDeg': 0, 'rollClockwiseDeg': 0, 'angleToleranceDeg': 1,
        }

    def profile(self, measurements=None):
        return placement_profile(measurements or self.measurements, self.fixture.manifest,
                                 [self.fixture.row], self.receipt)

    def analysis(self, entire=False):
        return {
            'recordingId': self.fixture.rid, 'captureManifestSha256': self.receipt['manifestSha256'],
            'promotionAllowed': False, 'ordinaryCameraWired': False,
            'falseStopReductionEstablished': False, 'measuredClearFrames': 0,
            'captureToDecisionMs': None, 'frames': [{
                'frameId': 1, 'evaluatorReasons': ['unverifiedCalibration'],
                'geometry': {'inputsAdmitted': True, 'entireRequestInView': entire,
                             'expiredAfterAnalysis': False, 'nearGapM': 0 if entire else 1.5,
                             'canAuthorizeMovement': False, 'canCertifyFreeSpace': False,
                             'placementPhysicallyValidated': False},
            }],
        }

    def test_preparation_keeps_all_measurements_unperformed(self):
        output = self.base/'kit'
        report = prepare(output)
        self.assertEqual(report['status'], 'awaiting_capture')
        self.assertEqual(report['captureStatus'], 'not_run')
        self.assertFalse(report['physicalGatePassed'])
        template = json.loads((output/'placement.template.json').read_text(encoding='utf-8'))
        self.assertEqual(template['cameraOriginWalkingM'], [None, None, None])
        self.assertFalse(template['independentReferenceAssertion'])
        checks = json.loads((output/'operator-checks.json').read_text())
        self.assertTrue(all(c['status'] == 'not_run' for c in checks['checks'].values()))
        with self.assertRaises(CaptureError):
            prepare(output)

    def test_zero_angles_have_expected_native_arkit_basis(self):
        profile = self.profile()
        m = profile['diagnosticWorldToWalkingRowMajor']
        self.assertEqual(transform(m, [0, 0, 0, 1]), [0, 0, 1.42, 1])
        self.assertEqual(transform(m, [0, 0, -1, 0]), [0, 1, 0, 0])
        self.assertEqual(transform(m, [0, 1, 0, 0]), [0, 0, 1, 0])
        self.assertFalse(profile['placementUncertaintyPropagated'])
        self.assertTrue(all(profile[k] is False for k in AUTHORITY))

    def test_pitch_yaw_and_roll_signs_are_explicit(self):
        for key, point, expected in [
            ('pitchDownDeg', [0,0,-1,0], [0,math.cos(math.pi/6),-.5,0]),
            ('yawRightDeg', [0,0,-1,0], [.5,math.cos(math.pi/6),0,0]),
            ('rollClockwiseDeg', [1,0,0,0], [math.cos(math.pi/6),0,-.5,0]),
        ]:
            with self.subTest(axis=key):
                data = copy.deepcopy(self.measurements)
                data[key] = 30
                result = transform(self.profile(data)['diagnosticWorldToWalkingRowMajor'], point)
                for actual, target in zip(result, expected):
                    self.assertAlmostEqual(actual, target, places=12)

    def test_world_origin_and_rotation_do_not_change_measured_mount(self):
        world = [0,-1,0,2, 1,0,0,-3, 0,0,1,4, 0,0,0,1]
        self.fixture.row['cameraTransform'] = [world[4*r+c] for c in range(4) for r in range(4)]
        self.fixture.seal()
        self.receipt = audit(self.fixture.root, self.fixture.rid)
        self.measurements['captureManifestSha256'] = self.receipt['manifestSha256']
        combined = multiply(self.profile()['diagnosticWorldToWalkingRowMajor'], world)
        self.assertEqual(transform(combined, [0,0,0,1]), [0,0,1.42,1])
        self.assertEqual(transform(combined, [0,0,-1,0]), [0,1,0,0])
        inverse = multiply(world, rigid_inverse(world))
        self.assertEqual(inverse, [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])

    def test_mount_must_bind_to_the_selected_recording_hash_and_frame(self):
        for key, value in [('recordingId', 'different'), ('captureManifestSha256', '0'*64), ('frameId', 99)]:
            with self.subTest(key=key):
                data = copy.deepcopy(self.measurements)
                data[key] = value
                with self.assertRaises(CaptureError):
                    self.profile(data)

    def test_unmeasured_or_invalid_mount_fields_fail_closed(self):
        for key, value in [
            ('cameraOriginWalkingM', [0,0,None]), ('cameraOriginWalkingM', [0,0,0]),
            ('originToleranceM', [0,.01,.01]), ('pitchDownDeg', None),
            ('pitchDownDeg', float('nan')), ('angleToleranceDeg', 0),
            ('frameId', True), ('schemaVersion', True), ('independentReferenceAssertion', False),
            ('referenceMethod', ''), ('wholePixelBoundsValidated', True),
            ('physicalAlignmentValidated', True),
        ]:
            with self.subTest(key=key, value=value):
                data = copy.deepcopy(self.measurements)
                data[key] = value
                with self.assertRaises(CaptureError):
                    self.profile(data)

    def test_conditional_gap_stops_before_behavioural_collection(self):
        report = summarize_analysis(self.analysis(), self.receipt, True)
        self.assertEqual(report['status'], 'nominal_geometry_gap_observed')
        self.assertEqual(report['maximumConditionalNearGapM'], 1.5)
        self.assertFalse(report['runtimeComparisonAllowed'])
        self.assertFalse(report['behaviouralCollectionAllowed'])

    def test_geometry_that_fits_still_cannot_self_grant_clearance(self):
        report = summarize_analysis(self.analysis(entire=True), self.receipt, True)
        self.assertEqual(report['status'], 'nominal_geometry_possible_physical_evidence_missing')
        self.assertFalse(report['physicalGatePassed'])
        self.assertTrue(all(report[k] is False for k in AUTHORITY))
        self.assertIn('whole_pixel_first_return_bounds', report['missingPhysicalEvidence'])

    def test_missing_stale_or_incomplete_geometry_is_not_a_positive_result(self):
        for change in ['missing', 'expired', 'unknown-expiry', 'inadmissible']:
            with self.subTest(change=change):
                report = self.analysis(entire=True)
                if change == 'missing':
                    del report['frames'][0]['geometry']
                elif change == 'expired':
                    report['frames'][0]['geometry']['expiredAfterAnalysis'] = True
                elif change == 'unknown-expiry':
                    del report['frames'][0]['geometry']['expiredAfterAnalysis']
                else:
                    report['frames'][0]['geometry']['inputsAdmitted'] = False
                result = summarize_analysis(report, self.receipt, True)
                self.assertEqual(result['status'], 'nominal_geometry_inconclusive')

    def test_missing_placement_does_not_infer_a_mount(self):
        result = summarize_analysis(self.analysis(), self.receipt, False)
        self.assertEqual(result['status'], 'awaiting_independent_placement')

    def test_fake_or_unbound_analysis_is_rejected(self):
        for key, value in [('recordingId','different'), ('captureManifestSha256','0'*64),
                           ('promotionAllowed',True), ('measuredClearFrames',1)]:
            with self.subTest(key=key):
                data = self.analysis()
                data[key] = value
                with self.assertRaises(CaptureError):
                    summarize_analysis(data, self.receipt, True)
        data = self.analysis()
        del data['frames'][0]['geometry']['entireRequestInView']
        with self.assertRaises(CaptureError):
            summarize_analysis(data, self.receipt, True)

    def test_output_inside_original_capture_and_git_media_are_rejected(self):
        with self.assertRaises(CaptureError):
            evaluate(self.fixture.root, self.fixture.rid, self.fixture.root/'new-output')
        (self.base/'.git').mkdir()
        with self.assertRaisesRegex(CaptureError, 'outside Git'):
            evaluate(self.fixture.root, self.fixture.rid, self.base/'outside-output')

    def test_cli_preparation_does_not_claim_a_physical_run(self):
        result = subprocess.run([sys.executable, 'tool/research_capture/first_capture_trial.py',
            'prepare', '--output', str(self.base/'cli-kit')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(result.stdout)['physicalGatePassed'])

    def test_actual_python_to_dart_flow_with_and_without_mount(self):
        if os.environ.get('BAGDAR_TEST_FIRST_CAPTURE_DART') != '1':
            self.skipTest('opt-in actual Dart process; software fixture only')
        before = {p.relative_to(self.fixture.root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in self.fixture.root.rglob('*') if p.is_file()}
        plain = evaluate(self.fixture.root, self.fixture.rid, self.base/'no-mount')
        self.assertEqual(plain['status'], 'awaiting_independent_placement')
        placed = evaluate(self.fixture.root, self.fixture.rid, self.base/'with-mount', self.measurements)
        self.assertEqual(placed['status'], 'nominal_geometry_gap_observed')
        self.assertGreater(placed['maximumConditionalNearGapM'], 0)
        self.assertIsNone(placed['captureToDecisionMs'])
        self.assertFalse(placed['physicalGatePassed'])
        placement_path = self.base/'placement.json'
        placement_path.write_text(json.dumps(self.measurements), encoding='utf-8')
        cli = subprocess.run([sys.executable, 'tool/research_capture/first_capture_trial.py',
            'evaluate', str(self.fixture.root), '--recording-id', self.fixture.rid,
            '--placement', str(placement_path), '--output', str(self.base/'cli-evaluation')],
            capture_output=True, text=True)
        self.assertEqual(cli.returncode, 2, cli.stdout+cli.stderr)
        self.assertEqual(json.loads(cli.stdout)['status'], 'nominal_geometry_gap_observed')
        after = {p.relative_to(self.fixture.root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in self.fixture.root.rglob('*') if p.is_file()}
        self.assertEqual(after, before)
        with self.assertRaises(CaptureError):
            evaluate(self.fixture.root, self.fixture.rid, self.base/'with-mount', self.measurements)


if __name__ == '__main__':
    unittest.main()

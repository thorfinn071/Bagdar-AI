"""Check continuous scoring against independently hand-computed cases."""
import unittest
from render_volume_holdout import entry_time, current_truth


class HoldoutScoringTest(unittest.TestCase):
    def test_floor_contact_is_not_body_occupancy(self):
        self.assertIsNone(entry_time([-4, -1, -.1], [4, 8, 0], [0, -.2, 0]))

    def test_thin_current_pole_is_hazard(self):
        self.assertEqual(entry_time([.056, 2.305, 0], [.066, 2.315, 1.72], [0, 0, 0]), 0)

    def test_crossing_entry_is_continuous_between_captures(self):
        self.assertAlmostEqual(entry_time([1, 2, 0], [1.4, 2.4, 1.5], [-2, 0, 0]), .275, places=5)

    def test_approach_in_body_coordinates_includes_camera_travel(self):
        self.assertAlmostEqual(entry_time([-.2, 3.8, 0], [.2, 4.2, 1.5], [0, -1, 0]), .3, places=5)

    def test_off_path_motion_never_intersects(self):
        self.assertIsNone(entry_time([1, 2, 0], [1.4, 2.4, 1.5], [.5, 0, 0]))

    def test_floor_discontinuity_is_a_separate_positive_label(self):
        label = {'walkingOriginWorldM': [0, 0, 0], 'geometry': [], 'floorDiscontinuity': True}
        self.assertEqual(current_truth(label), (True, []))
        label['floorDiscontinuity'] = False
        self.assertEqual(current_truth(label), (False, []))


if __name__ == '__main__': unittest.main()

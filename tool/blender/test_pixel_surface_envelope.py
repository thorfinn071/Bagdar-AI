"""Coverage admission contrasts; no Blender installation is needed."""
import math
import unittest

from pixel_surface_envelope import first_return_upper


def rectangle(x0, x1, z, y0=0, y1=1):
    return [([(x0, y0), (x1, y0), (x1, y1)], (0, 0, 1/z)),
            ([(x0, y0), (x1, y1), (x0, y1)], (0, 0, 1/z))]


class EnvelopeTests(unittest.TestCase):
    def test_adjacent_surfaces_cover_the_whole_pixel(self):
        self.assertAlmostEqual(first_return_upper(0, 0, rectangle(0, .4, 2) + rectangle(.4, 1, 2.01)), 2.01)

    def test_overlapping_area_cannot_fill_a_hole(self):
        patches = rectangle(0, .7, 2) + rectangle(.1, .8, 2)
        self.assertTrue(math.isnan(first_return_upper(0, 0, patches)))

    def test_subpixel_gap_remains_unknown(self):
        patches = rectangle(0, .499999, 2) + rectangle(.500001, 1, 2)
        self.assertTrue(math.isnan(first_return_upper(0, 0, patches)))

    def test_translated_subpixel_gap_remains_unknown(self):
        patches = rectangle(0, .499999, 2) + rectangle(.500001, 1, 2)
        shifted = [([(x+300, y+200) for x, y in tri], coef) for tri, coef in patches]
        self.assertTrue(math.isnan(first_return_upper(300, 200, shifted)))

    def test_thin_foreground_retains_bounded_first_surface(self):
        patches = rectangle(.49999, .50001, .5) + rectangle(0, 1, 2)
        self.assertAlmostEqual(first_return_upper(0, 0, patches), 2)
        self.assertAlmostEqual(first_return_upper(0, 0, rectangle(0, 1, .5) + patches), .5)

    def test_hidden_depth_cannot_change_visible_envelope(self):
        foreground = rectangle(0, .4, 2) + rectangle(.4, 1, 2.01)
        self.assertEqual(first_return_upper(0, 0, foreground),
                         first_return_upper(0, 0, foreground + rectangle(0, 1, 3)))

    def test_crossing_planes_choose_nearest_analytically(self):
        full = rectangle(0, 1, 1)
        patches = [(tri, (.5, 0, .5)) for tri, _ in full]
        patches += [(tri, (-.5, 0, 1)) for tri, _ in full]
        self.assertAlmostEqual(first_return_upper(0, 0, patches), 4/3)

    def test_budget_exhaustion_is_unknown(self):
        self.assertTrue(math.isnan(first_return_upper(0, 0, rectangle(0, 1, 2), maximum_fragments=1)))

    def test_nonpositive_depth_is_unknown(self):
        patches = [(tri, (1, 0, -.5)) for tri, _ in rectangle(0, 1, 2)]
        self.assertTrue(math.isnan(first_return_upper(0, 0, patches)))


if __name__ == '__main__':
    unittest.main()

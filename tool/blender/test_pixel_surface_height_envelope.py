import math
import unittest

from pixel_surface_envelope import first_return_upper
from pixel_surface_height_envelope import first_return_bounds
from test_pixel_surface_envelope import rectangle


class HeightEnvelopeTests(unittest.TestCase):
    def test_same_axis_bound_and_correlated_height_extrema(self):
        patches = rectangle(0,.4,1)+rectangle(.4,1,1.001)
        z,lo,hi = first_return_bounds(0,0,patches,(0,0,-1),1)
        self.assertEqual(z,first_return_upper(0,0,patches))
        self.assertAlmostEqual(lo,-.001)
        self.assertAlmostEqual(hi,0)

    def test_fractional_plane_extrema_enclose_independent_samples(self):
        patches = [(tri,(.2,.1,.8)) for tri,_ in rectangle(0,1,1)]
        _,lo,hi = first_return_bounds(0,0,patches,(.1,.3,-1),1.42)
        for ix in range(21):
            for iy in range(21):
                x,y=ix/20,iy/20
                actual=1.42+(.1*x+.3*y-1)/(.2*x+.1*y+.8)
                self.assertLessEqual(lo,actual+1e-14)
                self.assertGreaterEqual(hi,actual-1e-14)

    def test_hole_never_yields_height_bounds(self):
        bounds=first_return_bounds(0,0,rectangle(0,.7,1)+rectangle(.1,.8,1),(0,0,-1),1)
        self.assertTrue(all(math.isnan(v) for v in bounds))

    def test_thin_visible_surface_not_erased_by_background(self):
        patches=rectangle(.49999,.50001,.5)+rectangle(0,1,2)
        _,lo,hi=first_return_bounds(0,0,patches,(0,0,-1),2)
        self.assertAlmostEqual(lo,0)
        self.assertAlmostEqual(hi,1.5)

    def test_hidden_surface_cannot_change_any_bound(self):
        front=rectangle(0,.4,1)+rectangle(.4,1,1.001)
        self.assertEqual(first_return_bounds(0,0,front,(0,0,-1),1),
                         first_return_bounds(0,0,front+rectangle(0,1,3),(0,0,-1),1))


if __name__ == '__main__':
    unittest.main()

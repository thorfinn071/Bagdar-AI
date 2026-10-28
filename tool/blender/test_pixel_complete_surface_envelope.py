import math
import unittest
from pixel_complete_surface_envelope import first_return_bounds
from pixel_surface_envelope import first_return_upper
from test_pixel_surface_envelope import rectangle


class CompleteEnvelopeTests(unittest.TestCase):
    def test_full_coverage_independent_minimum_and_heights(self):
        patches=rectangle(0,.4,1)+rectangle(.4,1,1.001)
        upper,hlo,hhi,lower=first_return_bounds(0,0,patches,(0,0,-1),1)
        self.assertEqual(upper,first_return_upper(0,0,patches))
        self.assertAlmostEqual(lower,1)
        self.assertAlmostEqual(hlo,-.001)
        self.assertAlmostEqual(hhi,0)

    def test_thin_foreground_controls_minimum(self):
        _,_,_,lower=first_return_bounds(0,0,rectangle(.49999,.50001,.5)+rectangle(0,1,2),(0,0,-1),2)
        self.assertAlmostEqual(lower,.5)

    def test_hole_makes_all_bounds_unknown(self):
        bounds=first_return_bounds(0,0,rectangle(0,.7,1)+rectangle(.1,.8,1),(0,0,-1),1)
        self.assertTrue(all(math.isnan(v) for v in bounds))

    def test_subpixel_gap_is_not_interpolated(self):
        bounds=first_return_bounds(0,0,rectangle(0,.499999,1)+rectangle(.500001,1,1),(0,0,-1),1)
        self.assertTrue(all(math.isnan(v) for v in bounds))

    def test_fractional_extrema_enclose_all_sampled_rays(self):
        patches=[(tri,(.2,.1,.8)) for tri,_ in rectangle(0,1,1)]
        upper,hlo,hhi,lower=first_return_bounds(0,0,patches,(.1,.3,-1),1.42)
        for ix in range(21):
            for iy in range(21):
                x,y=ix/20,iy/20
                inverse=.2*x+.1*y+.8
                h=1.42+(.1*x+.3*y-1)/inverse
                self.assertLessEqual(lower,1/inverse+1e-14)
                self.assertGreaterEqual(upper,1/inverse-1e-14)
                self.assertLessEqual(hlo,h+1e-14)
                self.assertGreaterEqual(hhi,h-1e-14)

    def test_hidden_surfaces_change_no_bound(self):
        front=rectangle(0,.4,1)+rectangle(.4,1,1.001)
        self.assertEqual(first_return_bounds(0,0,front,(0,0,-1),1),
                         first_return_bounds(0,0,front+rectangle(0,1,3),(0,0,-1),1))

    def test_fragment_budget_exhaustion_is_unknown(self):
        bounds=first_return_bounds(0,0,rectangle(0,1,1),(0,0,-1),1,maximum_fragments=1)
        self.assertTrue(all(math.isnan(v) for v in bounds))


if __name__=='__main__': unittest.main()

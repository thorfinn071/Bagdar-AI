import math
import unittest
from pixel_exact_surface_envelope import first_return_bounds
from test_pixel_surface_envelope import rectangle

class ExactPartitionTests(unittest.TestCase):
    def test_closed_shared_diagonal_has_no_hidden_bottom(self):
        # Large projected vertices with one edge traversed in both directions.
        a=(-12345.123456789,-34567.987654321);b=(45678.456789,12345.23456789)
        front=[([a,b,(-1e6,1e6)],(0,0,1)),([b,a,(1e6,-1e6)],(0,0,1))]
        result=first_return_bounds(0,0,front+rectangle(0,1,1.16),(0,0,-1),1)
        self.assertAlmostEqual(result[1],0)
        self.assertAlmostEqual(result[2],0)

    def test_every_representable_positive_gap_remains_unknown(self):
        for a,b in [(.5-1e-12,.5+1e-12),
                    (math.nextafter(.5,0),math.nextafter(.5,1))]:
            result=first_return_bounds(0,0,rectangle(0,a,1)+rectangle(b,1,1),(0,0,-1),1)
            self.assertTrue(all(math.isnan(v) for v in result))

    def test_overlapping_area_never_fills_an_uncovered_fragment(self):
        result=first_return_bounds(0,0,rectangle(0,.7,1)+rectangle(.1,.8,1),(0,0,-1),1)
        self.assertTrue(all(math.isnan(v) for v in result))

    def test_subpixel_foreground_controls_height_and_free_minimum(self):
        result=first_return_bounds(0,0,rectangle(.499999,.500001,.5)+rectangle(0,1,1),(0,0,-1),1)
        self.assertAlmostEqual(result[2],.5)
        self.assertAlmostEqual(result[3],.5)

    def test_visible_drop_is_retained(self):
        result=first_return_bounds(0,0,rectangle(0,.5,1)+rectangle(.5,1,1.2),(0,0,-1),1)
        self.assertAlmostEqual(result[1],-.2)

    def test_hidden_surfaces_are_irrelevant(self):
        front=rectangle(0,1,1)
        self.assertEqual(first_return_bounds(0,0,front,(0,0,-1),1),
                         first_return_bounds(0,0,front+rectangle(0,1,3),(0,0,-1),1))

    def test_fragment_budget_exhaustion_is_unknown(self):
        result=first_return_bounds(0,0,rectangle(0,1,1),(0,0,-1),1,maximum_fragments=1)
        self.assertTrue(all(math.isnan(v) for v in result))

if __name__=='__main__':unittest.main()

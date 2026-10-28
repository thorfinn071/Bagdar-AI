import math
import unittest
from pixel_watertight_surface_envelope import first_return_bounds, triangle_edges
from watertight_surface_projection import clip_near
from test_pixel_surface_envelope import rectangle


class WatertightTests(unittest.TestCase):
    def test_shared_edge_coefficients_are_exact_opposites(self):
        a=(164.1609844993327,112.);b=(20000.123456789,-12345.987654321)
        mx,my=(a[0]+b[0])/2,(a[1]+b[1])/2
        dx,dy=b[0]-a[0],b[1]-a[1]
        left=(mx-dy,my+dx);right=(mx+dy,my-dx)
        first=triangle_edges([a,b,left])[0]
        second=triangle_edges([b,a,right])[0]
        self.assertEqual(first,tuple(-v for v in second))
        reversed_winding=triangle_edges([b,a,left])[0]
        self.assertEqual(first,reversed_winding)

    def test_shared_near_vertex_is_exact_in_both_directions(self):
        a=(-3.2123456789,-1.12345,-.1234567);b=(2.987654321,8.12345,9.12345)
        first=clip_near([a,b,(0,0,1)])[0]
        second=clip_near([b,a,(0,0,-1)])[1]
        self.assertEqual(first,second)
        self.assertEqual(first[2],.01)

    def test_real_positive_area_gaps_remain_unknown(self):
        for gap in (1e-6,1e-9,1e-12):
            result=first_return_bounds(0,0,rectangle(0,.5-gap,1)+rectangle(.5+gap,1,1),(0,0,-1),1)
            self.assertTrue(all(math.isnan(v) for v in result),gap)

    def test_overlapping_triangles_cannot_fill_a_hole(self):
        result=first_return_bounds(0,0,rectangle(0,.7,1)+rectangle(.1,.8,1),(0,0,-1),1)
        self.assertTrue(all(math.isnan(v) for v in result))

    def test_subpixel_foreground_height_is_retained(self):
        result=first_return_bounds(0,0,rectangle(.49999,.50001,.5)+rectangle(0,1,1),(0,0,-1),1)
        self.assertAlmostEqual(result[2],.5)
        self.assertAlmostEqual(result[3],.5)

    def test_visible_drop_is_retained(self):
        result=first_return_bounds(0,0,rectangle(0,.5,1)+rectangle(.5,1,1.2),(0,0,-1),1)
        self.assertAlmostEqual(result[1],-.2)

    def test_hidden_surface_changes_no_bound(self):
        front=rectangle(0,1,1)
        self.assertEqual(first_return_bounds(0,0,front,(0,0,-1),1),
                         first_return_bounds(0,0,front+rectangle(0,1,3),(0,0,-1),1))

if __name__=='__main__':unittest.main()

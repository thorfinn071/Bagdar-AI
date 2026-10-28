"""Blender-only negative and projection tests; no corpus writes."""
import math
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g

s,c,*_=g.setup('wide','validation')
c.rotation_euler=g.camera_rotation(0,-8,0).to_euler()
bpy.context.view_layer.update()
p=c.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=g.W,y=g.H,scale_x=1,scale_y=1)
fx,fy=p[0][0]*g.W/2,p[1][1]*g.H/2
assert abs(fx-fy)<1e-3
assert abs(2*math.atan(1/p[1][1])-c.data.angle_y)>.05
depth,lo,hi,valid=g.visible_depth(s,c,fx,fy,g.W/2,g.H/2)
deps=bpy.context.evaluated_depsgraph_get()
for y in range(12,g.H,29):
    for x in range(12,g.W,31):
        ray=Vector(((x+.5-g.W/2)/fx,-(y+.5-g.H/2)/fy,-1)).normalized()
        direction=c.matrix_world.to_quaternion() @ ray
        hit,point,*_=s.ray_cast(deps,c.location,direction,distance=20)
        assert hit==bool(valid[y,x])
        if hit:assert abs((point-c.location).length-depth[y,x])<1e-4
# Change geometry fully behind an opaque covering wall: observations unchanged.
g.cube('cover',(0,1.2,1.5),(8,.1,5),(.2,.2,.2))
bpy.context.view_layer.update()
before=g.visible_depth(s,c,fx,fy,g.W/2,g.H/2)
hidden=g.cube('hidden',(0,2.2,1),(0.2,.1,.5),(.5,.1,.1))
bpy.context.view_layer.update()
after=g.visible_depth(s,c,fx,fy,g.W/2,g.H/2)
for a,b in zip(before,after):assert np.array_equal(a,b,equal_nan=True)
# A very thin pole on a pixel boundary must affect footprint lower bounds even
# when neither neighbouring central ray hits it.
bpy.data.objects.remove(bpy.data.objects['cover'],do_unlink=True)
bpy.data.objects.remove(hidden,do_unlink=True)
g.cube('between-rays',(0,1.4,1.45),(.0005,.0005,.4),(.2,.2,.2))
bpy.context.view_layer.update()
thin=g.visible_depth(s,c,fx,fy,g.W/2,g.H/2)
assert np.any((thin[1]<lo-.1)&(abs(thin[0]-depth)<1e-4))
print('Visible renderer: projection/raycast, hidden-geometry invariance, subpixel footprint tests passed')

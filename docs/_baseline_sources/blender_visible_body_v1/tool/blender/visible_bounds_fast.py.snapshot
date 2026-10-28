"""Same whole-pixel bounds as the frozen renderer; linear surface exclusion.

Rasterization and all safety margins are unchanged. Only the min over other
planes is reduced with the two smallest per-record depths, including ties.
"""
import math
import bpy
import numpy as np
from generate_visible_passage_corpus import clip_near, clipped_area

def visible_depth(scene, camera, fx, fy, cx, cy, width, height):
    """Conservative rasterization of opaque triangles in camera coordinates.

    Minimum axis depth over a WHOLE pixel footprint (not its centre) prevents
    subpixel occupancy from disappearing. Surface upper bounds are published
    only when a coplanar group covers the entire pixel and no competing plane
    can occlude it. Thus hidden surfaces never certify floor or free space.
    """
    W, H = width, height
    inv = camera.matrix_world.inverted()
    groups = {}
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type != 'MESH':
            continue
        e = obj.evaluated_get(deps)
        mesh = e.to_mesh()
        mesh.calc_loop_triangles()
        pts = []
        for v in mesh.vertices:
            p = inv @ (e.matrix_world @ v.co)
            pts.append(np.array([p.x, -p.y, -p.z]))
        for tri in mesh.loop_triangles:
            poly = clip_near([pts[i] for i in tri.vertices])
            for i in range(1, len(poly)-1):
                t = np.array([poly[0],poly[i],poly[i+1]])
                screen = t[:,:2] / t[:,2,None] * [fx,fy] + [cx,cy]
                try:
                    coef = np.linalg.solve(np.column_stack((screen,np.ones(3))),1/t[:,2])
                except np.linalg.LinAlgError:
                    continue
                key = tuple(np.round(coef, 9))
                groups.setdefault(key, []).append((screen,coef))
        e.to_mesh_clear()
    centre = np.full((H,W),np.inf)
    lower = np.full((H,W),np.inf)
    records = []
    for triangles in groups.values():
        covered = np.zeros((H,W))
        nearest = np.full((H,W),np.inf)
        farthest = np.zeros((H,W))
        hit_centre = np.full((H,W),np.inf)
        for t,coef in triangles:
            x0=max(0,int(math.floor(t[:,0].min()))); x1=min(W,int(math.ceil(t[:,0].max())))
            y0=max(0,int(math.floor(t[:,1].min()))); y1=min(H,int(math.ceil(t[:,1].max())))
            if x0>=x1 or y0>=y1:
                continue
            xx,yy=np.meshgrid(np.arange(x0,x1)+.5,np.arange(y0,y1)+.5)
            signed=[]
            orientation=np.cross(t[1]-t[0],t[2]-t[0])
            sign=1 if orientation>=0 else -1
            for a,b in zip(t,np.roll(t,-1,axis=0)):
                dx,dy=b-a
                v=sign*(dx*(yy-a[1])-dy*(xx-a[0]))
                radius=(abs(dx)+abs(dy))*.5
                signed.append((v,radius))
            overlap=np.logical_and.reduce([v+r>=-1e-9 for v,r in signed])
            inside=np.logical_and.reduce([v-r>=-1e-9 for v,r in signed])
            at_centre=np.logical_and.reduce([v>=-1e-9 for v,r in signed])
            inverse=coef[0]*xx+coef[1]*yy+coef[2]
            spread=(abs(coef[0])+abs(coef[1]))*.5
            lo=np.where(overlap & (inverse+spread>0),1/np.maximum(inverse+spread,1e-20),np.inf)
            hi=np.where(overlap & (inverse-spread>0),1/np.maximum(inverse-spread,1e-20),np.inf)
            sub=nearest[y0:y1,x0:x1]; np.minimum(sub,lo,out=sub)
            sub=farthest[y0:y1,x0:x1]; np.maximum(sub,np.where(overlap,hi,0),out=sub)
            sub=hit_centre[y0:y1,x0:x1]; np.minimum(sub,np.where(at_centre & (inverse>0),1/np.maximum(inverse,1e-20),np.inf),out=sub)
            area=inside.astype(float)
            for iy,ix in np.argwhere(overlap & ~inside):
                area[iy,ix]=clipped_area(t,x0+ix,y0+iy)
            covered[y0:y1,x0:x1]+=area
        np.minimum(centre,hit_centre,out=centre)
        np.minimum(lower,nearest,out=lower)
        records.append((covered,nearest,farthest,hit_centre))
    # Exactly the same exclusion of competing surfaces, using the two
    # smallest distinct-record depths per pixel. Ties occupy both positions.
    # The minimum over all OTHER records replaces the quadratic comparison.
    first = np.full((H, W), np.inf)
    second = np.full((H, W), np.inf)
    for covered, nearest, farthest, hit_centre in records:
        second = np.where(nearest < first, first, np.minimum(second, nearest))
        first = np.minimum(first, nearest)
    upper=np.full((H,W),np.nan)
    for covered,nearest,farthest,hit_centre in records:
        full=(covered>=1-1e-7) & np.isfinite(hit_centre) & (abs(hit_centre-centre)<1e-5)
        other_minimum = np.where(nearest == first, second, first)
        full &= other_minimum > farthest + 1e-7
        upper[full]=farthest[full]
    xx,yy=np.meshgrid(np.arange(W)+.5,np.arange(H)+.5)
    ray_length=np.sqrt(1+((xx-cx)/fx)**2+((yy-cy)/fy)**2)
    valid=np.isfinite(centre) & (centre*ray_length<=20)
    radial=np.where(valid,centre*ray_length,np.nan)
    lower=np.where(valid & np.isfinite(lower),np.maximum(0,lower-1e-5),np.nan)
    upper=np.where(valid & np.isfinite(upper),upper+1e-5,np.nan)
    return radial.astype('<f4'),lower.astype('<f4'),upper.astype('<f4'),valid.astype('uint8')


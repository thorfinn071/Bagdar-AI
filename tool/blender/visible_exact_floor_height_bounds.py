"""Sparse independent whole-pixel height proof using canonical projection."""
import math
import bpy
import numpy as np
from watertight_surface_projection import clip_near
from pixel_exact_surface_envelope import first_return_bounds


def floor_heights(scene, camera, fx, fy, cx, cy, radial, previous_lo, previous_hi,
                  maximum_rise=.05, maximum_drop=.05):
    h, w = radial.shape
    world = np.array(camera.matrix_world, dtype=float)
    rotation = world[:3,:3] @ np.diag([1.,-1.,-1.])
    origin_height = float(world[2,3])
    hc = (rotation[2,0]/fx, rotation[2,1]/fy,
          rotation[2,2]-rotation[2,0]*cx/fx-rotation[2,1]*cy/fy)
    yy, xx = np.mgrid[:h,:w]
    norm = np.sqrt(1+((xx+.5-cx)/fx)**2+((yy+.5-cy)/fy)**2)
    centre_height = origin_height + radial/norm * (hc[0]*(xx+.5)+hc[1]*(yy+.5)+hc[2])
    already = np.isfinite(previous_lo) & np.isfinite(previous_hi) & (previous_lo>=-maximum_drop) & (previous_hi<=maximum_rise)
    selected = np.isfinite(radial) & (centre_height>=-maximum_drop) & (centre_height<=maximum_rise) & ~already
    candidates = {(int(y), int(x)): [] for y,x in np.argwhere(selected)}
    inv = camera.matrix_world.inverted()
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        points = []
        for vertex in mesh.vertices:
            p = inv @ (evaluated.matrix_world @ vertex.co)
            points.append((p.x,-p.y,-p.z))
        for triangle in mesh.loop_triangles:
            polygon = clip_near([points[i] for i in triangle.vertices])
            for k in range(1,len(polygon)-1):
                t = np.array([polygon[0],polygon[k],polygon[k+1]])
                screen = t[:,:2]/t[:,2,None]*[fx,fy]+[cx,cy]
                try:
                    coef = np.linalg.solve(np.column_stack((screen,np.ones(3))),1/t[:,2])
                except np.linalg.LinAlgError:
                    continue
                x0=max(0,int(math.floor(screen[:,0].min())));x1=min(w,int(math.ceil(screen[:,0].max())))
                y0=max(0,int(math.floor(screen[:,1].min())));y1=min(h,int(math.ceil(screen[:,1].max())))
                if x0>=x1 or y0>=y1:
                    continue
                px,py=np.meshgrid(np.arange(x0,x1)+.5,np.arange(y0,y1)+.5)
                orientation=np.cross(screen[1]-screen[0],screen[2]-screen[0])
                if orientation==0:
                    continue
                sign=1 if orientation>0 else -1
                overlap=selected[y0:y1,x0:x1].copy()
                for a,b in zip(screen,np.roll(screen,-1,axis=0)):
                    dx,dy=b-a
                    # Conservative broad phase only; the exact partition
                    # below never dilates the triangles' actual boundaries.
                    overlap &= sign*(dx*(py-a[1])-dy*(px-a[0]))+(abs(dx)+abs(dy))*.5>=-1e-9
                patch=(screen.tolist(),coef.tolist())
                for iy,ix in np.argwhere(overlap):
                    candidates[(y0+int(iy),x0+int(ix))].append(patch)
        evaluated.to_mesh_clear()
    lo,hi=previous_lo.copy(),previous_hi.copy()
    changed=0
    for (y,x),patches in candidates.items():
        _,minimum,maximum,_=first_return_bounds(x,y,patches,hc,origin_height)
        lo[y,x]=minimum-1e-5 if math.isfinite(minimum) else np.nan
        hi[y,x]=maximum+1e-5 if math.isfinite(maximum) else np.nan
        changed+=1
    return lo.astype('<f4'),hi.astype('<f4'),changed

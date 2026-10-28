"""Label-free exact finite pose selection for the frozen producer's box grid.

Geometry only: a selected view must still supply valid whole-pixel first-return
and floor bounds. No depth values, scoring labels or scene meshes are read.
"""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1/manifest.json'
DEFAULT_OUTPUT = ROOT / 'scratch/single-camera-minimal-scan-2026-10-11/geometry-plan.json'


def geometry(packet):
    return {key: packet[key] for key in ('width', 'height', 'fx', 'fy', 'cx', 'cy',
                                       'cameraToWalkingRotation', 'cameraOriginM')}


def plan(packets, refinement=4):
    """Every terminal cell must fit wholly inside at least one selected frustum."""
    rotations = np.array([p['cameraToWalkingRotation'] for p in packets]).reshape(-1, 3, 3)
    origins = np.array([p['cameraOriginM'] for p in packets])
    fx, fy, cx, cy, width, height = [np.array([p[k] for p in packets])[:, None] for k in ('fx', 'fy', 'cx', 'cy', 'width', 'height')]
    constraints = set()
    visited = 0

    def visit(box, depth, floor):
        nonlocal visited
        visited += 1
        points = np.array(list(itertools.product(*[(a, b) for a, b in box])))
        camera = np.einsum('vpi,vij->vpj', points[None, :, :] - origins[:, None, :], rotations)
        x, y, z = (camera[:, :, i] for i in range(3))
        planes = np.stack([z - .0100001, fx*x + cx*z,
                           (width-cx)*z-fx*x, fy*y+cy*z,
                           (height-cy)*z-fy*y], axis=2)
        inside = np.all(planes >= 1e-10, axis=(1, 2))
        possible = ~np.any(np.all(planes < 0, axis=1), axis=1)
        contained = sum(1 << i for i, value in enumerate(inside) if value)
        possible_mask = sum(1 << i for i, value in enumerate(possible) if value)
        if depth == 0 or contained == possible_mask:
            if not contained:
                raise ValueError(f'No view contains terminal box {box}')
            constraints.add(contained)
            return
        parts = [[(a, (a+b)/2), ((a+b)/2, b)] for a, b in box]
        if floor:
            parts[2] = [box[2]]
        for child in itertools.product(*parts):
            visit(child, depth - 1, floor)

    for iy in range(22):
        y0, y1 = .2 + 3.3*iy/22, .2 + 3.3*(iy+1)/22
        for ix in range(6):
            x0, x1 = -.45 + .9*ix/6, -.45 + .9*(ix+1)/6
            visit(((x0, x1), (y0, y1), (0, 0)), refinement, True)
            for iz in range(13):
                z0, z1 = .05 + 1.85*iz/13, .05 + 1.85*(iz+1)/13
                visit(((x0, x1), (y0, y1), (z0, z1)), refinement, False)
    # If A is a subset of B, hitting A also hits B; B adds no constraint.
    minimal = sorted(m for m in constraints if not any(n != m and n & m == n for n in constraints))
    feasible = [m for m in range(1, 1 << len(packets)) if all(m & c for c in minimal)]
    count = min(m.bit_count() for m in feasible)
    masks = [m for m in feasible if m.bit_count() == count]
    return {'refinementDepth': refinement, 'visitedBoxes': visited,
            'terminalViewMasks': sorted(constraints), 'minimalConstraints': minimal,
            'minimumViews': count, 'minimumViewMasks': masks,
            'selectedIndices': [i for i in range(len(packets)) if masks[0] & (1 << i)],
            'canCertifyFreeSpace': False, 'canAuthorizeMovement': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    data = json.loads(MANIFEST.read_bytes())
    cache, layouts = {}, []
    for layout in data['layouts']:
        packets = [geometry(f['axisPacket']) for f in layout['frames']]
        key = hashlib.sha256(json.dumps(packets, sort_keys=True).encode()).hexdigest()
        if key not in cache:
            cache[key] = {'geometrySha256': key, 'views': packets, **plan(packets)}
        layouts.append({'sceneId': layout['sceneId'], 'geometrySha256': key})
    result = {'scope': 'geometry-only hypothetical pose plan; no measured clearance or temporal authority',
              'sourceSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'manifestSha256': hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
              'plans': list(cache.values()), 'layouts': layouts,
              'promotionAllowed': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as file:
        file.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps([{k: p[k] for k in ('minimumViews', 'minimumViewMasks', 'selectedIndices', 'visitedBoxes')} for p in cache.values()]))


if __name__ == '__main__':
    main()

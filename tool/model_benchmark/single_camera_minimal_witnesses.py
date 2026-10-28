"""Independent point witnesses for the finite-pose lower bound; metadata only."""
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/single-camera-minimal-scan-2026-10-11'
plan = json.loads((OUT / 'geometry-plan.json').read_bytes())
results = []
for p in plan['plans']:
    views = p['views']
    witnesses = {}
    inspected = 0
    # Finest-grid centres and the independently checked supporting floor.
    xs = -.45 + .9 * (np.arange(96) + .5) / 96
    ys = .2 + 3.3 * (np.arange(352) + .5) / 352
    xy = np.stack(np.meshgrid(xs, ys), axis=-1).reshape(-1, 2)
    heights = np.r_[0, .05 + 1.85 * (np.arange(208) + .5) / 208]
    for height in heights:
        points = np.c_[xy, np.full(len(xy), height)]
        masks = np.zeros(len(points), dtype=np.int32)
        for i, v in enumerate(views):
            # Row-vector multiplication by R is R^T applied to a column point.
            camera = (points - v['cameraOriginM']) @ np.array(v['cameraToWalkingRotation']).reshape(3, 3)
            z = camera[:, 2]
            with np.errstate(divide='ignore', invalid='ignore'):
                u = v['fx'] * camera[:, 0] / z + v['cx']
                t = v['fy'] * camera[:, 1] / z + v['cy']
            seen = (z > .0100001) & (u >= 0) & (u < v['width']) & (t >= 0) & (t < v['height'])
            masks |= seen.astype(np.int32) << i
        for i in p['selectedIndices']:
            bit = 1 << i
            if bit not in witnesses:
                hits = np.flatnonzero(masks == bit)
                if hits.size:
                    witnesses[bit] = {'viewIndex': i, 'pointM': points[hits[0]].tolist()}
        inspected += len(points)
        if len(witnesses) == len(p['selectedIndices']):
            break
    results.append({'geometrySha256': p['geometrySha256'],
        'pointChecks': inspected, 'uniqueViewWitnesses': list(witnesses.values()),
        'independentMinimumRequiredViews': len(witnesses),
        'allSelectedViewsIndependentlyNecessary': len(witnesses) == len(p['selectedIndices'])})
result = {'scope': 'necessary point observability among the twelve frozen poses only',
    'sourceSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'planSha256': hashlib.sha256((OUT / 'geometry-plan.json').read_bytes()).hexdigest(),
    'results': results, 'canCertifyFreeSpace': False, 'canAuthorizeMovement': False}
with (OUT / 'geometry-witnesses.json').open('x', encoding='utf-8') as file:
    file.write(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))

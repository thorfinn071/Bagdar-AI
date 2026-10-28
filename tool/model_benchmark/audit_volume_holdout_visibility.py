"""Post-outcome independent ray witnesses for missing upper-body first returns."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/volume-holdout-2026-10-10'


def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ray_box(origin, direction, lower, upper):
    enter, leave = 0., math.inf
    for o, d, a, b in zip(origin, direction, lower, upper):
        if abs(d) < 1e-12:
            if o < a or o > b: return None
        else:
            near, far = sorted(((a - o) / d, (b - o) / d))
            enter, leave = max(enter, near), min(leave, far)
            if enter > leave: return None
    return enter if leave > 1e-6 else None


def build():
    labels = read(OUT / 'corpus/annotations.json')
    label = labels['layouts'][0]['frames'][0]
    optical = read(OUT / 'optical/manifest.json')
    batch = optical['batches'][0]
    audit = read(OUT / 'source-audit.json')['rows'][0]
    assert label['frameId'] == batch['frameId'] == audit['frameId'] == 1
    assert batch['layoutId'] == audit['layoutId'] == labels['layouts'][0]['layoutId']
    origin = np.array(batch['primaryOriginal']['cameraOriginM'])
    # Inside an unknown coarse cell, away from boundaries, fixed after diagnosis.
    point = np.array([-.375, .275, 1.685])
    assert -.45 < point[0] < .45 and .2 < point[1] < 3.5 and .05 < point[2] < 1.8
    direction = point - origin
    hits = [{'object': box['name'], 'rayParameter': t}
            for box in label['geometry']
            if (t := ray_box(origin, direction, box['lowerM'], box['upperM'])) is not None]
    channels = []
    for p in batch['channels']:
        camera = np.array(p['cameraToWalkingRotation']).reshape(3, 3).T @ direction
        if camera[2] <= .01: continue
        u, v = p['fx'] * camera[0] / camera[2] + p['cx'], p['fy'] * camera[1] / camera[2] + p['cy']
        if not (0 <= u < p['width'] and 0 <= v < p['height']): continue
        i = int(v) * p['width'] + int(u)
        arrays = {k: np.frombuffer(gzip.decompress((OUT / 'optical' / p[k]['path']).read_bytes()), dtype='u1' if k == 'validity' else '<f4')
                  for k in ('validity', 'depth', 'firstZLower')}
        channels.append({'cameraId': p['cameraId'], 'pixel': [int(u), int(v)],
                         'validCentreReturn': bool(arrays['validity'][i]),
                         'finiteRange': bool(np.isfinite(arrays['depth'][i])),
                         'finiteFirstZLower': bool(np.isfinite(arrays['firstZLower'][i]))})
    boxes = {b['name']: b for b in label['geometry']}
    wall_top = boxes['room-left']['upperM'][2]
    ceiling_bottom = boxes['ceiling']['lowerM'][2]
    assert hits == [] and channels and all(not p['validCentreReturn'] for p in channels)
    assert ceiling_bottom > wall_top
    return {'schemaVersion': 1, 'scope': 'post-outcome analytic opaque-box ray witness; scoring only, never runtime clearance authority',
            'promotionAllowed': False, 'layoutId': batch['layoutId'], 'frameId': 1,
            'sourceSha256': sha(__file__), 'sourceAuditSha256': sha(OUT / 'source-audit.json'),
            'annotationsSha256': sha(OUT / 'corpus/annotations.json'),
            'opticalManifestSha256': sha(OUT / 'optical/manifest.json'),
            'probeInsideProtectedBodyM': point.tolist(), 'cameraOriginM': origin.tolist(),
            'firstReturnHits': hits, 'coveringChannelPixels': channels,
            'sideWallTopM': wall_top, 'ceilingLowerM': ceiling_bottom,
            'unclosedUpperBandM': ceiling_bottom - wall_top,
            'conclusion': 'A body-interior direction escapes the open band without an opaque first return; unknown must remain unknown.',
            'causalScope': 'direct witness for one missing direction; not a proof that every unknown cell has this cause'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--write', action='store_true')
    args = parser.parse_args(); value = build(); target = OUT / 'visibility-audit.json'
    if args.write:
        assert not target.exists(), 'Immutable diagnostic'
        target.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    else:
        assert read(target) == value
    print(json.dumps(value, indent=2))

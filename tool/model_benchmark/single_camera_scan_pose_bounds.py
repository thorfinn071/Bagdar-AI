"""Optimistic label-free bounds for choosing/reordering the fixed twelve poses.

Sampled geometric witnesses impose necessary conditions only. Occlusion, depth,
floor evidence, scene motion and physical camera dynamics are deliberately absent.
"""
import hashlib
import itertools
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/single-camera-fresh-scan-2026-10-11'
MANIFEST = ROOT / 'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1/manifest.json'


def paths(distance):
    """Exact subset DP, free starting pose; minimize sum and largest step."""
    n = len(distance)
    total = np.full((1 << n, n), np.inf)
    peak = np.full_like(total, np.inf)
    for i in range(n):
        total[1 << i, i] = peak[1 << i, i] = 0
    for mask in range(1, 1 << n):
        for end in range(n):
            if not mask & (1 << end):
                continue
            previous = mask ^ (1 << end)
            if not previous:
                continue
            for start in range(n):
                if previous & (1 << start):
                    step = distance[start, end]
                    total[mask, end] = min(total[mask, end], total[previous, start] + step)
                    peak[mask, end] = min(peak[mask, end], max(peak[previous, start], step))
    return total.min(axis=1), peak.min(axis=1)


def self_check():
    random = np.random.default_rng(20261011)
    for n in range(2, 7):
        positions = random.normal(size=(n, 3))
        distances = np.linalg.norm(positions[:, None] - positions[None, :], axis=2)
        sums, peaks = paths(distances)
        for mask in range(1, 1 << n):
            selected = [i for i in range(n) if mask & (1 << i)]
            lengths = [
                [distances[a, b] for a, b in zip(order, order[1:])]
                for order in itertools.permutations(selected)
            ]
            assert math.isclose(sums[mask], min(sum(x) for x in lengths), abs_tol=1e-9)
            assert math.isclose(peaks[mask], min(max(x, default=0) for x in lengths), abs_tol=1e-9)


def main():
    self_check()
    manifest_bytes = MANIFEST.read_bytes()
    witness = np.array(list(itertools.product(
        [-.45, 0, .45], [.2, .35, .5, 1, 2, 3.5], [0, .05, .5125, .975, 1.4375, 1.9]
    )))
    all_witnesses = (1 << len(witness)) - 1
    results = []
    for layout in json.loads(manifest_bytes)['layouts']:
        packets = [f['axisPacket'] for f in layout['frames']]
        rotations = [np.array(p['cameraToWalkingRotation']).reshape(3, 3) for p in packets]
        visible = []
        for p, rotation in zip(packets, rotations):
            camera = (witness - p['cameraOriginM']) @ rotation
            z = camera[:, 2]
            with np.errstate(divide='ignore', invalid='ignore'):
                u = p['fx'] * camera[:, 0] / z + p['cx']
                v = p['fy'] * camera[:, 1] / z + p['cy']
            inside = (z > .01) & (u >= 0) & (u < p['width']) & (v >= 0) & (v < p['height'])
            visible.append(sum(1 << i for i, flag in enumerate(inside) if flag))
        union = [0] * (1 << len(packets))
        for mask in range(1, len(union)):
            bit = mask & -mask
            union[mask] = union[mask ^ bit] | visible[bit.bit_length() - 1]
        feasible = [mask for mask in range(1, len(union)) if union[mask] == all_witnesses]
        assert feasible
        distance = np.array([
            [math.degrees(math.acos(np.clip((np.trace(a.T @ b) - 1) / 2, -1, 1))) for b in rotations]
            for a in rotations
        ])
        np.fill_diagonal(distance, 0)
        total, peak = paths(distance)
        results.append({
            'sceneId': layout['sceneId'],
            'witnesses': len(witness),
            'minimumPosesToCoverWitnesses': min(mask.bit_count() for mask in feasible),
            'minimumTotalRotationDegrees': min(total[mask] for mask in feasible),
            'minimumLargestRotationStepDegrees': min(peak[mask] for mask in feasible),
            'bestFull12TotalRotationDegrees': total[-1],
            'bestFull12LargestRotationStepDegrees': peak[-1],
            'canCertifyFreeSpace': False,
            'canAuthorizeMovement': False,
        })
    output = {
        'scope': 'necessary sampled visibility bounds within the fixed 12-pose set; not complete coverage or phone capability',
        'algorithm': 'exact subset dynamic programming, free start; sum and bottleneck minima may use different paths',
        'selfCheck': 'all subsets versus exhaustive permutations for n=2..6',
        'sourceSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'manifestSha256': hashlib.sha256(manifest_bytes).hexdigest(),
        'promotionAllowed': False, 'rows': results,
    }
    (OUT / 'pose-bounds.json').write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()

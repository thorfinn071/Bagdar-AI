"""Label-free optical view grid covering requested angular extents.

Selection uses only camera intrinsics, its optical height and requested volume.
It proposes views, never certifies free space: the camera producer does that.
"""
import math


def choose_views(fx, fy, width, height, origin_height, body_width=.9,
                 headroom=1.85, floor_rise=.05, forward_start=.2,
                 forward_end=3.5, margin_deg=5):
    hfov = math.degrees(math.atan(width / (2 * fx)))
    vfov = math.degrees(math.atan(height / (2 * fy)))
    if min(hfov, vfov) <= margin_deg or forward_start <= 0:
        raise ValueError('Unsupported optical coverage request')
    directions = [(math.degrees(math.atan2(x, y)),
                   math.degrees(math.atan2(z-origin_height, math.hypot(x, y))))
                  for x in (-body_width/2, 0., body_width/2)
                  for y in (forward_start, forward_end)
                  for z in (0., .05, headroom+floor_rise)]

    def centres(values, half):
        low = math.floor(min(values)+half-margin_deg)
        high = math.ceil(max(values)-half+margin_deg)
        if low >= high:
            return [(min(values)+max(values))/2]
        gaps = math.ceil((high-low)/(2*(half-margin_deg)))
        return [low+(high-low)*i/gaps for i in range(gaps+1)]

    yaws = centres([p[0] for p in directions], hfov)
    pitches = centres([p[1] for p in directions], vfov)
    if len(yaws)*len(pitches) > 12:
        raise ValueError('Required coverage exceeds the existing scan budget')
    return {'horizontalHalfFovDeg': hfov, 'verticalHalfFovDeg': vfov,
            'marginDeg': margin_deg, 'yawDeg': yaws, 'pitchDeg': pitches,
            'poses': [(yaw, pitch) for pitch in pitches for yaw in yaws]}

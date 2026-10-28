"""Validate versioned procedural controls without importing Blender."""
import math
import re


def validate_spec(s):
    def number(v, low, high):
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or not low <= v <= high:
            raise ValueError(f'Invalid experiment control: {v}')
    if s['schemaVersion'] != 1 or s.get('promotionAllowed', False) is not False:
        raise ValueError('Research-only v1 specification required')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,120}', s['corpusId']): raise ValueError('Invalid corpus ID')
    for key in ('width', 'height'):
        number(s[key], 32, 1280)
        if not isinstance(s[key], int) or s[key] % 2: raise ValueError('Even integer dimensions required')
    number(s['frames'], 2, 601); number(s['fps'], 1, 60); number(s['sensorHz'], 1, 120)
    if any(not isinstance(s[k], int) for k in ('frames', 'fps', 'sensorHz')): raise ValueError('Integer cadence required')
    if (s['frames']-1)/s['fps'] > 120: raise ValueError('Sequence exceeds runtime duration')
    number(s['severity'], .25, 3)
    for field, bounds in {'heightM': (.5, 2.1), 'pitchDownDeg': (0, 75), 'lensMm': (6, 80),
                          'sensorWidthMm': (10, 50), 'walkingSpeedMps': (0, 1.5)}.items():
        number(s['camera'][field], *bounds)
    number(s['referenceBody']['widthM'], .4, 1.5); number(s['referenceBody']['heightM'], 1, 2.4)
    for field, allowed in [('layouts', {'hallway', 'courtyard', 'shop', 'sidewalk', 'underpass', 'pedestrian'}),
                           ('conditions', {'clean', 'shake', 'lowlight', 'defocus', 'rain', 'mixed'})]:
        values = s[field]
        if not values or len(set(values)) != len(values) or not set(values) <= allowed:
            raise ValueError(f'Invalid {field}')
    number(s.get('geometry', {}).get('crossTrackScale', 1), .7, 1.4)
    for field, default, bounds in [('textureScale', 14, (1, 80)), ('bumpStrength', .12, (0, 1)),
                                    ('roughnessMultiplier', 1, (.2, 2))]:
        number(s.get('materials', {}).get(field, default), *bounds)
    return s

"""Differential ABI tests: scalar/SIMD winners and every written score bit."""
import argparse
import ctypes as C
import math
import random
import unittest
from pathlib import Path


class MotionFrame(C.Structure):
    _fields_ = [('width', C.c_int), ('height', C.c_int),
                ('fx', C.c_double), ('fy', C.c_double), ('error', C.c_double)] + [
        (name, C.POINTER(C.c_double)) for name in
        ('pixels', 'range', 'lower', 'upper', 'nx', 'ny', 'x2', 'y2', 'axis')
    ] + [('valid', C.POINTER(C.c_ubyte)), ('status', C.POINTER(C.c_ubyte))]


def library(path):
    dll = C.CDLL(str(Path(path).resolve()))
    dll.fast_motion_abi.restype = C.c_int
    if dll.fast_motion_abi() != 1:
        raise ValueError('Unexpected matcher ABI')
    dll.fast_motion_match.restype = C.c_int
    dll.fast_motion_match.argtypes = [C.POINTER(MotionFrame),
                                     C.POINTER(C.c_double), C.POINTER(C.c_double),
                                     C.c_double, C.c_int, C.c_int,
                                     C.POINTER(C.c_double), C.POINTER(C.c_int),
                                     C.POINTER(C.c_int)]
    return dll


def run(dll, case):
    w, h = case['width'], case['height']
    n = w * h
    # Eight-byte offset exercises vector loads without 16-byte alignment.
    pixel_store = (C.c_double * (3 * n + 2))(-9876, *case['pixels'], 9876)
    pixels = C.cast(C.byref(pixel_store, 8), C.POINTER(C.c_double))
    planes = [(C.c_double * len(case[key]))(*case[key]) for key in
              ('range', 'lower', 'upper', 'nx', 'ny', 'x2', 'y2')]
    axis = (C.c_double * n)(*([-12345] * n))
    valid = (C.c_ubyte * n)(*case['valid'])
    status = (C.c_ubyte * n)()
    frame = MotionFrame(w, h, case['fx'], case['fy'], case['error'],
                        pixels, *planes, axis, valid, status)
    template = (C.c_double * 75)(*case['template'])
    basis = (C.c_double * 6)(*case['basis'])
    scores = (C.c_double * 4225)(*([-111] * 4225))
    sx = (C.c_int * 4225)(*([-222] * 4225))
    sy = (C.c_int * 4225)(*([-333] * 4225))
    immutable = [pixel_store, *planes, valid, template, basis]
    before = [bytes(a) for a in immutable]
    result = dll.fast_motion_match(C.byref(frame), template, basis,
                                   case['za'], *case['center'], scores, sx, sy)
    if [bytes(a) for a in immutable] != before:
        raise AssertionError('Matcher mutated immutable input storage')
    return result, bytes(scores), bytes(sx), bytes(sy), bytes(axis), bytes(status)


def case(seed, mode='random'):
    rng = random.Random(seed)
    w, h = rng.randrange(15, 28), rng.randrange(15, 28)
    fx, fy = 40.0, 43.0
    cx, cy = (w - 1) / 2, (h - 1) / 2
    nx = [(x - cx) / fx for x in range(w)]
    ny = [(y - cy) / fy for y in range(h)]
    pixels = []
    for y in range(h):
        for x in range(w):
            if mode == 'ambiguous':
                values = [.2, .4, .6]
            elif mode == 'third-channel':
                values = [0., 0., rng.random()]
            elif mode == 'gradient':
                values = [x / w, y / h, (x + y) / (w + h)]
            else:
                values = [rng.random() for _ in range(3)]
            pixels.extend(values)
    center = (w // 2, h // 2)
    template = []
    for dy in range(-4, 5, 2):
        for dx in range(-4, 5, 2):
            k = ((center[1] + dy) * w + center[0] + dx) * 3
            template.extend(pixels[k:k + 3])
    z = 2.0
    return dict(width=w, height=h, fx=fx, fy=fy, error=0., pixels=pixels,
                range=[z * math.sqrt(1 + nx[x]**2 + ny[y]**2)
                       for y in range(h) for x in range(w)],
                lower=[1.98] * (w * h), upper=[2.02] * (w * h),
                nx=nx, ny=ny, x2=[v*v for v in nx], y2=[v*v for v in ny],
                valid=[1] * (w * h), template=template,
                basis=[z/fx, 0., 0., 0., z/fy, 0.], za=z, center=center)


class ParityTests(unittest.TestCase):
    def compare(self, value):
        expected, actual = run(CONTROL, value), run(SIMD, value)
        self.assertEqual(expected, actual)
        return actual[0]

    def test_unaligned_channels_and_ambiguity(self):
        for mode in ('random', 'third-channel', 'gradient', 'ambiguous'):
            for seed in range(8):
                with self.subTest(mode=mode, seed=seed):
                    result = self.compare(case(seed, mode))
                    if mode == 'ambiguous':
                        self.assertEqual(result, -1)
                    elif mode in ('random', 'third-channel'):
                        self.assertGreaterEqual(result, 0)

    def test_fractional_projective_sampling_and_edges(self):
        for seed in range(32):
            value = case(seed)
            rng = random.Random(seed + 100)
            value['basis'] = [rng.uniform(.045, .06), rng.uniform(-.01, .01),
                              rng.uniform(-.03, .03), rng.uniform(-.01, .01),
                              rng.uniform(.04, .06), rng.uniform(-.03, .03)]
            if seed % 2:
                value['center'] = [(0, 0), (value['width'] - 1, 0),
                                   (0, value['height'] - 1),
                                   (value['width'] - 1, value['height'] - 1)][seed % 4]
            with self.subTest(seed=seed):
                self.compare(value)

    def test_score_thresholds_and_ties(self):
        for delta in (0., .015, .065, math.nextafter(.065, 0),
                      math.nextafter(.065, 1), .066):
            for mode in ('random', 'ambiguous'):
                value = case(43, mode)
                value['template'] = [v + delta for v in value['template']]
                with self.subTest(delta=delta, mode=mode):
                    self.compare(value)

    def test_invalid_depth_and_geometry(self):
        for field, bad in [('range', math.nan), ('range', math.inf),
                           ('lower', -1.), ('upper', .1), ('upper', math.inf)]:
            value = case(61)
            value[field] = [bad] * (value['width'] * value['height'])
            with self.subTest(field=field, bad=bad):
                self.assertEqual(self.compare(value), -1)
        value = case(62)
        value['valid'] = [0] * len(value['valid'])
        self.assertEqual(self.compare(value), -1)
        for basis in ([0.] * 6, [math.nan] * 6, [math.inf] * 6):
            value = case(63)
            value['basis'] = basis
            self.assertEqual(self.compare(value), -1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('control_library')
    parser.add_argument('simd_library')
    args = parser.parse_args()
    CONTROL, SIMD = library(args.control_library), library(args.simd_library)
    unittest.main(argv=[__file__], verbosity=2)

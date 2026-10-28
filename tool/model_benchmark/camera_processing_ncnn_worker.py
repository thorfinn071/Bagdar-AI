"""Live pinned CPU inference for elapsed replay; no labels/geometry input."""
import gzip
import json
import sys
import time
from pathlib import Path

import ncnn
import numpy as np
from PIL import Image
from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names, sha256_file

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'test/fixtures/spatial_safety/camera-scale-motion-v1'


def run():
    manifest = json.loads((CORPUS / 'manifest.json').read_text(encoding='utf-8'))
    pinned = json.loads((CORPUS / 'ncnn/manifest.json').read_text(encoding='utf-8'))
    if sha256_file(PARAM) != pinned['modelParamSha256'] or sha256_file(BIN) != pinned['modelBinSha256']:
        raise ValueError('Model identity mismatch')
    records = {(r['layoutId'], r['frameId']): r for r in pinned['frames']}
    images = {}
    load_start = time.perf_counter_ns()
    for layout in manifest['layouts']:
        for frame in layout['frames']:
            key = layout['id'], frame['frameId']
            path = (CORPUS / frame['rgb']['path']).resolve()
            if not path.is_relative_to(CORPUS) or sha256_file(path) != frame['rgb']['sha256']:
                raise ValueError('RGB identity mismatch')
            with Image.open(path) as image:
                pixels = np.asarray(image.convert('RGB'), dtype=np.uint8)
            rec = records[key]
            expected_pixels = gzip.decompress((CORPUS / 'ncnn' / rec['rgbPixels']['path']).read_bytes())
            if pixels.tobytes() != expected_pixels:
                raise ValueError('Decoded pixels mismatch')
            expected = gzip.decompress((CORPUS / 'ncnn' / rec['path']).read_bytes())
            height, width = pixels.shape[:2]
            images[key] = (pixels, np.arange(256) * height // 256,
                           np.arange(256) * width // 256, expected)
    load_ms = (time.perf_counter_ns() - load_start) / 1e6
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):
        raise RuntimeError('Pinned model load failed')
    inp, out = ncnn_blob_names(PARAM)
    pixels, ys, xs, _ = next(iter(images.values()))
    warm = (pixels.astype(np.float32) / 255)[ys[:, None], xs[None, :]]
    for _ in range(10):
        infer(net, inp, out, warm)
    print(json.dumps({'ready': True, 'warmupInferences': 10, 'fixtureLoadMs': load_ms,
                      'numThreads': 1, 'runtime': pinned['runtime']}), flush=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            key = request['layoutId'], request['frameId']
            pixels, ys, xs, expected = images[key]
            start = time.perf_counter_ns()
            rgb = (pixels.astype(np.float32) / 255)[ys[:, None], xs[None, :]]
            prepared = time.perf_counter_ns()
            raw = infer(net, inp, out, rgb)
            finished = time.perf_counter_ns()
            # Validation happens after inference and is part of IPC elapsed
            # overhead, never a source of metres, motion or planner decisions.
            if raw.astype('<f4').tobytes() != expected:
                raise ValueError('Live NCNN output drift')
            print(json.dumps({'ok': True, 'layoutId': key[0], 'frameId': key[1],
                              'preprocessingMs': (prepared - start) / 1e6,
                              'inferenceMs': (finished - prepared) / 1e6,
                              'outputMatchesPinned': True}), flush=True)
        except Exception as exc:
            print(json.dumps({'ok': False, 'error': str(exc)}), flush=True)


if __name__ == '__main__':
    run()

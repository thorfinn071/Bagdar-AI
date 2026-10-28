"""Continuous pinned CPU MiDaS competition, independent of scan geometry.

Uses three unchanged RGB frames from the existing scale/motion corpus. Neural
outputs are checked byte-for-byte, never supplied as metric scan evidence.
"""
import gzip
import json
import sys
import threading
import time
from pathlib import Path

import ncnn
import numpy as np
from PIL import Image

from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names, sha256_file

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'test/fixtures/spatial_safety/camera-scale-motion-v1'


def run():
    corpus = json.loads((CORPUS / 'manifest.json').read_text(encoding='utf-8'))
    pinned = json.loads((CORPUS / 'ncnn/manifest.json').read_text(encoding='utf-8'))
    if sha256_file(PARAM) != pinned['modelParamSha256'] or sha256_file(BIN) != pinned['modelBinSha256']:
        raise ValueError('Model identity mismatch')
    records = {(r['layoutId'], r['frameId']): r for r in pinned['frames']}
    layout = corpus['layouts'][0]
    images = []
    for frame in layout['frames'][:3]:
        path = (CORPUS / frame['rgb']['path']).resolve()
        if not path.is_relative_to(CORPUS) or sha256_file(path) != frame['rgb']['sha256']:
            raise ValueError('RGB path/hash mismatch')
        record = records[layout['id'], frame['frameId']]
        with Image.open(path) as image:
            pixels = np.asarray(image.convert('RGB'), dtype=np.uint8)
        def asset(key):
            descriptor = record[key] if key else record
            target = (CORPUS / 'ncnn' / descriptor['path']).resolve()
            if not target.is_relative_to(CORPUS / 'ncnn') or sha256_file(target) != descriptor['sha256']:
                raise ValueError('Pinned asset path/hash mismatch')
            return gzip.decompress(target.read_bytes())
        if pixels.tobytes() != asset('rgbPixels'):
            raise ValueError('Decoded RGB mismatch')
        height, width = pixels.shape[:2]
        images.append((pixels, np.arange(256) * height // 256,
                       np.arange(256) * width // 256, asset(None)))
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):
        raise RuntimeError('Model load failed')
    inp, out = ncnn_blob_names(PARAM)
    def measure(index):
        pixels, ys, xs, expected = images[index % len(images)]
        start = time.perf_counter_ns()
        rgb = (pixels.astype(np.float32) / 255)[ys[:, None], xs[None, :]]
        prepared = time.perf_counter_ns()
        raw = infer(net, inp, out, rgb)
        finish = time.perf_counter_ns()
        if raw.astype('<f4').tobytes() != expected:
            raise ValueError('Live neural output drift')
        return {'startUs': (start - origin) // 1000,
                'finishUs': (finish - origin) // 1000,
                'preprocessingUs': (prepared - start) // 1000,
                'inferenceUs': (finish - prepared) // 1000}
    origin = time.perf_counter_ns()
    for index in range(10):
        measure(index)
    print(json.dumps({'ready': True, 'warmupInferences': 10,
                      'runtime': pinned['runtime'], 'numThreads': 1,
                      'corpusSha256': sha256_file(CORPUS / 'manifest.json'),
                      'pinnedSha256': sha256_file(CORPUS / 'ncnn/manifest.json'),
                      'modelParamSha256': pinned['modelParamSha256'],
                      'modelBinSha256': pinned['modelBinSha256'],
                      'rgbFrames': [f['rgb'] for f in layout['frames'][:3]],
                      'geometryInput': False}), flush=True)
    if json.loads(sys.stdin.readline()).get('command') != 'start':
        raise ValueError('Expected start')
    stop = threading.Event()
    def control():
        for line in sys.stdin:
            if json.loads(line).get('command') == 'stop':
                stop.set()
                return
        stop.set()
    threading.Thread(target=control, daemon=True).start()
    origin = time.perf_counter_ns()
    print(json.dumps({'started': True}), flush=True)
    rows = []
    while not stop.is_set():
        rows.append(measure(len(rows)))
    if not rows:
        raise ValueError('No measured inference')
    print(json.dumps({'stopped': True, 'inferences': len(rows),
                      'allOutputsMatchPinned': True, 'rows': rows}), flush=True)


if __name__ == '__main__':
    run()

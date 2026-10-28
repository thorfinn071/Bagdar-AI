"""RGB-only pinned inference on the predeclared recovery holdout. No refitting."""
import argparse
import gzip
import json
import time
from pathlib import Path

import ncnn
import numpy as np
from PIL import Image
from generate_context_ncnn_depth import infer, ncnn_blob_names, PARAM, BIN
from generate_visible_passage_ncnn import sha, save, percentile

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-recovery-v1'
OUT = CORPUS / 'ncnn'
FROZEN = ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json'


def main(check):
    manifest = json.loads((CORPUS / 'manifest.json').read_text(encoding='utf-8'))
    frozen = json.loads(FROZEN.read_text(encoding='utf-8'))
    assert frozen['modelParamSha256'] == sha(PARAM) and frozen['modelBinSha256'] == sha(BIN)
    OUT.mkdir(exist_ok=True)
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):
        raise RuntimeError('Pinned model load failed')
    inp, out = ncnn_blob_names(PARAM)
    records, times = [], []
    first = manifest['layouts'][0]['frames'][0]
    with Image.open(CORPUS / first['rgb']['path']) as img:
        warm = np.asarray(img.convert('RGB'), dtype=np.float32) / 255
    ys = np.arange(256) * first['height'] // 256
    xs = np.arange(256) * first['width'] // 256
    for _ in range(10):
        infer(net, inp, out, warm[ys[:, None], xs[None, :]])
    for layout in manifest['layouts']:
        for f in layout['frames']:
            start = time.perf_counter_ns()
            path = (CORPUS / f['rgb']['path']).resolve()
            if not path.is_relative_to(CORPUS) or sha(path) != f['rgb']['sha256']:
                raise ValueError('RGB identity mismatch')
            with Image.open(path) as img:
                a = np.asarray(img.convert('RGB'), dtype=np.float32) / 255
            ys = np.arange(256) * f['height'] // 256
            xs = np.arange(256) * f['width'] // 256
            rgb = a[ys[:, None], xs[None, :]]
            prep = time.perf_counter_ns()
            raw = infer(net, inp, out, rgb)
            end = time.perf_counter_ns()
            name = f"{layout['id']}-clean-{f['frameId']}.f32.gz"
            if check:
                if gzip.decompress((OUT / name).read_bytes()) != raw.astype('<f4').tobytes():
                    raise ValueError('NCNN map drift: ' + name)
            else:
                (OUT / name).write_bytes(gzip.compress(raw.astype('<f4').tobytes(), mtime=0))
                times.append({'layoutId': layout['id'], 'frameId': f['frameId'], 'variant': 'clean',
                              'preprocessingMs': (prep-start)/1e6, 'inferenceMs': (end-prep)/1e6})
            records.append({'layoutId': layout['id'], 'frameId': f['frameId'], 'variant': 'clean',
                            'rgbSha256': f['rgb']['sha256'], 'path': name, 'sha256': sha(OUT/name)})
        print('NCNN ' + layout['id'], flush=True)
    receipt = {'schemaVersion': 1, 'corpusManifestSha256': sha(CORPUS/'manifest.json'),
               'generatorSha256': sha(__file__), 'modelParamSha256': sha(PARAM), 'modelBinSha256': sha(BIN),
               'runtime': frozen['runtime'], 'preprocessId': frozen['preprocessId'],
               'valueSemantics': frozen['valueSemantics'], 'calibration': frozen['calibration'],
               'frozenCalibrationSourceSha256': sha(FROZEN), 'newScenesUsedForFit': False,
               'frames': records, 'promotionAllowed': False}
    if check:
        if json.loads((OUT/'manifest.json').read_text(encoding='utf-8')) != receipt:
            raise ValueError('Recovery inference receipt drift')
        print('Recovery maps and original frozen calibration match')
    else:
        save(OUT/'manifest.json', receipt)
        save(ROOT/'docs/_baseline_logs/passage_recovery_ncnn_timing.json', {
            'scope': 'measured desktop CPU; no calibration refit; excludes render and scan',
            'warmupInferences': 10,
            'preprocessingP50Ms': percentile([r['preprocessingMs'] for r in times], 50),
            'preprocessingP95Ms': percentile([r['preprocessingMs'] for r in times], 95),
            'inferenceP50Ms': percentile([r['inferenceMs'] for r in times], 50),
            'inferenceP95Ms': percentile([r['inferenceMs'] for r in times], 95), 'frames': times})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    main(parser.parse_args().check)

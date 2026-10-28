"""Pinned NCNN inference on the preregistered holdout RGB; never fits calibration."""
import argparse
import gzip
import json
from pathlib import Path
import ncnn
import numpy as np
from PIL import Image
from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names
from generate_visible_passage_ncnn import sha, save

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT/'scratch/volume-holdout-2026-10-10/corpus'
OUT = CORPUS/'ncnn'
FROZEN = ROOT/'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json'


def main(check):
    manifest = json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    frozen = json.loads(FROZEN.read_text(encoding='utf-8'))
    assert frozen['modelParamSha256'] == sha(PARAM) and frozen['modelBinSha256'] == sha(BIN)
    if not check and (OUT/'manifest.json').exists():
        raise ValueError('Never overwrite completed inference')
    OUT.mkdir(exist_ok=True)
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 1
    assert net.load_param(str(PARAM)) == 0 and net.load_model(str(BIN)) == 0
    inp, out = ncnn_blob_names(PARAM)
    records = []
    for layout in manifest['layouts']:
        for f in layout['frames']:
            path = (CORPUS/f['rgb']['path']).resolve()
            assert path.is_relative_to(CORPUS) and sha(path) == f['rgb']['sha256']
            with Image.open(path) as image:
                pixels = np.asarray(image.convert('RGB'), dtype=np.uint8)
            pixel_name = f"{layout['id']}-rgb-{f['frameId']}.u8.gz"
            ys = np.arange(256)*f['height']//256
            xs = np.arange(256)*f['width']//256
            rgb = pixels.astype(np.float32)[ys[:,None],xs[None,:]]/255
            raw = infer(net, inp, out, rgb).astype('<f4').tobytes()
            name = f"{layout['id']}-clean-{f['frameId']}.f32.gz"
            for target, data in ((OUT/pixel_name, pixels.tobytes()), (OUT/name, raw)):
                if check:
                    assert gzip.decompress(target.read_bytes()) == data, f'Inference drift: {target}'
                else:
                    target.write_bytes(gzip.compress(data, mtime=0))
            records.append({'layoutId': layout['id'], 'frameId': f['frameId'], 'variant': 'clean',
                'rgbSha256': f['rgb']['sha256'], 'path': name, 'sha256': sha(OUT/name),
                'rgbPixels': {'path': pixel_name, 'sha256': sha(OUT/pixel_name)}})
        print('HOLDOUT_NCNN '+layout['id'], flush=True)
    receipt = {'schemaVersion': 1, 'corpusManifestSha256': sha(CORPUS/'manifest.json'),
        'generatorSha256': sha(__file__), 'modelParamSha256': sha(PARAM), 'modelBinSha256': sha(BIN),
        'runtime': frozen['runtime'], 'preprocessId': frozen['preprocessId'],
        'valueSemantics': frozen['valueSemantics'], 'calibration': frozen['calibration'],
        'frozenCalibrationSourceSha256': sha(FROZEN), 'newScenesUsedForFit': False,
        'inferenceHelperSha256': sha(ROOT/'tool/model_benchmark/generate_context_ncnn_depth.py'),
        'frames': records, 'promotionAllowed': False}
    if check:
        assert json.loads((OUT/'manifest.json').read_text(encoding='utf-8')) == receipt
    else:
        save(OUT/'manifest.json', receipt)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    main(parser.parse_args().check)

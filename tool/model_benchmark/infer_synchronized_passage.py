"""New primary-camera MiDaS outputs, with exact earlier pixel/output parity."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import ncnn
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_context_ncnn_depth import infer, nearest_rgb, ncnn_blob_names


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(directory):
    target = directory / 'neural.json'
    if target.exists():
        raise ValueError('Neural receipt is write-once')
    manifest = json.loads((directory/'manifest.json').read_text())
    prior_root = ROOT / 'scratch/camera-view-coverage-2026-10-09/optical'
    prior = json.loads((prior_root/'neural.json').read_text())
    prior_optics = json.loads((prior_root/'manifest.json').read_text())
    param, model = ROOT/'assets/midas_small.ncnn.param', ROOT/'assets/midas_small.ncnn.bin'
    assert sha(param) == prior['modelParamSha256'] and sha(model) == prior['modelBinSha256']
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 4
    assert net.load_param(str(param)) == 0 and net.load_model(str(model)) == 0
    names = ncnn_blob_names(param)
    frames = []
    for batch in manifest['batches']:
        p = batch['primary']
        rgb = (directory/p['rgb']['path']).resolve()
        assert rgb.is_relative_to(directory.resolve()) and sha(rgb) == p['rgb']['sha256']
        previous = next(x for x in prior_optics['packets'] if x['caseId']==batch['id'] and x['viewId']=='original')
        old_rgb = prior_root/previous['rgb']['path']
        assert sha(old_rgb) == previous['rgb']['sha256']
        pixels = np.asarray(Image.open(rgb).convert('RGB'))
        old_pixels = np.asarray(Image.open(old_rgb).convert('RGB'))
        assert np.array_equal(pixels, old_pixels), 'Primary pixels drift'
        pixel_hash = hashlib.sha256(pixels.tobytes()).hexdigest()
        raw = infer(net, *names, nearest_rgb(rgb))
        old = next(x for x in prior['frames'] if x['caseId']==batch['id'] and x['viewId']=='original')
        old_path = prior_root/old['asset']['path']
        assert sha(old_path) == old['asset']['sha256']
        pinned = np.frombuffer(gzip.decompress(old_path.read_bytes()), dtype='<f4').reshape(256,256)
        assert np.array_equal(raw, pinned), 'New neural output drift despite exact input'
        path = rgb.parent/'primary-midas-relative.f32.gz'
        if path.exists():
            raise ValueError('Preserve first neural output')
        path.write_bytes(gzip.compress(raw.tobytes(), mtime=0))
        frames.append({'id': batch['id'], 'rgbSha256': sha(rgb), 'canonicalRgbU8Sha256': pixel_hash,
                       'priorCanonicalRgbU8Sha256': hashlib.sha256(old_pixels.tobytes()).hexdigest(),
                       'rawOutputMatchesPrior': True,
                       'asset': {'path': path.relative_to(directory).as_posix(), 'sha256': sha(path)}})
        print('SYNC_NEURAL', batch['id'], flush=True)
    receipt = {'schemaVersion': 1, 'promotionAllowed': False, 'manifestSha256': sha(directory/'manifest.json'),
               'modelParamSha256': sha(param), 'modelBinSha256': sha(model),
               'preprocessId': 'rgb01-chw-256-nearest-stretch-no-crop-v1',
               'depthSemantics': 'relative inverse depth; never metres', 'frames': frames,
               'sources': {p.relative_to(ROOT).as_posix(): sha(p) for p in [Path(__file__),
                  ROOT/'tool/model_benchmark/generate_context_ncnn_depth.py', ROOT/'tools/ncnn/parity_test.py']}}
    target.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    args = parser.parse_args()
    directory = (ROOT/args.directory).resolve()
    if not directory.is_relative_to(ROOT/'scratch'):
        raise ValueError('Outputs must remain in scratch')
    run(directory)

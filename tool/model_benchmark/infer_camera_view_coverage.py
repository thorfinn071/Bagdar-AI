"""New RGB -> pinned desktop NCNN relative outputs; no metric conversion."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import ncnn

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_context_ncnn_depth import infer, nearest_rgb, ncnn_blob_names


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    target = directory / 'neural.json'
    if target.exists():
        raise ValueError('Neural receipt is write-once')
    param, model = ROOT / 'assets/midas_small.ncnn.param', ROOT / 'assets/midas_small.ncnn.bin'
    prior = json.loads((ROOT / 'docs/_baseline_logs/blender_paired_ncnn.json').read_text())
    assert sha(param) == prior['modelParamSha256'] and sha(model) == prior['modelBinSha256']
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 4
    assert net.load_param(str(param)) == 0 and net.load_model(str(model)) == 0
    input_name, output_name = ncnn_blob_names(param)
    records = []
    for packet in manifest['packets']:
        rgb = (directory / packet['rgb']['path']).resolve()
        assert rgb.is_relative_to(directory.resolve()) and sha(rgb) == packet['rgb']['sha256']
        raw = infer(net, input_name, output_name, nearest_rgb(rgb))
        path = rgb.parent / 'midas-relative.f32.gz'
        if path.exists():
            raise ValueError('Never overwrite neural output')
        path.write_bytes(gzip.compress(raw.tobytes(), mtime=0))
        records.append({'caseId': packet['caseId'], 'viewId': packet['viewId'],
                        'rgbSha256': sha(rgb), 'asset': {'path': path.relative_to(directory).as_posix(), 'sha256': sha(path)}})
        print(f"NEURAL_PACKET {packet['caseId']}/{packet['viewId']}", flush=True)
    result = {'schemaVersion': 1, 'modelParamSha256': sha(param), 'modelBinSha256': sha(model),
              'preprocessId': 'rgb01-chw-256-nearest-stretch-no-crop-v1',
              'semantics': 'relative inverse depth; never metres', 'promotionAllowed': False,
              'manifestSha256': sha(directory / 'manifest.json'), 'frames': records,
              'sources': {p.relative_to(ROOT).as_posix(): sha(p) for p in
                          [Path(__file__), ROOT / 'tool/model_benchmark/generate_context_ncnn_depth.py', ROOT / 'tools/ncnn/parity_test.py']}}
    target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    args = parser.parse_args()
    directory = (ROOT / args.directory).resolve()
    if not directory.is_relative_to(ROOT / 'scratch'):
        raise ValueError('Trial must remain in scratch')
    run(directory)

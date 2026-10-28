"""Preserve older freezes and pin the independent-callback experiment."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/camera_fast_motion_stream_contract_v1.json'
SOURCES = [
    'tool/model_benchmark/independent_replay_feed.dart',
    'tool/model_benchmark/replay_depth_load_lane.dart',
    'tool/model_benchmark/pinned_depth_load_worker.dart',
    'tool/model_benchmark/replay_fast_camera_motion_stream.dart',
    'tool/model_benchmark/evaluate_fast_camera_motion_stream.dart',
    'tool/model_benchmark/verify_fast_camera_motion_stream.py',
    'test/independent_replay_feed_test.dart',
    'lib/core/performance/perception_scheduler.dart',
    'lib/core/performance/perception_performance.dart',
    'tool/model_benchmark/camera_processing_ncnn_worker.py',
    'docs/camera-fast-motion-stream-protocol-2026-10-07.md',
]


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify(check):
    subprocess.run([sys.executable,
                    'tool/model_benchmark/verify_fast_camera_motion_packed.py',
                    '--check'], cwd=ROOT, check=True)
    # The load process protocol is unchanged; only the caller's admission and
    # scheduling differ. Preserve pinned RGB/preprocess/raw-output checks.
    old = (ROOT / 'tool/model_benchmark/replay_fast_camera_motion_packed.dart').read_text(encoding='utf-8')
    start = old.index('// The neural worker')
    end = old.index('Future<void> main(', start)
    expected = old[start:end].replace('_NeuralWorker', 'PinnedDepthLoadWorker')
    new = (ROOT / SOURCES[2]).read_text(encoding='utf-8')
    new = new[new.index('// The neural worker'):]
    if ''.join(expected.split()) != ''.join(new.split()):
        raise ValueError('Pinned NN load protocol changed beyond public class name')
    for path in SOURCES[:3]:
        text = (ROOT / path).read_text(encoding='utf-8')
        for forbidden in ('annotations.json', 'visibleObjectMask',
                          'expectedDecision', 'relativeModelHash'):
            if forbidden in text:
                raise ValueError('Feed/load helper reads hidden scoring inputs: ' + path)
    receipt = {
        'scope': 'versioned independent synthetic callback feed and real app depth-lane admission',
        'sourceSha256': {path: sha(path) for path in SOURCES},
        'previousPackedContractSha256': sha(
            'docs/_baseline_logs/camera_fast_motion_packed_contract_v1.json'),
        'previousLoadContractSha256': sha(
            'docs/_baseline_logs/camera_fast_motion_load_contract_v2.json'),
        'currentAgeLimitUs': 100000,
        'captureDeliveryWaitsForNeural': False,
        'depthLoadModels': ['midas-small-ncnn'],
        'depthQueueCapacity': 0,
        'promotionAllowed': False,
        'ordinaryCameraWired': False,
        'newIndependentHoldout': False,
        'captureToCommandMeasured': False,
        'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if OUT.read_text(encoding='utf-8') != rendered:
            raise ValueError('Independent stream source receipt drift')
    else:
        if OUT.exists():
            raise ValueError('Never overwrite the stream experiment receipt')
        OUT.write_text(rendered, encoding='utf-8')
    print('Stream integrity: previous receipts unchanged; same pinned MiDaS load protocol; shadow only')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

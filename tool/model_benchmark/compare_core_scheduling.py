"""Desktop real YOLOv8n TFLite + MiDaS NCNN scheduling diagnostic.

Two persistent processes isolate the runtimes/GIL, like separate native model
workers. Repeated static RGB trials isolate launch dependency from motion.
This does not execute Android YUV, Dart scheduler, geometry or feedback.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

from depth_candidate_common import ROOT, load_frames, percentile, save, sha

DEST = ROOT / 'scratch/phone-performance-stage4-2026-10-05'
YOLO = ROOT / 'assets/yolov8n_int8.tflite'
PARAM = ROOT / 'assets/midas_small.ncnn.param'
BIN = ROOT / 'assets/midas_small.ncnn.bin'


def worker(kind):
    if kind == 'yolo':
        os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
        os.environ['TF_NUM_INTEROP_THREADS'] = os.environ['TF_NUM_INTRAOP_THREADS'] = '1'
        import tensorflow as tf
        interpreter = tf.lite.Interpreter(model_path=str(YOLO), num_threads=1)
        interpreter.allocate_tensors()
        input_detail, output_detail = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
        assert list(input_detail['shape']) == [1, 416, 416, 3]
        assert list(output_detail['shape']) == [1, 84, 3549]
        assert input_detail['dtype'] == output_detail['dtype'] == np.float32
        version = importlib.metadata.version('tensorflow')

        def infer(path):
            with Image.open(path) as source:
                image = source.convert('RGB')
                scale = 416 / max(image.size)
                size = tuple(round(x * scale) for x in image.size)
                canvas = Image.new('RGB', (416, 416), (114, 114, 114))
                canvas.paste(image.resize(size, Image.Resampling.BILINEAR),
                             ((416-size[0])//2, (416-size[1])//2))
            tensor = np.asarray(canvas, dtype=np.float32)[None] / 255
            interpreter.set_tensor(input_detail['index'], tensor)
            interpreter.invoke()
            return interpreter.get_tensor(output_detail['index'])
    else:
        import ncnn
        net = ncnn.Net()
        net.opt.num_threads = 1
        net.opt.use_vulkan_compute = False
        net.opt.use_fp16_packed = net.opt.use_fp16_storage = net.opt.use_fp16_arithmetic = False
        assert net.load_param(str(PARAM)) == net.load_model(str(BIN)) == 0
        version = importlib.metadata.version('ncnn')
        # Production control graph names are checked against the pinned graph.
        lines = PARAM.read_text().splitlines()[2:]
        inputs = [x.split()[4] for x in lines if x.split()[0] == 'Input']
        consumed, produced = set(), []
        for line in lines:
            parts = line.split()
            bottoms, tops = int(parts[2]), int(parts[3])
            consumed.update(parts[4:4+bottoms])
            produced.extend(parts[4+bottoms:4+bottoms+tops])
        outputs = [x for x in produced if x not in consumed]
        assert len(inputs) == len(outputs) == 1

        def infer(path):
            with Image.open(path) as source:
                rgb = np.asarray(source.convert('RGB').resize((256, 256), Image.Resampling.NEAREST), dtype=np.float32) / 255
            chw = rgb.transpose(2, 0, 1).copy()
            mat = ncnn.Mat(256, 256, 3)
            for channel in range(3):
                np.copyto(np.array(mat.channel(channel), copy=False), chw[channel])
            extractor = net.create_extractor()
            assert extractor.input(inputs[0], mat) == 0
            code, result = extractor.extract(outputs[0])
            assert code == 0 and result.w == result.h == 256
            return np.array(result, copy=True).astype(np.float32)

    print(json.dumps({'ready': kind, 'runtime': version, 'numpy': np.__version__}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        if request.get('close'):
            break
        started = time.perf_counter_ns()
        result = infer(request['path'])
        elapsed_ms = (time.perf_counter_ns() - started) / 1e6
        assert np.isfinite(result).all()
        digest = hashlib.sha256(result.astype('<f4').tobytes()).hexdigest()
        print(json.dumps({'id': request['id'], 'computeMs': elapsed_ms,
                          'outputSha256': digest, 'outputShape': list(result.shape)}), flush=True)


class Worker:
    def __init__(self, kind, python):
        self.log = (DEST / f'{kind}-worker-stderr.log').open('w', encoding='utf-8')
        self.process = subprocess.Popen([str(python), str(Path(__file__)), '--worker', kind],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.log, text=True, bufsize=1)
        self.ready = self._read()
        assert self.ready['ready'] == kind
        self.sequence = 0

    def _read(self):
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError('model worker exited; inspect stderr log')
        return json.loads(line)

    def run(self, path, source_ns):
        self.sequence += 1
        started = time.perf_counter_ns()
        self.process.stdin.write(json.dumps({'id': self.sequence, 'path': str(path)}) + '\n')
        self.process.stdin.flush()
        result = self._read()
        ended = time.perf_counter_ns()
        assert result['id'] == self.sequence
        return {**result, 'sourceToReplyMs': (ended-source_ns)/1e6,
                'dispatchToReplyMs': (ended-started)/1e6,
                'dispatchAgeMs': (started-source_ns)/1e6}

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.write('{"close":true}\n')
            self.process.stdin.flush()
            self.process.wait(timeout=30)
        self.log.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--worker', choices=['yolo', 'depth'])
    parser.add_argument('--python-yolo', default=r'C:\Users\Nurik\AppData\Local\Programs\Python\Python311\python.exe')
    parser.add_argument('--python-depth', default=str(ROOT / 'tools/ncnn/.venv/Scripts/python.exe'))
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if args.worker:
        worker(args.worker)
        return
    if args.repeats < 3:
        raise ValueError('at least three counterbalanced repetitions required')
    corpus, frames = load_frames()
    DEST.mkdir(parents=True, exist_ok=True)
    controls = {str(p.relative_to(ROOT)).replace('\\', '/'): sha(p) for p in (YOLO, PARAM, BIN)}
    models, rows, hashes = {}, [], {}
    policies = ['legacy-yolo-then-depth', 'staggered-next-callback', 'controlled-parallel']
    try:
        for kind, python in [('yolo', args.python_yolo), ('depth', args.python_depth)]:
            models[kind] = Worker(kind, python)
            for _ in range(3):
                models[kind].run(frames[0]['paths']['rgb'], time.perf_counter_ns())
        with ThreadPoolExecutor(max_workers=2) as executor:
            for repeat in range(args.repeats):
                for index, frame in enumerate(frames):
                    shift = (repeat + index) % 3
                    order = policies[shift:] + policies[:shift]
                    for policy in order:
                        path = frame['paths']['rgb']
                        origin = time.perf_counter_ns()
                        if policy == policies[0]:
                            yolo = models['yolo'].run(path, origin)
                            depth = models['depth'].run(path, origin)
                        else:
                            yolo_future = executor.submit(models['yolo'].run, path, origin)
                            if policy == policies[1]:
                                # Simulated next callback at 30 FPS, same static RGB.
                                remaining = 1/30 - (time.perf_counter_ns()-origin)/1e9
                                if remaining > 0:
                                    time.sleep(remaining)
                                depth_source = time.perf_counter_ns()
                            else:
                                depth_source = origin
                            depth_future = executor.submit(models['depth'].run, path, depth_source)
                            yolo, depth = yolo_future.result(timeout=10), depth_future.result(timeout=10)
                        for kind, result in [('yolo', yolo), ('depth', depth)]:
                            key = (frame['sceneId'], frame['frameIndex'], kind)
                            hashes.setdefault(key, result['outputSha256'])
                            assert hashes[key] == result['outputSha256'], ('output drift', key, policy)
                        rows.append({'repeat': repeat, 'policy': policy, 'sceneId': frame['sceneId'],
                                     'frameIndex': frame['frameIndex'], 'rgbSha256': frame['rgb']['sha256'],
                                     'yolo': yolo, 'depth': depth})
                print(f'Completed scheduling repetition {repeat+1}/{args.repeats}', flush=True)
        summary = []
        for policy in policies:
            trials = [r for r in rows if r['policy'] == policy]
            result = {'policy': policy, 'trials': len(trials), 'modelErrors': 0,
                      'outputIdenticalAcrossSchedules': True}
            for kind in ('yolo', 'depth'):
                for metric in ('sourceToReplyMs', 'dispatchToReplyMs', 'dispatchAgeMs'):
                    values = [r[kind][metric] for r in trials]
                    result[f'{kind}_{metric}_p50'] = percentile(values, 0.5)
                    result[f'{kind}_{metric}_p95'] = percentile(values, 0.95)
                result[f'{kind}_overTwoSeconds'] = sum(r[kind]['sourceToReplyMs'] > 2000 for r in trials)
            summary.append(result)
        report = {'schemaVersion': 1, 'modelControls': controls,
                  'corpusId': corpus['corpusId'], 'repetitions': args.repeats,
                  'scriptSha256': sha(Path(__file__)), 'workers': {k: w.ready for k, w in models.items()},
                  'scope': 'desktop CPU real inference, static RGB trials; launch scheduling diagnostic only',
                  'excludes': ['Android camera/YUV/crop', 'production Dart scheduler', 'geometry', 'alerts', 'device thermals'],
                  'staggeredClock': 'new simulated callback after 33 ms; RGB repeats in each trial',
                  'phonePerformanceValidated': False, 'promotionAllowed': False,
                  'summary': summary, 'trials': rows}
        save(DEST / 'real-model-scheduling-report.json', report)
        for row in summary:
            print(json.dumps(row), flush=True)
    finally:
        for model in models.values():
            model.close()


if __name__ == '__main__':
    main()

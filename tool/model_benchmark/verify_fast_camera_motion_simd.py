"""Write-once receipt for strict two-channel arithmetic only."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/camera_fast_motion_simd_contract_v1.json'
SOURCES = [
    'tool/model_benchmark/native/fast_motion_match_simd.c',
    'tool/model_benchmark/build_fast_motion_simd.ps1',
    'tool/model_benchmark/check_fast_motion_simd_parity.py',
    'tool/model_benchmark/evaluate_fast_camera_motion_simd.dart',
    'tool/model_benchmark/verify_fast_camera_motion_simd.py',
    'docs/camera-fast-motion-simd-protocol-2026-10-07.md',
]


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def canonical(text):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    return ''.join(text.split())


def verify(check):
    subprocess.run([sys.executable,
                    'tool/model_benchmark/verify_fast_camera_motion_stream.py',
                    '--check'], cwd=ROOT, check=True)
    old = (ROOT / 'tool/model_benchmark/native/fast_motion_match.c').read_text(encoding='utf-8')
    expected = old.replace('typedef unsigned char u8;', '''typedef unsigned char u8;
        typedef double ColourPair __attribute__((vector_size(16), aligned(1), may_alias));''')
    begin = expected.index('          for (int c = 0; c < 3; c++) {')
    end = expected.index('          if (error > limit)', begin)
    expected = expected[:begin] + '''
          ColourPair sample01 =
              *(const ColourPair *)(f->pixels + i00) * left * up +
              *(const ColourPair *)(f->pixels + i10) * du * up +
              *(const ColourPair *)(f->pixels + i01) * left * dv +
              *(const ColourPair *)(f->pixels + i11) * du * dv;
          double sample2 = f->pixels[i00+2] * left * up +
                           f->pixels[i10+2] * du * up +
                           f->pixels[i01+2] * left * dv +
                           f->pixels[i11+2] * du * dv;
          error += __builtin_fabs(template75[k++] - sample01[0]);
          error += __builtin_fabs(template75[k++] - sample01[1]);
          error += __builtin_fabs(template75[k++] - sample2);
    ''' + expected[end:]
    actual = (ROOT / SOURCES[0]).read_text(encoding='utf-8')
    if canonical(expected) != canonical(actual):
        raise ValueError('Native source changed beyond strict channel vectorization')
    old_build = (ROOT / 'tool/model_benchmark/build_fast_motion_native.ps1').read_text(encoding='utf-8')
    expected_build = old_build.replace('scratch/fast-motion-native', 'scratch/fast-motion-simd')
    expected_build = expected_build.replace('fast_motion_match.', 'fast_motion_match_simd.')
    expected_build = expected_build.replace('Native experimental matcher:', 'Native strict SIMD2 matcher:')
    if canonical(expected_build) != canonical((ROOT / SOURCES[1]).read_text(encoding='utf-8')):
        raise ValueError('SIMD compiler flags or linking contract changed')
    receipt = {
        'scope': 'Windows x64 strict SIMD2 channel evaluation; known synthetic shadow regression',
        'sourceSha256': {path: sha(path) for path in SOURCES},
        'previousStreamContractSha256': sha(
            'docs/_baseline_logs/camera_fast_motion_stream_contract_v1.json'),
        'originalNativeSourceSha256': sha('tool/model_benchmark/native/fast_motion_match.c'),
        'abi': 1,
        'currentAgeLimitUs': 100000,
        'fastMath': False,
        'floatingPointContraction': False,
        'decisionThresholdsUnchanged': True,
        'promotionAllowed': False,
        'ordinaryCameraWired': False,
        'newIndependentHoldout': False,
        'captureToCommandMeasured': False,
        'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if OUT.read_text(encoding='utf-8') != rendered:
            raise ValueError('Strict SIMD source receipt drift')
    else:
        if OUT.exists():
            raise ValueError('Never overwrite the SIMD experiment receipt')
        OUT.write_text(rendered, encoding='utf-8')
    print('SIMD integrity: earlier receipts unchanged; strict channel sampling only; shadow only')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

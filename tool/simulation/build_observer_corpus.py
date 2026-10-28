"""Fresh v1 observer experiment. Labels stay outside every pixel-only API."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PROTOCOL = Path(__file__).with_name('quality_observer_protocol_v1.json')
SOURCE = Path(__file__).resolve().parents[2]/'lib/research/image_quality_observer.dart'
DEV = {'sparse-polylines', 'disks', 'staggered-blocks', 'random-crosses'}
HOLDOUT = {'sparse-arcs', 'triangles', 'zigzag-ribbons', 'scattered-rectangles'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def validate(protocol):
    if protocol['schemaVersion'] != 1 or protocol['promotionAllowed'] is not False:
        raise ValueError('Research-only v1 protocol required')
    seen_families, seen_seeds = set(), set()
    for name, split in protocol['splits'].items():
        families, seeds = set(split['families']), set(split['seeds'])
        if not families or not seeds or families & seen_families or seeds & seen_seeds:
            raise ValueError('Empty or overlapping split')
        if not families <= (DEV if name == 'development' else HOLDOUT):
            raise ValueError('Unknown or previously used family')
        seen_families |= families
        seen_seeds |= seeds
    if set(protocol['splits']) != {'development', 'holdout'}:
        raise ValueError('Both independent splits are required')
    ids = [c['id'] for c in protocol['conditions']]
    if len(set(ids)) != len(ids) or 'sharp' not in ids:
        raise ValueError('Unique paired conditions required')
    for width, height in protocol['sizes']:
        if not 32 <= width <= 1280 or not 32 <= height <= 1280:
            raise ValueError('Invalid dimensions')
    for c in protocol['conditions']:
        if c['noise'] not in ('none', 'white', 'correlated', 'shot'):
            raise ValueError('Unknown noise model')
        if not 0 <= c['blur'] <= 12 or c['motion'] not in range(1, 32, 2):
            raise ValueError('Invalid blur')
        if not 0 <= c['sigma'] <= 32 or not 0 < c['gain'] <= 1:
            raise ValueError('Invalid noise/gain')
        if c['noise'] == 'shot' and not 1 <= c['peak'] <= 256:
            raise ValueError('Invalid shot peak')


def chart(family, seed, width, height, contrast):
    rng = np.random.default_rng(seed)
    im = Image.new('L', (width, height), 128)
    d = ImageDraw.Draw(im)
    def point(): return (int(rng.integers(8, width-8)), int(rng.integers(8, height-8)))
    if family == 'sparse-polylines':
        d.line([point() for _ in range(4)], fill=40, width=2)
    elif family == 'sparse-arcs':
        d.arc((width//7, height//9, width*6//7, height*8//9), 27, 239, fill=40, width=2)
    elif family == 'disks':
        for _ in range(28):
            x, y = point(); r = int(rng.integers(3, 20))
            d.ellipse((x-r, y-r, x+r, y+r), fill=int(rng.integers(35, 220)))
    elif family == 'staggered-blocks':
        for y in range(7, height-20, 31):
            x = int(rng.integers(5, 30))
            for x in range(x, width-20, 37):
                d.rectangle((x, y, x+17, y+11), fill=int(rng.integers(35, 220)))
    elif family == 'random-crosses':
        for _ in range(40):
            x, y = point()
            d.line((x-6, y, x+6, y), fill=40, width=2)
            d.line((x, y-6, x, y+6), fill=195, width=2)
    elif family == 'triangles':
        for _ in range(22):
            x, y = point(); r = int(rng.integers(4, 20))
            d.polygon([(x, y-r), (x-r, y+r), (x+r, y+r)], fill=int(rng.integers(35, 220)))
    elif family == 'zigzag-ribbons':
        for y in range(15, height-15, 24):
            d.line([(x, y+int(rng.integers(-10, 11))) for x in range(0, width, 17)],
                   fill=int(rng.integers(35, 90)), width=3)
    elif family == 'scattered-rectangles':
        for _ in range(32):
            x, y = point()
            d.rectangle((x, y, x+int(rng.integers(5, 30)), y+int(rng.integers(5, 35))),
                        outline=int(rng.integers(35, 90)), width=2)
    else:
        raise ValueError('Unknown family')
    return Image.fromarray(np.rint(128+(np.asarray(im, dtype=float)-128)*contrast).clip(0, 255).astype('uint8'))


def transform(image, c, seed):
    v = np.asarray(image.filter(ImageFilter.GaussianBlur(c['blur'])), dtype=float)
    r = c['motion']//2
    if r:
        padded = np.pad(v, ((0, 0), (r, r)), mode='edge')
        v = np.mean([padded[:, i:i+image.width] for i in range(2*r+1)], axis=0)
    v *= c['gain']
    rng = np.random.default_rng(seed)
    if c['noise'] == 'white':
        v += rng.normal(0, c['sigma'], v.shape)
    elif c['noise'] == 'correlated':
        n = rng.normal(0, 1, v.shape)
        p = np.pad(n, 1, mode='reflect')
        n = sum(p[dy:dy+v.shape[0], dx:dx+v.shape[1]] for dy in range(3) for dx in range(3))/9
        v += n/max(float(n.std()), 1e-9)*c['sigma']
    elif c['noise'] == 'shot':
        v = rng.poisson(np.clip(v, 0, 255)/255*c['peak'])/c['peak']*255
    return np.rint(v).clip(0, 255).astype('uint8')


def build(root, protocol_path=PROTOCOL):
    raw = protocol_path.read_bytes(); protocol = json.loads(raw)
    validate(protocol)
    root.mkdir(parents=True, exist_ok=False)
    (root/'luma').mkdir()
    rows = []
    def save(identifier, values, **metadata):
        pixels = values.tobytes(); relative = f'luma/{identifier}.y8'
        (root/relative).write_bytes(pixels)
        rows.append({'id': identifier, 'width': values.shape[1], 'height': values.shape[0],
                     'rowStride': values.shape[1], 'asset': {'path': relative, 'sha256': sha(pixels)}, **metadata})
    for split, selection in protocol['splits'].items():
        for family in selection['families']:
            for seed in selection['seeds']:
                for w, h in protocol['sizes']:
                    for contrast in protocol['contrasts']:
                        base = f'{split}-{family}-{seed}-{w}x{h}-c{round(contrast*100)}'
                        image = chart(family, seed, w, h, contrast)
                        for c in protocol['conditions']:
                            save(f'{base}-{c["id"]}', transform(image, c, seed+100000),
                                 baseId=base, split=split, family=family, seed=seed,
                                 contrast=contrast, condition=c['id'], transform=c)
    for w, h in protocol['sizes']:
        y, x = np.mgrid[:h, :w]
        for cell in protocol['phaseCells']:
            base = f'phase-{w}x{h}-cell-{cell}'
            for px in protocol['phaseOffsets']:
                for py in protocol['phaseOffsets']:
                    v = np.where(((x+px)//cell+(y+py)//cell)%2, 205, 50).astype('uint8')
                    save(f'{base}-{px}-{py}', v, baseId=base, split='diagnostic',
                         family='phase-checker', condition='sharp', phaseX=px, phaseY=py)
        for noise in ('none', 'white', 'correlated', 'shot'):
            c = {'blur': 0, 'motion': 1, 'gain': 1, 'noise': noise, 'sigma': 8, 'peak': 64}
            save(f'flat-{w}x{h}-{noise}', transform(Image.new('L', (w, h), 128), c, 771831),
                 baseId=f'flat-{w}x{h}', split='diagnostic', family='flat', condition=noise, transform=c)
    manifest = {'schemaVersion': 1, 'experimentId': protocol['experimentId'],
                'promotionAllowed': False, 'scope': protocol['scope'],
                'protocolSha256': sha(raw), 'generatorSha256': sha(Path(__file__).read_bytes()),
                'candidateSourceSha256': sha(SOURCE.read_bytes()), 'images': rows}
    (root/'protocol.json').write_bytes(raw)
    (root/'candidate-frozen.dart.txt').write_bytes(SOURCE.read_bytes())
    (root/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(f'OBSERVER_CORPUS {len(rows)} images; candidate {manifest["candidateSourceSha256"]}')
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('output', type=Path)
    p.add_argument('--protocol', type=Path, default=PROTOCOL)
    a = p.parse_args(); build(a.output, a.protocol)

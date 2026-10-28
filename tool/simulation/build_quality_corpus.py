"""Independent, paired luma diagnostics; no geometry or usability truth is asserted."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PROTOCOL = Path(__file__).with_name('quality_protocol_v1.json')
FAMILIES = {'panel', 'tiles', 'shelves', 'bars', 'doorway', 'bricks', 'steps', 'foliage'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def validate_protocol(protocol):
    families, seeds = set(), set()
    for split in protocol['splits'].values():
        current_families, current_seeds = set(split['families']), set(split['seeds'])
        if current_families & families or current_seeds & seeds:
            raise ValueError('Development and holdout must have disjoint families and seeds')
        if not current_families <= FAMILIES:
            raise ValueError('Unknown chart family')
        families |= current_families
        seeds |= current_seeds
    ids = [row['id'] for row in protocol['conditions']]
    if len(set(ids)) != len(ids) or 'sharp' not in ids:
        raise ValueError('Unique conditions including sharp are required')
    for width, height in protocol['sizes']:
        if not 16 <= width <= 1280 or not 16 <= height <= 1280:
            raise ValueError('Invalid diagnostic image dimensions')
    for row in protocol['conditions']:
        if not 0 <= row['blurSigmaPx'] <= 20 or row['motionPx'] not in range(1, 32, 2):
            raise ValueError('Invalid blur kernel')
        if not 0 <= row['noiseSigmaLuma'] <= 64 or not 0 < row['gain'] <= 1:
            raise ValueError('Invalid exposure/noise condition')
    if protocol['promotionAllowed'] is not False:
        raise ValueError('Diagnostic corpus cannot allow promotion')


def make_chart(family, seed, width, height, contrast):
    rng = np.random.default_rng(seed)
    image = Image.new('L', (width, height), 128)
    d = ImageDraw.Draw(image)
    dx, dy = int(rng.integers(3, 13)), int(rng.integers(3, 13))
    if family == 'panel':
        d.rectangle((width//3+dx, height//4+dy, width*2//3+dx, height*3//4+dy), fill=155)
        d.line((0, height*4//5+dy, width, height*4//5+dy), fill=90, width=2)
    elif family == 'tiles':
        cell = int(rng.integers(19, 38))
        for y in range(dy, height, cell):
            for x in range(dx, width, cell):
                d.rectangle((x, y, x+cell-2, y+cell-2), fill=int(rng.integers(65, 200)))
    elif family == 'shelves':
        for y in range(dy+25, height, 60):
            d.rectangle((width//10, y, width*9//10, y+3), fill=45)
            for x in range(dx+width//8, width*7//8, 23):
                d.rectangle((x, y-35, x+int(rng.integers(9, 20)), y-2), fill=int(rng.integers(30, 225)))
    elif family == 'bars':
        for x in range(-height, width, 13):
            d.line((x+dx, 0, x+height//2+dx, height), fill=40, width=4)
    elif family == 'doorway':
        d.rectangle((width//4+dx, height//8+dy, width*3//4+dx, height*7//8), outline=50, width=4)
        d.rectangle((width//4+dx+8, height//8+dy+8, width*3//4+dx-8, height*7//8), fill=140)
        d.ellipse((width*2//3, height//2, width*2//3+4, height//2+4), fill=25)
    elif family == 'bricks':
        for row, y in enumerate(range(dy-24, height, 29)):
            for x in range(dx-60+(row%2)*30, width, 61):
                d.rectangle((x, y, x+57, y+25), fill=int(rng.integers(65, 180)))
    elif family == 'steps':
        for i in range(1, 11):
            y = int(height*(i/11)**1.4)
            d.rectangle((0, y+dy, width, y+dy+2), fill=35)
            d.line((width//2+dx, 0, int(width*(i%3)/2), height), fill=190, width=1)
    elif family == 'foliage':
        for _ in range(width*height//300):
            x, y = int(rng.integers(width)), int(rng.integers(height))
            r = int(rng.integers(2, 9))
            d.ellipse((x-r, y-r, x+r, y+r), fill=int(rng.integers(40, 210)))
    else:
        raise ValueError('Unknown chart family')
    values = np.asarray(image, dtype=np.float64)
    return Image.fromarray(np.rint(128+(values-128)*contrast).clip(0, 255).astype(np.uint8))


def transform(image, condition, seed):
    result = image.copy()
    if condition['blurSigmaPx']:
        result = result.filter(ImageFilter.GaussianBlur(condition['blurSigmaPx']))
    values = np.asarray(result, dtype=np.float64)
    radius = condition['motionPx']//2
    if radius:
        padded = np.pad(values, ((0, 0), (radius, radius)), mode='edge')
        values = np.mean([padded[:, i:i+image.width] for i in range(radius*2+1)], axis=0)
    # Luma is direct 8-bit sensor-like intensity. Apply gain BEFORE read noise.
    values *= condition['gain']
    if condition['noiseSigmaLuma']:
        values += np.random.default_rng(seed).normal(0, condition['noiseSigmaLuma'], values.shape)
    return np.rint(values).clip(0, 255).astype(np.uint8)


def build(root, protocol_path=PROTOCOL):
    protocol_raw = protocol_path.read_bytes()
    protocol = json.loads(protocol_raw)
    validate_protocol(protocol)
    root.mkdir(parents=True, exist_ok=False)
    (root/'luma').mkdir()
    rows, examples = [], []

    def save(identifier, values, metadata):
        raw = values.tobytes()
        relative = f'luma/{identifier}.y8'
        (root/relative).write_bytes(raw)
        rows.append({'id': identifier, 'asset': {'path': relative, 'sha256': sha(raw)},
                     'width': values.shape[1], 'height': values.shape[0], 'rowStride': values.shape[1], **metadata})

    for split, selection in protocol['splits'].items():
        for family in selection['families']:
            for seed in selection['seeds']:
                for width, height in protocol['sizes']:
                    for contrast in protocol['contrasts']:
                        base_id = f'{split}-{family}-{seed}-{width}x{height}-c{round(contrast*100)}'
                        image = make_chart(family, seed, width, height, contrast)
                        for condition in protocol['conditions']:
                            values = transform(image, condition, seed+100000)
                            save(f'{base_id}-{condition["id"]}', values, {
                                'baseId': base_id, 'split': split, 'family': family, 'seed': seed,
                                'contrast': contrast, 'condition': condition['id'], 'transform': condition})
                            if seed == selection['seeds'][0] and width == protocol['sizes'][0][0] and contrast == 1:
                                if condition['id'] in ('sharp', 'defocus-5', 'defocus-5-noise-8'):
                                    examples.append((f'{family}\n{condition["id"]}', Image.fromarray(values)))
    # Period-8 patterns expose sampling phase independently of texture/blur/noise.
    phase = protocol['phaseProbe']
    for width, height in protocol['sizes']:
        y, x = np.mgrid[:height, :width]
        for px in phase['xOffsets']:
            for py in phase['yOffsets']:
                values = np.where((((x+px)//phase['cellPx']+(y+py)//phase['cellPx'])%2)==0, 50, 205).astype(np.uint8)
                save(f'phase-{width}x{height}-{px}-{py}', values, {'baseId': f'phase-{width}x{height}',
                    'split': 'diagnostic', 'family': 'periodic-checker', 'condition': 'sharp',
                    'phaseX': px, 'phaseY': py, 'transform': None})
    # Flat/noise controls separate a noise response from any scene edge response.
    for sigma in (0, 2, 8, 24):
        for width, height in protocol['sizes']:
            condition = {'blurSigmaPx': 0, 'motionPx': 1, 'gain': 1, 'noiseSigmaLuma': sigma}
            values = transform(Image.new('L', (width, height), 128), condition, 530091)
            save(f'flat-{width}x{height}-noise-{sigma}', values, {'baseId': f'flat-{width}x{height}',
                'split': 'diagnostic', 'family': 'flat', 'condition': f'noise-{sigma}', 'transform': condition})
    manifest = {'schemaVersion': 1, 'experimentId': protocol['experimentId'], 'scope': protocol['scope'],
        'promotionAllowed': False, 'protocolSha256': sha(protocol_raw),
        'generatorSha256': sha(Path(__file__).read_bytes()), 'images': rows}
    (root/'protocol.json').write_bytes(protocol_raw)
    (root/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    cell_w, cell_h = 172, 270
    sheet = Image.new('RGB', (cell_w*3, cell_h*(len(examples)//3)), '#202329')
    draw = ImageDraw.Draw(sheet)
    for i, (label, image) in enumerate(examples):
        image.thumbnail((164, 228))
        left, top = (i%3)*cell_w, (i//3)*cell_h
        sheet.paste(image.convert('RGB'), (left+(cell_w-image.width)//2, top))
        draw.text((left+4, top+232), label, fill='white')
    sheet.save(root/'examples.jpg', quality=92)
    print(f'QUALITY_CORPUS {len(rows)} images; {root}')
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('output', type=Path)
    p.add_argument('--protocol', type=Path, default=PROTOCOL)
    a = p.parse_args()
    build(a.output, a.protocol)

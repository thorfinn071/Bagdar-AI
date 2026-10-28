"""Deterministic image formation approximations, not a calibrated phone ISP."""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def apply(image, condition, seed, frame_index, severity=1):
    if condition not in {"clean", "shake", "lowlight", "defocus", "rain", "mixed"}:
        raise ValueError("Unknown condition")
    if not 0 < severity <= 3:
        raise ValueError("severity must be in (0, 3]")
    result = image.convert("RGB")
    rng = np.random.default_rng(seed+frame_index*7919)
    width, height = result.size
    if condition in {"shake", "mixed"}:
        # Approximate within-exposure motion, alongside actual 3-D camera shake.
        radius = max(1, round(width*.007*severity))
        a = np.asarray(result, dtype=np.float32)
        padded = np.pad(a, ((0, 0), (radius, radius), (0, 0)), mode="edge")
        result = Image.fromarray(np.mean([padded[:, i:i+width] for i in range(2*radius+1)], axis=0).astype(np.uint8))
    if condition in {"defocus", "mixed"}:
        result = result.filter(ImageFilter.GaussianBlur(width*.009*severity))
    if condition in {"rain", "mixed"}:
        overlay = Image.new("RGBA", result.size)
        draw = ImageDraw.Draw(overlay)
        for _ in range(round(width*height*.0016*severity)):
            x, y = rng.integers(0, width), rng.integers(0, height)
            length = int(rng.integers(3, max(4, height//17)))
            draw.line((int(x), int(y), int(x-2), int(y+length)), fill=(190, 210, 225, 75), width=1)
        result = Image.alpha_composite(result.convert("RGBA"), overlay).convert("RGB")
        # Droplets remain attached to the lens across a clip, with local defocus.
        lens_rng = np.random.default_rng(seed+123)
        mask = Image.new("L", result.size)
        draw = ImageDraw.Draw(mask)
        for _ in range(round(5*severity)):
            x, y = lens_rng.integers(0, width), lens_rng.integers(0, height)
            r = int(lens_rng.integers(max(2, width//55), max(3, width//15)))
            draw.ellipse((int(x-r), int(y-r), int(x+r), int(y+r)), fill=200)
        mask = mask.filter(ImageFilter.GaussianBlur(2))
        result = Image.composite(result.filter(ImageFilter.GaussianBlur(width*.025)), result, mask)
    if condition in {"lowlight", "mixed"}:
        a = np.asarray(result, dtype=np.float32)/255
        # Lighting was reduced in Blender. Add signal-dependent shot/read noise.
        photons = max(20, 220/severity)
        a = rng.poisson(np.clip(a, 0, 1)*photons)/photons + rng.normal(0, .008*severity, a.shape)
        result = Image.fromarray(np.clip(a*255, 0, 255).astype(np.uint8))
    return result


def to_i420(image):
    """BT.601 limited-range planar YUV420, with 2x2 chroma averaging."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    h, w, _ = rgb.shape
    if w%2 or h%2:
        raise ValueError("I420 requires even image dimensions")
    r, g, b = (rgb[..., c] for c in range(3))
    y = np.clip(np.floor(16 + .256788*r + .504129*g + .097906*b + .5), 0, 255).astype(np.uint8)
    u = 128 - .148223*r - .290993*g + .439216*b
    v = 128 + .439216*r - .367788*g - .071427*b
    def chroma(a):
        return np.clip(np.floor(a.reshape(h//2, 2, w//2, 2).mean(axis=(1, 3))+.5), 0, 255).astype(np.uint8)
    return y.tobytes()+chroma(u).tobytes()+chroma(v).tobytes()

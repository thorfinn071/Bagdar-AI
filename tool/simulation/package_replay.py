"""Export an app-only bundle and separate evaluator annotations + contact sheet."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw
from camera_effects import apply, to_i420


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, data):
    Path(path).write_text(json.dumps(data, indent=2, allow_nan=False)+"\n", encoding="utf-8")


def package(root):
    root = root.resolve()
    source = root/"render-manifest.json"
    manifest = json.loads(source.read_text(encoding="utf-8"))
    runtime = root/"runtime"
    runtime.mkdir(exist_ok=False)
    spec = manifest["spec"]
    sequences, truth, thumbs = [], [], []
    for seq in manifest["sequences"]:
        target = runtime/seq["id"]
        target.mkdir()
        rows = []
        for index, f in enumerate(seq["frames"]):
            path = (root/f["render"]["path"]).resolve()
            if not path.is_relative_to(root) or sha(path.read_bytes()) != f["render"]["sha256"]:
                raise ValueError("Unsafe or modified render")
            with Image.open(path) as im:
                if im.size != (spec["width"], spec["height"]):
                    raise ValueError("Render dimensions mismatch")
                image = apply(im, seq["condition"], seq["seed"], index, spec["severity"])
            yuv = to_i420(image)
            raw = target/f"{index:04d}.i420"
            preview = target/f"{index:04d}.png"
            raw.write_bytes(yuv)
            image.save(preview)
            def asset(p):
                return {"path": p.relative_to(runtime).as_posix(), "sha256": sha(p.read_bytes())}
            rows.append({"frameId": f["frameId"], "offsetUs": f["offsetUs"], "deliveryDelayUs": 0,
                         "drop": False, "yuv": asset(raw), "preview": asset(preview)})
            if index == len(seq["frames"])//2:
                thumbs.append((seq["id"], image.copy()))
        sequences.append({"id": seq["id"], "width": spec["width"], "height": spec["height"],
            "rotationDegrees": 0, "mirrored": False, "pixelFormat": "i420-bt601-limited",
            "frames": rows, "sensors": seq["sensors"]})
        truth.append({"sequenceId": seq["id"], "layout": seq["layout"], "condition": seq["condition"],
            "physicalHazard": seq["physicalHazard"], "referenceBody": spec["referenceBody"],
            "visibilityScope": "sparse geometry witnesses before lens/noise effects; not recognizability",
            "frames": [{k: f[k] for k in ("frameId", "offsetUs", "visibleHazardWitnesses", "witnessSamples")}
                       for f in seq["frames"]]})
    save(runtime/"manifest.json", {"schemaVersion": 1, "corpusId": manifest["corpusId"],
        "synthetic": True, "scope": manifest["scope"], "promotionAllowed": False,
        "modelInput": "YUV420 pixels + synthetic inertial samples only; no labels, depth or geometry",
        "sequences": sequences})
    save(root/"annotations.json", {"schemaVersion": 1, "runtimeManifestSha256": sha((runtime/"manifest.json").read_bytes()),
        "renderManifestSha256": sha(source.read_bytes()), "packagerSha256": sha(Path(__file__).read_bytes()),
        "effectsSha256": sha(Path(__file__).with_name("camera_effects.py").read_bytes()), "sequences": truth})
    cols, tw, th = 6, 160, 264
    sheet = Image.new("RGB", (cols*tw, ((len(thumbs)+cols-1)//cols)*th), (24, 26, 30))
    draw = ImageDraw.Draw(sheet)
    for i, (label, img) in enumerate(thumbs):
        img.thumbnail((tw-8, th-36))
        x, y = (i%cols)*tw, (i//cols)*th
        sheet.paste(img, (x+(tw-img.width)//2, y))
        draw.text((x+4, y+th-32), label.replace("-", "\n", 1), fill="white")
    sheet.save(root/"overview.jpg", quality=90)
    print(f"PACKAGED {len(sequences)} sequences, {sum(len(s['frames']) for s in sequences)} frames -> {runtime}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("corpus", type=Path)
    package(p.parse_args().corpus)

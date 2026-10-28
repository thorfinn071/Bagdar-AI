"""Byte-level proof for the two existing MiDaS preprocessing contract names.

Execute the actual local preprocessing ASTs without loading/invoking a model.
No approximate resize, metadata-only rename or RGB/depth oracle is used.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"
RECEIPT = ROOT / "docs/_baseline_logs/blender_body_preprocess_equivalence_v1.json"
PAIRED = ROOT / "tool/model_benchmark/evaluate_paired_scene_models.py"
VISIBLE = ROOT / "tool/model_benchmark/generate_visible_passage_ncnn.py"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build():
    tree = ast.parse(PAIRED.read_text(encoding="utf-8"))
    pixels = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "pixels")
    paired_module = ast.fix_missing_locations(ast.Module(body=[pixels], type_ignores=[]))
    paired_namespace = {"Image": Image, "np": np}
    exec(compile(paired_module, str(PAIRED), "exec"), paired_namespace)

    visible = ast.parse(VISIBLE.read_text(encoding="utf-8"))
    decode = next(n for n in ast.walk(visible) if isinstance(n, ast.With)
                  and "read_asset(f['rgb'])" in ast.unparse(n.items[0].context_expr))
    assignments = []
    for name, marker in (("ys", "f['height']"), ("xs", "f['width']"), ("rgb", "a[ys")):
        assignments.append(next(n for n in ast.walk(visible)
                                if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                                and n.targets[0].id == name and marker in ast.unparse(n.value)))
    canonical_module = ast.fix_missing_locations(ast.Module(body=[decode, *assignments], type_ignores=[]))
    canonical_code = compile(canonical_module, str(VISIBLE), "exec")
    corpus = json.loads((CORPUS / "corpus-manifest.json").read_text())
    records = []
    for sequence in corpus["sequences"]:
        for frame in sequence["frames"]:
            path = CORPUS / frame["rgb"]["path"]
            assert sha(path) == frame["rgb"]["sha256"]
            old = paired_namespace["pixels"](path)
            namespace = {"np": np, "Image": Image, "variant": "clean",
                         "read_asset": lambda _, current=path: current,
                         "f": {"rgb": frame["rgb"], "height": 240, "width": 320}}
            exec(canonical_code, namespace)
            new = namespace["rgb"]
            assert old.shape == new.shape == (256, 256, 3)
            assert old.dtype == new.dtype == np.float32
            assert old.tobytes() == new.tobytes(), (sequence["sceneId"], frame["frameIndex"])
            chw = np.ascontiguousarray(new.transpose(2, 0, 1))
            records.append({"sceneId": sequence["sceneId"], "frameIndex": frame["frameIndex"],
                            "rgbSha256": frame["rgb"]["sha256"],
                            "inputTensorSha256": hashlib.sha256(chw.tobytes()).hexdigest()})
    assert len(records) == 132
    return {"schemaVersion": 1, "passed": True, "exactInputFrames": len(records),
            "scope": "actual RGB01/nearest/CHW tensor equivalence on known pinned RGB; no inference or metric conversion",
            "fromId": "pinned-RGB01-CHW-256-nearest-stretch-v1",
            "toId": "rgb01-chw-256-nearest-stretch-no-crop-v1",
            "corpusManifestSha256": sha(CORPUS / "corpus-manifest.json"),
            "sources": {"tool/model_benchmark/evaluate_paired_scene_models.py": sha(PAIRED),
                        "tool/model_benchmark/generate_visible_passage_ncnn.py": sha(VISIBLE),
                        "tool/model_benchmark/generate_context_ncnn_depth.py": sha(ROOT / "tool/model_benchmark/generate_context_ncnn_depth.py"),
                        "tool/model_benchmark/verify_body_preprocess_equivalence.py": sha(__file__)},
            "frames": records}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--write", action="store_true")
    args = p.parse_args()
    current = build()
    if args.write:
        if RECEIPT.exists():
            raise ValueError("Preprocess equivalence is write-once")
        RECEIPT.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")
    elif json.loads(RECEIPT.read_text()) != current:
        raise ValueError("Changed preprocess inputs or source")
    print("Actual preprocessing tensors match byte-for-byte on 132 pinned RGB frames")

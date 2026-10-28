"""Bit-exact renderer parity on floor seams and detailed moving geometry."""
import hashlib
import json
from pathlib import Path
import sys
import time

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as baseline
import visible_bounds_fast as candidate

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    manifest = json.loads((CORPUS / "corpus-manifest.json").read_text())
    baseline.W, baseline.H = manifest["width"], manifest["height"]
    results = []
    for scene_id, frame_index in [("path-clear", 0), ("person-approach", 10)]:
        row = next(s for s in manifest["sequences"] if s["sceneId"] == scene_id)
        bpy.ops.wm.open_mainfile(filepath=str(CORPUS / row["scene"]["path"]))
        scene = bpy.context.scene
        scene.frame_set(frame_index + 1)
        bpy.context.view_layer.update()
        camera = scene.camera
        p = row["frames"][frame_index]["cameraPose"]
        started = time.perf_counter()
        original = baseline.visible_depth(scene, camera, p["fx"], p["fy"], p["cx"], p["cy"])
        original_ms = (time.perf_counter() - started) * 1000
        started = time.perf_counter()
        optimized = candidate.visible_depth(scene, camera, p["fx"], p["fy"], p["cx"], p["cy"], baseline.W, baseline.H)
        optimized_ms = (time.perf_counter() - started) * 1000
        for a, b in zip(original, optimized):
            assert a.tobytes() == b.tobytes(), scene_id
        results.append({"sceneId": scene_id, "frameIndex": frame_index,
                        "bitExact": True, "frozenRendererMs": original_ms,
                        "optimizedRendererMs": optimized_ms})
        print("RENDERER_PARITY", results[-1], flush=True)
    output = {"passed": True, "sources": {
        "tool/blender/generate_visible_passage_corpus.py": sha(baseline.__file__),
        "tool/blender/visible_bounds_fast.py": sha(candidate.__file__),
        "tool/blender/check_visible_bounds_fast.py": sha(__file__)}, "cases": results}
    target = ROOT / "docs/_baseline_logs/blender_visible_bounds_fast_parity_v1.json"
    if target.exists():
        raise ValueError("Renderer parity receipt is write-once")
    target.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

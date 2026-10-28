"""Export first-return whole-pixel bounds; never modify the frozen corpus.

Only the renderer opens meshes. Consumers receive optical packets without
object names, labels or geometry. Static scans are coverage diagnostics only.
"""
import gzip
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"
OUTPUT = ROOT / "test/fixtures/spatial_safety/blender-paired-visible-body-v1"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as renderer
import visible_bounds_fast as fast_renderer


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def export():
    if (OUTPUT / "manifest.json").exists():
        raise ValueError("Never overwrite a completed visible-body corpus")
    manifest = json.loads((SOURCE / "corpus-manifest.json").read_text())
    renderer.W, renderer.H = manifest["width"], manifest["height"]
    OUTPUT.mkdir(parents=True, exist_ok=True)

    def packet(scene, camera, path, frame_id, offset):
        bpy.context.view_layer.update()
        projection = camera.calc_matrix_camera(
            bpy.context.evaluated_depsgraph_get(), x=renderer.W, y=renderer.H,
            scale_x=1, scale_y=1)
        fx, fy = projection[0][0] * renderer.W / 2, projection[1][1] * renderer.H / 2
        cx, cy = renderer.W / 2, renderer.H / 2
        suffixes = ("range.f32", "lower.f32", "upper.f32", "valid.u8")
        cached = False
        try:
            arrays = [np.frombuffer(gzip.decompress((OUTPUT / f"{path}-{suffix}.gz").read_bytes()),
                                    dtype="u1" if suffix == "valid.u8" else "<f4").reshape(renderer.H, renderer.W)
                      for suffix in suffixes]
            cached = True
        except (OSError, ValueError, EOFError):
            arrays = fast_renderer.visible_depth(scene, camera, fx, fy, cx, cy, renderer.W, renderer.H)
        radial, lower, upper, valid = arrays
        world = np.array(camera.matrix_world, dtype=float)
        rotation = world[:3, :3] @ np.diag([1., -1., -1.])

        def asset(suffix, data):
            target = OUTPUT / f"{path}-{suffix}.gz"
            target.parent.mkdir(parents=True, exist_ok=True)
            if not cached:
                target.write_bytes(gzip.compress(data, mtime=0))
            return {"path": target.relative_to(OUTPUT).as_posix(), "sha256": sha(target)}

        print(f"VISIBLE_PACKET {path} {'checkpoint' if cached else 'new'}", flush=True)
        return {"width": renderer.W, "height": renderer.H, "frameId": frame_id,
                "capturedOffsetMs": offset, "fx": fx, "fy": fy, "cx": cx, "cy": cy,
                "cameraToWalkingRotation": rotation.ravel().tolist(),
                "cameraOriginM": [0., 0., float(world[2, 3])],
                "depth": asset("range.f32", radial.tobytes()),
                "freeZLower": asset("lower.f32", lower.tobytes()),
                "surfaceZUpper": asset("upper.f32", upper.tobytes()),
                "validity": asset("valid.u8", valid.tobytes())}

    sequences = []
    for sequence in manifest["sequences"]:
        blend = SOURCE / sequence["scene"]["path"]
        assert sha(blend) == sequence["scene"]["sha256"]
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        scene, camera = bpy.context.scene, bpy.context.scene.camera
        single = []
        for frame in sequence["frames"]:
            index = frame["frameIndex"]
            scene.frame_set(index + 1)
            current = packet(scene, camera, f"{sequence['sceneId']}/single-{index:02d}",
                             index + 1, frame["capturedOffsetMs"])
            for key in ("fx", "fy", "cx", "cy"):
                assert abs(current[key] - frame["cameraPose"][key]) < 1e-5
            current["rgbSha256"] = frame["rgb"]["sha256"]
            single.append(current)
        # Frozen final-state geometry, same optical centre; no geometry-derived
        # choice of viewpoints or selection based on physical labels.
        final_rotation = camera.rotation_euler.copy()
        scan = []
        poses = [(yaw, pitch) for pitch in (-65., -15., 35.) for yaw in (-60., 0., 60.)]
        for index, (yaw, pitch) in enumerate(poses):
            camera.rotation_euler = renderer.camera_rotation(yaw, pitch, 0).to_euler()
            scan.append(packet(scene, camera, f"{sequence['sceneId']}/scan-{index:02d}",
                               index + 101, index * 200))
        camera.rotation_euler = final_rotation
        scan.append(packet(scene, camera, f"{sequence['sceneId']}/scan-09", 11, 2000))
        sequences.append({"sceneId": sequence["sceneId"], "single": single, "staticScan": scan})
        print(f"VISIBLE_BODY {sequence['sceneId']} {len(single)} original views, {len(scan)} static views", flush=True)

    output = {"schemaVersion": 1, "corpusId": "blender-paired-visible-body-v1",
              "sourceCorpusSha256": sha(SOURCE / "corpus-manifest.json"),
              "promotionAllowed": False, "metricCalibration": "synthetic_renderer_only",
              "depthSemantics": "first-visible Euclidean range, whole-pixel axis-Z bounds",
              "staticScanScope": "frozen final geometry; counterfactual observability, not dynamic safety",
              "sources": {str(Path(__file__).relative_to(ROOT)).replace('\\', '/'): sha(__file__),
                          "tool/blender/generate_visible_passage_corpus.py": sha(renderer.__file__),
                          "tool/blender/visible_bounds_fast.py": sha(fast_renderer.__file__),
                          "tool/blender/check_visible_bounds_fast.py": sha(ROOT / "tool/blender/check_visible_bounds_fast.py"),
                          "docs/_baseline_logs/blender_visible_bounds_fast_parity_v1.json": sha(ROOT / "docs/_baseline_logs/blender_visible_bounds_fast_parity_v1.json"),
                          "docs/blender-visible-body-protocol-2026-10-04.md": sha(ROOT / "docs/blender-visible-body-protocol-2026-10-04.md")},
              "sequences": sequences}
    (OUTPUT / "manifest.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {sum(len(s['single']) + len(s['staticScan']) for s in sequences)} optical packets", flush=True)


if __name__ == "__main__":
    export()

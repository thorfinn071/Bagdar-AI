"""Write-once viewpoint experiment; only this renderer sees synthetic meshes."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as renderer
import visible_bounds_fast as bounds

VIEWS = (
    ("original", 1.42, 12., 26.),
    ("chest-level", 1.42, 0., 26.),
    ("waist-level", .975, 0., 26.),
    ("waist-down", .975, 25., 26.),
    ("ideal-wide-control", .975, 0., 2.5),
)
CASES = (
    ("clear-first", "path-clear", 0, None, False),
    ("clear-final", "path-clear", 10, None, False),
    ("box", "path-box", 10, None, True),
    ("low-headroom", "headroom-low", 10, None, True),
    ("drop", "floor-drop", 10, None, True),
    ("thin-pole", "path-clear", 10, "thin", True),
    ("hidden-pole", "path-clear", 10, "hidden", True),
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(output):
    if output.exists():
        raise ValueError("Use a new output directory; never overwrite a trial")
    output.mkdir(parents=True)
    source = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"
    manifest = json.loads((source / "corpus-manifest.json").read_text())
    packets = []
    for case, scene_id, index, contrast, hazard in CASES:
        sequence = next(s for s in manifest["sequences"] if s["sceneId"] == scene_id)
        blend = source / sequence["scene"]["path"]
        assert sha(blend) == sequence["scene"]["sha256"]
        for view, height, pitch, lens in VIEWS:
            bpy.ops.wm.open_mainfile(filepath=str(blend))
            scene, camera = bpy.context.scene, bpy.context.scene.camera
            scene.frame_set(index + 1)
            # Clear keyframes before applying the intervention; preserve the
            # frozen final horizontal location as the walking reference.
            horizontal = list(camera.location)[:2]
            camera.animation_data_clear()
            camera.location = (*horizontal, height)
            camera.rotation_euler = renderer.camera_rotation(0., -pitch, 0.).to_euler()
            camera.data.lens = lens
            camera.data.sensor_width = 36.
            if contrast:
                renderer.cube("experiment-pole", (0., horizontal[1] + 2.1, .95),
                              (.002, .002, .95), (.16, .18, .20))
                if contrast == "hidden":
                    renderer.cube("experiment-opaque-occluder",
                                  (0., horizontal[1] + 1.45, 1.),
                                  (.60, .035, 1.), (.22, .26, .29))
            bpy.context.view_layer.update()
            width, height_px = manifest["width"], manifest["height"]
            projection = camera.calc_matrix_camera(
                bpy.context.evaluated_depsgraph_get(), x=width, y=height_px,
                scale_x=1, scale_y=1)
            fx, fy = projection[0][0] * width / 2, projection[1][1] * height_px / 2
            cx, cy = width / 2, height_px / 2
            radial, lower, upper, valid = bounds.visible_depth(
                scene, camera, fx, fy, cx, cy, width, height_px)
            world = np.array(camera.matrix_world, dtype=float)
            rotation = world[:3, :3] @ np.diag([1., -1., -1.])
            folder = output / case / view
            folder.mkdir(parents=True)

            def asset(name, data):
                path = folder / name
                path.write_bytes(gzip.compress(data, mtime=0))
                return {"path": path.relative_to(output).as_posix(), "sha256": sha(path)}

            # RGB and depth share the actual new camera. No frozen neural
            # result is ever relabelled as an output of this changed view.
            scene.render.filepath = str(folder / "rgb.png")
            scene.render.resolution_percentage = 100
            bpy.ops.render.render(write_still=True)
            rgb = folder / "rgb.png"
            packet = {
                "caseId": case, "viewId": view, "sceneId": scene_id,
                "originalFrameIndex": index, "physicalHazard": hazard,
                "syntheticContrast": contrast, "sourceBlendSha256": sha(blend),
                "width": width, "height": height_px, "frameId": index + 1,
                "capturedOffsetMs": sequence["frames"][index]["capturedOffsetMs"],
                "pitchDownDeg": pitch, "lensMm": lens,
                "fx": fx, "fy": fy, "cx": cx, "cy": cy,
                "cameraToWalkingRotation": rotation.ravel().tolist(),
                "cameraOriginM": [0., 0., float(world[2, 3])],
                "rgb": {"path": rgb.relative_to(output).as_posix(), "sha256": sha(rgb)},
                "depth": asset("range.f32.gz", radial.tobytes()),
                "freeZLower": asset("lower.f32.gz", lower.tobytes()),
                "surfaceZUpper": asset("upper.f32.gz", upper.tobytes()),
                "validity": asset("valid.u8.gz", valid.tobytes()),
            }
            packets.append(packet)
            print(f"VIEW_PACKET {case}/{view}", flush=True)
    files = [Path(__file__), Path(renderer.__file__), Path(bounds.__file__),
             ROOT / "docs/camera-view-coverage-protocol-2026-10-09.md"]
    result = {
        "schemaVersion": 1, "experimentId": "camera-view-coverage-2026-10-09",
        "sourceCorpusSha256": sha(source / "corpus-manifest.json"),
        "metricCalibration": "synthetic_renderer_only", "promotionAllowed": False,
        "blenderVersion": bpy.app.version_string, "packets": packets,
        "sources": {p.relative_to(ROOT).as_posix(): sha(p) for p in files},
    }
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    target = (ROOT / args.output).resolve()
    if not target.is_relative_to(ROOT / "scratch"):
        raise ValueError("Experiment output must remain in scratch")
    run(target)

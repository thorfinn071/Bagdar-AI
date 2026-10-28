"""Generate a higher-resolution, three-frame synthetic obstacle corpus.

Run inside Blender 5.x:
  blender -b --python tool/blender/generate_spatial_temporal_corpus.py -- \
    --output test/fixtures/spatial_safety/blender-temporal-v2

Frames are rendered/raycast from the same camera pose. Replay sectors are
synthetic scene-state inputs for planner policy checks; they are not inferred
from the raycast depth/semantic frames or detector outputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_spatial_corpus as base


WIDTH = 256
HEIGHT = 192
SEED = 20260922
FRAME_OFFSETS_MS = (0, 300, 600)
CAMERA_Y_OFFSETS = (0.0, 0.12, 0.24)
CAMERA_X_OFFSETS = (0.0, 0.03, 0.0)
RIDER_X_OFFSETS = (-0.18, 0.0, 0.18)
CORPUS_ID = "blender-temporal-v2"
MODEL_ID = "blender-synthetic-scene-state-temporal-v2"
PREPROCESS_ID = "blender-scene-state-sectors-temporal-v2"
MODEL_HASH = hashlib.sha256(
    f"bagdar:{MODEL_ID}:{PREPROCESS_ID}".encode("utf-8")
).hexdigest()


@dataclass(frozen=True)
class Sequence:
    scene_id: str
    builder: str
    state: str
    tags: tuple[str, ...]
    expected_semantic_id: int | None = None


SEQUENCES = (
    Sequence("temporal-thin-pole", "thin_pole", "blocked", ("thin", "obstacle"), 2),
    Sequence("temporal-low-obstacle", "low_obstacle", "blocked", ("low", "obstacle"), 4),
    Sequence("temporal-overhead", "overhead_obstacle", "blocked", ("overhead", "obstacle"), 5),
    Sequence("temporal-crossing-rider", "rider", "moving", ("moving", "rider"), 10),
    Sequence("temporal-ramp", "ramp", "safe", ("ramp", "traversable")),
    Sequence("temporal-doorway", "doorway", "safe", ("doorway", "opening")),
)


def pretty(value: object) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def scene_replay(sequence: Sequence) -> tuple[list[dict[str, object]], dict[str, object]]:
    frames: list[dict[str, object]] = []
    timeline: list[dict[str, object]] = []
    safe = sequence.state == "safe"
    action = "continueForward" if safe else "stopNow"
    for index, offset in enumerate(FRAME_OFFSETS_MS):
        sectors = {
            name: base.sector(sequence.state, name)
            for name in ("left", "forward", "right")
        }
        for sector in sectors.values():
            sector["sourceMask"] = ["synthetic_scene_state"]
            sector["lastObservedOffsetMs"] = offset
        frames.append({
            "schemaVersion": 1,
            "sceneId": sequence.scene_id,
            "frameIndex": index,
            "capturedOffsetMs": offset,
            "evaluateOffsetMs": offset,
            "validUntilOffsetMs": offset + 900,
            "sessionGeneration": 1,
            "frameId": index + 1,
            "modelId": MODEL_ID,
            "modelHash": MODEL_HASH,
            "preprocessId": PREPROCESS_ID,
            "orientationValid": True,
            "sensingHealthy": True,
            "userMoving": True,
            "sectors": sectors,
        })
        timeline.append({
            "startOffsetMs": offset,
            "endOffsetMs": offset + 100,
            "expectedActions": [action],
            "forbiddenActions": ["adjustLeft", "adjustRight"] + ([] if safe else ["continueForward"]),
            "expectedHealth": ["healthy"],
            "expectedAlertEvents": ["suppressed" if safe or index > 0 else "emitted"],
            # Three consistent observed revisions allow a left proposal, but
            # the user-facing action remains stopNow and the proposal is shadow.
            "expectedShadowDirections": ["left" if not safe and index == 2 else "none"],
            "interruptCurrent": False,
        })
    annotations = {
        "schemaVersion": 1,
        "sceneId": sequence.scene_id,
        "annotationRevision": 1,
        "initialFeedback": "none",
        "timeline": timeline,
    }
    return frames, annotations


def main() -> None:
    raw_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args(raw_args)
    repo_root = Path(__file__).resolve().parents[2]
    output_root = (repo_root / args.output).resolve()
    if repo_root not in output_root.parents:
        raise SystemExit("Output must remain inside the repository")
    output_root.mkdir(parents=True, exist_ok=True)
    renders = output_root / "renders"
    scenes_root = output_root / "scenes"
    renders.mkdir(exist_ok=True)
    scenes_root.mkdir(exist_ok=True)

    # Reuse the geometry and raycaster without touching the pinned v1 corpus.
    base.WIDTH = WIDTH
    base.HEIGHT = HEIGHT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("bagdar-temporal-world")
    scene.world.color = (0.05, 0.05, 0.05)
    materials = {
        "ground": base.material("ground", (0.18, 0.20, 0.22, 1.0)),
        "hazard": base.material("hazard", (0.75, 0.12, 0.08, 1.0)),
        "safe": base.material("safe", (0.12, 0.55, 0.22, 1.0)),
        "glass": base.material("glass", (0.18, 0.55, 0.78, 0.30), alpha=0.30),
        "person": base.material("person", (0.75, 0.42, 0.08, 1.0)),
        "rain": base.material("rain", (0.55, 0.72, 0.92, 1.0)),
    }
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 8))
    sun = bpy.context.object
    sun.data.energy = 2.0
    sun.rotation_euler = (math.radians(25), math.radians(-20), math.radians(-25))
    bpy.ops.object.camera_add(location=(0, 0, 1.45))
    camera = bpy.context.object
    camera.name = "egocentric-camera"
    camera.data.lens = 26.0
    camera.data.sensor_width = 36.0
    camera.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    scene.camera = camera

    for index, sequence in enumerate(SEQUENCES):
        source = base.Scenario(
            f"blender-{sequence.scene_id}", sequence.tags, sequence.state, sequence.builder
        )
        base.build_geometry(source, index * 30.0, materials)
    # The v1 low box at 1.8 m is below this chest camera's FOV. Move the
    # synthetic object to 2.8 m; validate the rendered/raycast mask below.
    bpy.data.objects["low-box"].location.y = 2.8
    bpy.context.view_layer.update()
    camera.location = (0.0, 0.0, 1.45)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_root / "scene.blend"), compress=True)

    assets: list[dict[str, object]] = []
    replay_scenes: list[dict[str, object]] = []
    for index, sequence in enumerate(SEQUENCES):
        base_x = index * 30.0
        moving_objects = [
            obj for obj in scene.objects
            if obj.get("semantic_id") == 10 and abs(obj.location.x - base_x) < 3
        ] if sequence.builder == "rider" else []
        original_x = {obj.name: obj.location.x for obj in moving_objects}
        scene_assets: list[dict[str, object]] = []
        seen_rgb_hashes: set[str] = set()
        for frame_index, offset in enumerate(FRAME_OFFSETS_MS):
            camera.location = (
                base_x + CAMERA_X_OFFSETS[frame_index],
                CAMERA_Y_OFFSETS[frame_index],
                1.45,
            )
            if moving_objects:
                for obj in moving_objects:
                    obj.location.x = original_x[obj.name] + RIDER_X_OFFSETS[frame_index]
            bpy.context.view_layer.update()
            stem = f"{sequence.scene_id}_f{frame_index}"
            rgb_path = renders / f"{stem}_rgb.png"
            depth_path = renders / f"{stem}_depth_mm.pgm"
            semantic_path = renders / f"{stem}_semantic.pgm"
            scene.render.filepath = str(rgb_path)
            bpy.ops.render.render(write_still=True)
            depth, semantics = base.raycast(camera, scene, noisy_depth=False)
            base.write_pgm16(depth_path, depth)
            base.write_pgm8(semantic_path, semantics)
            if sequence.expected_semantic_id is not None:
                center_pixels = sum(
                    semantics[row * WIDTH + column] == sequence.expected_semantic_id
                    for row in range(HEIGHT)
                    for column in range(WIDTH // 3, WIDTH * 2 // 3)
                )
                if center_pixels < 8:
                    raise RuntimeError(
                        f"{sequence.scene_id} frame {frame_index}: hazard outside forward FOV "
                        f"({center_pixels} pixels)"
                    )
            rgb_hash = base.sha256(rgb_path)
            if rgb_hash in seen_rgb_hashes:
                raise RuntimeError(f"duplicate temporal RGB: {sequence.scene_id}")
            seen_rgb_hashes.add(rgb_hash)
            scene_assets.append({
                "frameIndex": frame_index,
                "capturedOffsetMs": offset,
                "cameraPose": {
                    "locationMetres": [round(v, 6) for v in camera.location],
                    "rotationEulerRadians": [round(v, 6) for v in camera.rotation_euler],
                    "horizontalFovRadians": round(camera.data.angle_x, 8),
                    "verticalFovRadians": round(camera.data.angle_y, 8),
                },
                "rgb": {"path": f"renders/{rgb_path.name}", "sha256": rgb_hash},
                "depth": {
                    "path": f"renders/{depth_path.name}",
                    "sha256": base.sha256(depth_path),
                    "encoding": "P5 uint16 big-endian millimetres; 0=unobserved",
                },
                "semantic": {
                    "path": f"renders/{semantic_path.name}",
                    "sha256": base.sha256(semantic_path),
                    "encoding": "P5 uint8 class id",
                },
            })

        scene_dir = scenes_root / sequence.scene_id
        scene_dir.mkdir(exist_ok=True)
        frames_path = scene_dir / "frames.jsonl"
        annotations_path = scene_dir / "annotations.json"
        frames, annotations = scene_replay(sequence)
        frames_path.write_text(
            "".join(json.dumps(frame, separators=(",", ":")) + "\n" for frame in frames),
            encoding="utf-8",
        )
        annotations_path.write_text(pretty(annotations), encoding="utf-8")
        assets.append({
            "sceneId": sequence.scene_id,
            "state": sequence.state,
            "tags": list(sequence.tags),
            "frames": scene_assets,
        })
        replay_scenes.append({
            "id": sequence.scene_id,
            "kind": "blender-temporal",
            "frames": f"scenes/{sequence.scene_id}/frames.jsonl",
            "annotations": f"scenes/{sequence.scene_id}/annotations.json",
            "sha256": {
                "frames": base.sha256(frames_path),
                "annotations": base.sha256(annotations_path),
            },
            "tags": [*sequence.tags, "blender", "temporal", "synthetic-scene-state"],
            "annotationRevision": 1,
            "requiredForRc": True,
            "coverage": "complete",
        })
    replay_manifest = {
        "schemaVersion": 1,
        "corpusId": CORPUS_ID,
        "seed": SEED,
        "generatorId": "bagdar-blender-temporal-v2",
        "timelineOriginUtc": "2026-09-22T00:00:00.000Z",
        "source": {
            "type": "blender",
            "license": "project-generated-test-fixture",
            "consentClass": "not_applicable",
        },
        "handling": "public",
        "camera": {
            "mount": "synthetic_chest_approach",
            "parameters": f"{WIDTH}x{HEIGHT}; lens=26mm; sensor=36mm",
            "coordinateMode": "relative",
        },
        "modelContract": {
            "modelId": MODEL_ID,
            "modelHash": MODEL_HASH,
            "preprocessId": PREPROCESS_ID,
        },
        "scenes": replay_scenes,
        "externalCorpora": [],
    }
    replay_path = output_root / "replay-manifest.json"
    replay_path.write_text(pretty(replay_manifest), encoding="utf-8")
    manifest = {
        "schemaVersion": 2,
        "corpusId": CORPUS_ID,
        "generator": "tool/blender/generate_spatial_temporal_corpus.py",
        "generatorSha256": base.sha256(Path(__file__)),
        "baseGeometryGeneratorSha256": base.sha256(Path(base.__file__)),
        "blender": {"version": bpy.app.version_string, "versionTuple": list(bpy.app.version)},
        "seed": SEED,
        "license": "project-generated-test-fixture",
        "consentClass": "not_applicable",
        "handling": "public",
        "containsRecordedMedia": False,
        "frameCountPerScene": len(FRAME_OFFSETS_MS),
        "scene": {"path": "scene.blend", "sha256": base.sha256(output_root / "scene.blend")},
        "replayManifest": {"path": "replay-manifest.json", "sha256": base.sha256(replay_path)},
        "semanticClasses": {
            "0": "unobserved", "1": "ground", "2": "obstacle", "3": "transparent",
            "4": "low", "5": "overhead", "6": "drop", "7": "stairs",
            "8": "traversable", "9": "crowd", "10": "moving", "11": "obstruction",
        },
        "assets": assets,
    }
    (output_root / "corpus-manifest.json").write_text(pretty(manifest), encoding="utf-8")
    print(f"Generated {len(SEQUENCES)} sequences, {len(SEQUENCES) * len(FRAME_OFFSETS_MS)} frames in {output_root}")


if __name__ == "__main__":
    main()

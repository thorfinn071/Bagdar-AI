"""Generate Bagdar's public Blender spatial-safety corpus.

Run with Blender, not CPython:
  blender -b --python tool/blender/generate_spatial_corpus.py -- \
    --output test/fixtures/spatial_safety/blender-egocentric-v1

The bundle contains small rendered RGB frames, metric ray-cast depth, semantic
masks, exact camera/object metadata, and derived relative-polar replay inputs.
It is synthetic and contains no personal or recorded camera data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy
from mathutils import Vector


SCHEMA_VERSION = 1
ANNOTATION_REVISION = 4
SEED = 20260921
WIDTH = 96
HEIGHT = 72
MAX_DEPTH_METRES = 20.0
MODEL_ID = "blender-ground-truth-relative-v1"
PREPROCESS_ID = "blender-raycast-sectors-v1"
MODEL_HASH = hashlib.sha256(
    f"bagdar:{MODEL_ID}:{PREPROCESS_ID}".encode("utf-8")
).hexdigest()


@dataclass(frozen=True)
class Scenario:
    scene_id: str
    tags: tuple[str, ...]
    state: str
    builder: str
    roll_deg: float = 0.0
    pitch_deg: float = 0.0
    dark: bool = False
    defocus: bool = False
    noisy_depth: bool = False


SCENARIOS = (
    Scenario("blender-thin-pole", ("thin", "pole", "obstacle"), "blocked", "thin_pole"),
    Scenario("blender-transparent-door", ("transparent", "reflective", "door"), "blocked", "transparent_door"),
    Scenario("blender-low-obstacle", ("low", "obstacle"), "blocked", "low_obstacle"),
    Scenario("blender-overhead-obstacle", ("overhead", "obstacle"), "blocked", "overhead_obstacle"),
    Scenario("blender-curb-up", ("curb", "up"), "blocked", "curb_up"),
    Scenario("blender-curb-down", ("curb", "down", "drop"), "drop", "curb_down"),
    Scenario("blender-pothole", ("pothole", "drop"), "drop", "pothole"),
    Scenario("blender-stairs-up", ("stairs", "up"), "blocked", "stairs_up"),
    Scenario("blender-stairs-down", ("stairs", "down", "drop"), "drop", "stairs_down"),
    Scenario("blender-ramp", ("ramp", "traversable"), "safe", "ramp"),
    Scenario("blender-narrow-passage", ("narrow", "passage"), "blocked", "narrow_passage"),
    Scenario("blender-doorway", ("doorway", "opening"), "safe", "doorway"),
    Scenario("blender-dead-end", ("dead-end", "obstacle"), "blocked", "dead_end"),
    Scenario("blender-crowd-occlusion", ("crowd", "occlusion"), "blocked", "crowd"),
    Scenario("blender-crossing-rider", ("bicycle", "moving-threat"), "moving", "rider"),
    Scenario("blender-darkness", ("darkness", "degradation"), "unknown", "thin_pole", dark=True),
    Scenario("blender-defocus-blur", ("blur", "degradation"), "unknown", "thin_pole", defocus=True),
    Scenario("blender-rain-noise", ("rain", "noise", "degradation"), "unknown", "rain", noisy_depth=True),
    Scenario("blender-excessive-roll", ("roll", "orientation"), "invalid_orientation", "doorway", roll_deg=38.0),
    Scenario("blender-excessive-pitch", ("pitch", "orientation"), "invalid_orientation", "doorway", pitch_deg=32.0),
    Scenario("blender-camera-obstruction", ("camera", "obstruction"), "unavailable", "obstruction"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pretty(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=False) + "\n"


def material(name: str, color: tuple[float, float, float, float], *, alpha: float = 1.0):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (color[0], color[1], color[2], alpha)
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alpha)
    bsdf.inputs["Roughness"].default_value = 0.65
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        bsdf.inputs["Transmission Weight"].default_value = 0.65
        value.surface_render_method = "DITHERED"
    return value


def cube(name: str, location, scale, semantic_id: int, mat):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj["semantic_id"] = semantic_id
    obj.data.materials.append(mat)
    return obj


def cylinder(name: str, location, radius: float, depth: float, semantic_id: int, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    obj["semantic_id"] = semantic_id
    obj.data.materials.append(mat)
    return obj


def add_floor(base_x: float, ground, *, end_y: float = 7.0, z: float = -0.06):
    return cube(
        "ground",
        (base_x, end_y / 2.0, z),
        (4.0, end_y / 2.0, 0.05),
        1,
        ground,
    )


def build_geometry(scenario: Scenario, base_x: float, mats: dict[str, object]):
    ground = mats["ground"]
    hazard = mats["hazard"]
    safe = mats["safe"]
    glass = mats["glass"]
    person = mats["person"]
    kind = scenario.builder
    add_floor(base_x, ground)
    if kind == "thin_pole":
        cylinder("thin-pole", (base_x, 2.1, 0.95), 0.055, 1.9, 2, hazard)
    elif kind == "transparent_door":
        cube("transparent-door", (base_x, 2.2, 1.0), (0.75, 0.025, 1.0), 3, glass)
        cube("door-frame-left", (base_x - 0.82, 2.2, 1.0), (0.06, 0.08, 1.0), 2, hazard)
        cube("door-frame-right", (base_x + 0.82, 2.2, 1.0), (0.06, 0.08, 1.0), 2, hazard)
    elif kind == "low_obstacle":
        cube("low-box", (base_x, 1.8, 0.16), (0.65, 0.32, 0.16), 4, hazard)
    elif kind == "overhead_obstacle":
        cube("overhead", (base_x, 1.9, 1.55), (0.75, 0.28, 0.18), 5, hazard)
    elif kind == "curb_up":
        cube("curb-up", (base_x, 3.0, 0.12), (4.0, 1.7, 0.12), 2, hazard)
    elif kind in {"curb_down", "pothole", "stairs_down"}:
        # A visible ledge plus lower continuation provides exact drop geometry.
        cube("near-ground", (base_x, 0.9, -0.06), (4.0, 0.9, 0.05), 1, ground)
        cube("lower-ground", (base_x, 4.4, -0.42), (4.0, 2.4, 0.05), 6, hazard)
        if kind == "pothole":
            cube("pothole-back", (base_x, 2.8, -0.20), (0.7, 0.8, 0.12), 6, hazard)
        if kind == "stairs_down":
            for step in range(4):
                cube(
                    f"down-step-{step}",
                    (base_x, 2.0 + step * 0.42, -0.09 - step * 0.10),
                    (1.5, 0.22, 0.05),
                    7,
                    hazard,
                )
    elif kind == "stairs_up":
        for step in range(5):
            cube(
                f"up-step-{step}",
                (base_x, 1.7 + step * 0.42, 0.05 + step * 0.11),
                (1.5, 0.22, 0.055 + step * 0.055),
                7,
                hazard,
            )
    elif kind == "ramp":
        ramp = cube("ramp", (base_x, 3.0, 0.25), (1.5, 1.8, 0.08), 8, safe)
        ramp.rotation_euler.x = math.radians(8.0)
    elif kind == "narrow_passage":
        cube("left-wall", (base_x - 0.62, 3.0, 1.0), (0.35, 2.0, 1.0), 2, hazard)
        cube("right-wall", (base_x + 0.62, 3.0, 1.0), (0.35, 2.0, 1.0), 2, hazard)
    elif kind == "doorway":
        cube("door-wall-left", (base_x - 1.15, 3.0, 1.1), (0.75, 0.18, 1.1), 2, hazard)
        cube("door-wall-right", (base_x + 1.15, 3.0, 1.1), (0.75, 0.18, 1.1), 2, hazard)
        cube("door-lintel", (base_x, 3.0, 2.05), (0.42, 0.18, 0.15), 5, hazard)
    elif kind == "dead_end":
        cube("dead-end", (base_x, 2.4, 1.0), (2.8, 0.18, 1.0), 2, hazard)
    elif kind == "crowd":
        for index, (x, y) in enumerate(((-0.55, 1.8), (0.25, 2.0), (0.75, 2.4), (-0.15, 2.8))):
            cylinder(f"person-{index}", (base_x + x, y, 0.85), 0.22, 1.7, 9, person)
    elif kind == "rider":
        cylinder("rider", (base_x, 2.0, 0.82), 0.24, 1.55, 10, person)
        for offset in (-0.34, 0.34):
            cylinder("wheel", (base_x + offset, 2.0, 0.35), 0.29, 0.08, 10, person).rotation_euler.y = math.pi / 2
    elif kind == "rain":
        cylinder("rain-hidden-pole", (base_x, 2.2, 0.95), 0.06, 1.9, 2, hazard)
        rng = random.Random(SEED)
        for index in range(42):
            x = base_x + rng.uniform(-1.8, 1.8)
            y = rng.uniform(0.5, 4.0)
            z = rng.uniform(0.4, 2.2)
            cylinder(f"rain-{index}", (x, y, z), 0.008, 0.32, 0, mats["rain"])
    elif kind == "obstruction":
        cube("lens-obstruction", (base_x, 0.11, 1.45), (0.12, 0.025, 0.10), 11, hazard)


def write_pgm16(path: Path, values: list[int]):
    with path.open("wb") as output:
        output.write(f"P5\n{WIDTH} {HEIGHT}\n65535\n".encode("ascii"))
        for value in values:
            output.write(struct.pack(">H", max(0, min(65535, value))))


def write_pgm8(path: Path, values: list[int]):
    with path.open("wb") as output:
        output.write(f"P5\n{WIDTH} {HEIGHT}\n255\n".encode("ascii"))
        output.write(bytes(max(0, min(255, value)) for value in values))


def raycast(camera, scene, noisy_depth: bool) -> tuple[list[int], list[int]]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    origin = camera.matrix_world.translation
    tan_x = math.tan(camera.data.angle_x / 2.0)
    tan_y = math.tan(camera.data.angle_y / 2.0)
    depths: list[int] = []
    semantics: list[int] = []
    rng = random.Random(SEED + 991)
    for row in range(HEIGHT):
        normalized_y = 1.0 - 2.0 * ((row + 0.5) / HEIGHT)
        for column in range(WIDTH):
            normalized_x = 2.0 * ((column + 0.5) / WIDTH) - 1.0
            local = Vector((normalized_x * tan_x, normalized_y * tan_y, -1.0)).normalized()
            direction = (camera.matrix_world.to_quaternion() @ local).normalized()
            hit, location, _normal, _face, obj, _matrix = scene.ray_cast(
                depsgraph, origin, direction, distance=MAX_DEPTH_METRES
            )
            if hit:
                distance = (location - origin).length
                if noisy_depth:
                    distance = max(0.0, distance + rng.gauss(0.0, 0.22))
                depths.append(round(distance * 1000.0))
                semantics.append(int(obj.get("semantic_id", 0)))
            else:
                depths.append(0)
                semantics.append(0)
    return depths, semantics


def sector(state: str, direction: str) -> dict[str, object]:
    base = {
        "observedFraction": 0.95,
        "occupancyProbability": 0.05,
        "traversabilityProbability": 0.90,
        "dropProbability": 0.02,
        "movingThreatRisk": 0.02,
        "unknownProbability": 0.05,
        "confidence": 0.90,
        "sourceMask": ["blender_depth", "blender_semantic_ground_truth"],
        "hazardIds": [],
        "lastObservedOffsetMs": 0,
    }
    if direction != "forward":
        return base
    if state == "blocked":
        base.update(occupancyProbability=0.92, traversabilityProbability=0.10, confidence=0.98, hazardIds=["blender:forward-obstacle"])
    elif state == "drop":
        base.update(dropProbability=0.90, traversabilityProbability=0.05, confidence=0.98, hazardIds=["blender:forward-drop"])
    elif state == "moving":
        base.update(movingThreatRisk=0.90, traversabilityProbability=0.15, confidence=0.98, hazardIds=["blender:crossing-rider"])
    elif state in {"unknown", "unavailable"}:
        base.update(observedFraction=0.15, traversabilityProbability=0.05, unknownProbability=0.94, confidence=0.12)
    return base


def replay_payload(scenario: Scenario) -> tuple[str, str]:
    orientation_valid = scenario.state != "invalid_orientation"
    sensing_healthy = scenario.state != "unavailable"
    frame = {
        "schemaVersion": SCHEMA_VERSION,
        "sceneId": scenario.scene_id,
        "frameIndex": 0,
        "capturedOffsetMs": 0,
        "evaluateOffsetMs": 0,
        "validUntilOffsetMs": 900,
        "sessionGeneration": 1,
        "frameId": 1,
        "modelId": MODEL_ID,
        "modelHash": MODEL_HASH,
        "preprocessId": PREPROCESS_ID,
        "orientationValid": orientation_valid,
        "sensingHealthy": sensing_healthy,
        "userMoving": True,
        "sectors": {
            name: sector(scenario.state, name) for name in ("left", "forward", "right")
        },
    }
    safe = scenario.state == "safe"
    expected_action = "continueForward" if safe else "stopNow"
    expected_health = "unavailable" if not sensing_healthy else ("degraded" if not orientation_valid else "healthy")
    annotation = {
        "schemaVersion": SCHEMA_VERSION,
        "sceneId": scenario.scene_id,
        "annotationRevision": ANNOTATION_REVISION,
        "initialFeedback": "none",
        "timeline": [{
            "startOffsetMs": 0,
            "endOffsetMs": 100,
            "expectedActions": [expected_action],
            "forbiddenActions": ["adjustLeft", "adjustRight"] + ([] if safe else ["continueForward"]),
            "expectedHealth": [expected_health],
            "expectedAlertEvents": ["suppressed" if safe else "emitted"],
            "expectedShadowDirections": ["none"],
            "interruptCurrent": False,
        }],
    }
    return json.dumps(frame, separators=(",", ":")) + "\n", pretty(annotation)


def main() -> None:
    raw_args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args(raw_args)
    repo_root = Path(__file__).resolve().parents[2]
    output_root = (repo_root / args.output).resolve()
    if repo_root not in output_root.parents:
        raise SystemExit("Output must remain inside the repository")
    renders = output_root / "renders"
    scenes_root = output_root / "scenes"
    renders.mkdir(parents=True, exist_ok=True)
    scenes_root.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    # Blender 5.x reports the Eevee engine as BLENDER_EEVEE in headless mode.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.world = bpy.data.worlds.new("bagdar-world")
    scene.world.color = (0.05, 0.05, 0.05)

    mats = {
        "ground": material("ground", (0.18, 0.20, 0.22, 1.0)),
        "hazard": material("hazard", (0.75, 0.12, 0.08, 1.0)),
        "safe": material("safe", (0.12, 0.55, 0.22, 1.0)),
        "glass": material("glass", (0.18, 0.55, 0.78, 0.30), alpha=0.30),
        "person": material("person", (0.75, 0.42, 0.08, 1.0)),
        "rain": material("rain", (0.55, 0.72, 0.92, 1.0)),
    }

    bpy.ops.object.light_add(type="SUN", location=(0, 0, 8))
    sun = bpy.context.object
    sun.name = "sun"
    sun.data.energy = 2.0
    sun.rotation_euler = (math.radians(25), math.radians(-20), math.radians(-25))

    bpy.ops.object.camera_add(location=(0, 0, 1.45))
    camera = bpy.context.object
    camera.name = "egocentric-camera"
    camera.data.lens = 26.0
    camera.data.sensor_width = 36.0
    camera.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    scene.camera = camera

    for index, scenario in enumerate(SCENARIOS):
        build_geometry(scenario, index * 30.0, mats)

    # Preserve the exact generated Blender source in the public corpus.
    camera.location = (0.0, 0.0, 1.45)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_root / "scene.blend"), compress=True)

    asset_entries = []
    replay_scenes = []
    for index, scenario in enumerate(SCENARIOS):
        base_x = index * 30.0
        camera.location = (base_x, 0.0, 1.45)
        camera.rotation_euler = (
            math.pi / 2.0 + math.radians(scenario.pitch_deg),
            0.0,
            math.radians(scenario.roll_deg),
        )
        camera.data.dof.use_dof = scenario.defocus
        camera.data.dof.focus_distance = 7.0
        camera.data.dof.aperture_fstop = 0.35
        scene.world.color = (0.001, 0.001, 0.001) if scenario.dark else (0.05, 0.05, 0.05)
        sun.data.energy = 0.02 if scenario.dark else 2.0

        stem = scenario.scene_id.removeprefix("blender-")
        rgb_path = renders / f"{stem}_rgb.png"
        depth_path = renders / f"{stem}_depth_mm.pgm"
        semantic_path = renders / f"{stem}_semantic.pgm"
        scene.render.filepath = str(rgb_path)
        bpy.ops.render.render(write_still=True)
        depth, semantics = raycast(camera, scene, scenario.noisy_depth)
        write_pgm16(depth_path, depth)
        write_pgm8(semantic_path, semantics)

        scene_dir = scenes_root / scenario.scene_id
        scene_dir.mkdir(parents=True, exist_ok=True)
        frames_path = scene_dir / "frames.jsonl"
        annotations_path = scene_dir / "annotations.json"
        frames_text, annotations_text = replay_payload(scenario)
        frames_path.write_text(frames_text, encoding="utf-8")
        annotations_path.write_text(annotations_text, encoding="utf-8")

        asset_entries.append({
            "sceneId": scenario.scene_id,
            "tags": list(scenario.tags),
            "state": scenario.state,
            "cameraPose": {
                "locationMetres": [round(v, 6) for v in camera.location],
                "rotationEulerRadians": [round(v, 6) for v in camera.rotation_euler],
                "horizontalFovRadians": round(camera.data.angle_x, 8),
                "verticalFovRadians": round(camera.data.angle_y, 8),
            },
            "rgb": {"path": f"renders/{rgb_path.name}", "sha256": sha256(rgb_path)},
            "depth": {
                "path": f"renders/{depth_path.name}",
                "sha256": sha256(depth_path),
                "encoding": "P5 uint16 big-endian millimetres; 0=unobserved",
                "maxMetres": MAX_DEPTH_METRES,
            },
            "semantic": {
                "path": f"renders/{semantic_path.name}",
                "sha256": sha256(semantic_path),
                "encoding": "P5 uint8 class id",
            },
        })
        replay_scenes.append({
            "id": scenario.scene_id,
            "kind": "blender",
            "frames": f"scenes/{scenario.scene_id}/frames.jsonl",
            "annotations": f"scenes/{scenario.scene_id}/annotations.json",
            "sha256": {"frames": sha256(frames_path), "annotations": sha256(annotations_path)},
            "tags": [*scenario.tags, "blender", "ground-truth-derived"],
            "annotationRevision": ANNOTATION_REVISION,
            "requiredForRc": True,
            "coverage": "complete",
        })

    replay_manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "corpusId": "blender-egocentric-v1",
        "seed": SEED,
        "generatorId": "bagdar-blender-primitives-v1",
        "timelineOriginUtc": "2026-09-21T00:00:00.000Z",
        "source": {
            "type": "blender",
            "license": "project-generated-test-fixture",
            "consentClass": "not_applicable",
        },
        "handling": "public",
        "camera": {
            "mount": "synthetic_chest_fixed",
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
    (output_root / "replay-manifest.json").write_text(pretty(replay_manifest), encoding="utf-8")

    corpus_manifest = {
        "schemaVersion": 1,
        "corpusId": "blender-egocentric-v1",
        "generator": "tool/blender/generate_spatial_corpus.py",
        "generatorSha256": sha256(Path(__file__)),
        "blender": {"version": bpy.app.version_string, "versionTuple": list(bpy.app.version)},
        "seed": SEED,
        "license": "project-generated-test-fixture",
        "consentClass": "not_applicable",
        "handling": "public",
        "containsRecordedMedia": False,
        "scene": {"path": "scene.blend", "sha256": sha256(output_root / "scene.blend")},
        "replayManifest": {
            "path": "replay-manifest.json",
            "sha256": sha256(output_root / "replay-manifest.json"),
        },
        "semanticClasses": {
            "0": "unobserved", "1": "ground", "2": "obstacle", "3": "transparent",
            "4": "low", "5": "overhead", "6": "drop", "7": "stairs",
            "8": "traversable", "9": "crowd", "10": "moving", "11": "obstruction",
        },
        "assets": asset_entries,
    }
    (output_root / "corpus-manifest.json").write_text(pretty(corpus_manifest), encoding="utf-8")
    print(f"Generated {len(SCENARIOS)} Blender scenarios in {output_root}")


if __name__ == "__main__":
    main()

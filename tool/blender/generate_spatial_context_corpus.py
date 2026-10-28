"""Generate a contextual synthetic RGB/depth/mask corpus without changing v2.

Run with Blender 5.x:
  blender -b --python tool/blender/generate_spatial_context_corpus.py -- \
    --output test/fixtures/spatial_safety/blender-context-v3

This remains synthetic oracle depth. Context geometry is included in the
raycast, so the rendered RGB and depth/mask always share a camera pose.
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_spatial_temporal_corpus as temporal


base = temporal.base
_original_build_geometry = base.build_geometry
_original_material = base.material


def material(name: str, color: tuple[float, float, float, float], *, alpha: float = 1.0):
    palette = {
        "ground": (0.42, 0.40, 0.37, 1.0),
        "hazard": (0.28, 0.23, 0.18, 1.0),
        "safe": (0.46, 0.43, 0.37, 1.0),
        "person": (0.18, 0.24, 0.32, 1.0),
    }
    value = _original_material(name, palette.get(name, color), alpha=alpha)
    if name in {"ground", "hazard", "safe"}:
        bsdf = value.node_tree.nodes.get("Principled BSDF")
        noise = value.node_tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 55.0 if name == "ground" else 20.0
        bump = value.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        bump.inputs["Distance"].default_value = 0.025
        value.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        value.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return value


def context_material(name: str, rgb: tuple[float, float, float], roughness: float = 0.8):
    value = _original_material(name, (*rgb, 1.0))
    value.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = roughness
    return value


def bevel(obj, width: float) -> None:
    modifier = obj.modifiers.new("softened real-world edges", "BEVEL")
    modifier.width = width
    modifier.segments = 2
    obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")


def build_geometry(source, base_x: float, mats: dict[str, object]) -> None:
    # Chest-mounted cameras commonly see some ground ahead. Keep the pose
    # explicit in every frame's camera metadata and raycast.
    bpy.context.scene.camera.rotation_euler.x = math.pi / 2.0 - math.radians(8.0)
    _original_build_geometry(source, base_x, mats)
    rng = random.Random(20260923 + round(base_x))
    concrete = context_material(f"concrete-{base_x:g}", (0.55, 0.53, 0.49))
    brick = context_material(f"brick-{base_x:g}", (0.43, 0.31, 0.25))
    mortar = context_material(f"mortar-{base_x:g}", (0.62, 0.59, 0.53))
    metal = context_material(f"metal-{base_x:g}", (0.18, 0.19, 0.20), 0.42)

    # Paving seams and alternating slabs add visible surface texture. All are
    # ground, never free-space evidence inferred from decorative RGB alone.
    for row in range(12):
        y = 0.25 + row * 0.54
        slab = base.cube(
            f"paving-{base_x:g}-{row}",
            (base_x, y, 0.001),
            (2.9, 0.259, 0.002),
            1,
            concrete if row % 3 else mortar,
        )
        slab.location.x += rng.uniform(-0.01, 0.01)
        for side in (-1, 1):
            base.cube(
                f"paving-joint-{base_x:g}-{row}-{side}",
                (base_x + side * 1.46, y, 0.004),
                (0.007, 0.258, 0.003),
                1,
                mortar,
            )

    # Side facades, windows and varied light create visual context without
    # adding unseen central hazards to the route ground truth.
    for side in (-1, 1):
        wall_x = base_x + side * 3.25
        base.cube(
            f"facade-{base_x:g}-{side}",
            (wall_x, 3.5, 1.65),
            (0.22, 3.5, 1.7),
            0,
            brick,
        )
        for y in (1.5, 3.3, 5.1):
            base.cube(
                f"window-{base_x:g}-{side}-{y:g}",
                (wall_x - side * 0.23, y, 2.0),
                (0.015, 0.55, 0.48),
                0,
                metal,
            )
        base.cube(
            f"curb-{base_x:g}-{side}",
            (base_x + side * 2.92, 3.5, 0.035),
            (0.10, 3.45, 0.045),
            0,
            concrete,
        )

    if source.builder == "low_obstacle":
        body = bpy.data.objects["low-box"]
        bevel(body, 0.045)
        body.data.materials.clear()
        body.data.materials.append(context_material("luggage-fabric", (0.23, 0.27, 0.32)))
        base.cube("luggage-handle", (base_x, 2.8, 0.38), (0.15, 0.025, 0.035), 4, metal)
        for side in (-1, 1):
            wheel = base.cylinder(
                f"luggage-wheel-{side}",
                (base_x + side * 0.48, 2.8, 0.075),
                0.075,
                0.055,
                4,
                metal,
            )
            wheel.rotation_euler.y = math.pi / 2
    elif source.builder == "thin_pole":
        pole = bpy.data.objects["thin-pole"]
        pole.data.materials.clear()
        pole.data.materials.append(metal)
        base.cylinder("bollard-cap", (base_x, 2.1, 1.91), 0.075, 0.05, 2, metal)
    elif source.builder == "overhead_obstacle":
        awning = bpy.data.objects["overhead"]
        bevel(awning, 0.035)
        awning.data.materials.clear()
        awning.data.materials.append(context_material("awning-fabric", (0.22, 0.25, 0.19)))
    elif source.builder == "rider":
        bpy.data.objects["rider"].data.materials.clear()
        bpy.data.objects["rider"].data.materials.append(context_material("jacket", (0.19, 0.32, 0.38)))
    elif source.builder == "doorway":
        # The base 0.8 m opening is narrower than Bagdar's 0.9 m corridor
        # contract. Make this labelled-passable variant 1.4 m wide; the base
        # generator retains the narrow variant for contrast.
        bpy.data.objects["door-wall-left"].location.x -= 0.30
        bpy.data.objects["door-wall-right"].location.x += 0.30
        bpy.data.objects["door-lintel"].scale.x += 0.30

    bpy.ops.object.light_add(type="AREA", location=(base_x + 2.0, 2.0, 4.8))
    light = bpy.context.object
    light.data.energy = 260.0 + rng.uniform(-25.0, 25.0)
    light.data.shape = "DISK"
    light.data.size = 5.0


def main() -> None:
    temporal.CORPUS_ID = "blender-context-v3"
    temporal.SEED = 20260923
    temporal.MODEL_ID = "blender-synthetic-scene-state-context-v3"
    temporal.PREPROCESS_ID = "blender-scene-state-sectors-context-v3"
    temporal.MODEL_HASH = temporal.hashlib.sha256(
        f"bagdar:{temporal.MODEL_ID}:{temporal.PREPROCESS_ID}".encode("utf-8")
    ).hexdigest()
    temporal.SEQUENCES = tuple(
        temporal.Sequence(
            sequence.scene_id.replace("temporal-", "context-"),
            sequence.builder,
            sequence.state,
            (*sequence.tags, "contextual-urban"),
            sequence.expected_semantic_id,
        )
        for sequence in temporal.SEQUENCES
    )
    base.material = material
    base.build_geometry = build_geometry
    temporal.main()

    raw_args = sys.argv[sys.argv.index("--") + 1:]
    output_root = (Path(__file__).resolve().parents[2] / raw_args[raw_args.index("--output") + 1]).resolve()
    manifest_path = output_root / "corpus-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["generator"] = "tool/blender/generate_spatial_context_corpus.py"
    manifest["generatorSha256"] = base.sha256(Path(__file__))
    manifest["parentTemporalGeneratorSha256"] = base.sha256(Path(temporal.__file__))
    manifest["contextRevision"] = 1
    # Only these rendered objects have a defensible COCO class mapping.
    # An awning, bollard or generic doorway has no matching COCO label;
    # an overlapping box of another class is not a correct recognition.
    class_ids = {
        "context-low-obstacle": [28],  # suitcase
        "context-crossing-rider": [0, 1],  # person, bicycle
    }
    for asset in manifest["assets"]:
        asset["compatibleCocoClassIds"] = class_ids.get(asset["sceneId"], [])
    manifest_path.write_text(temporal.pretty(manifest), encoding="utf-8")


if __name__ == "__main__":
    main()

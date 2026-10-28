"""Separate animated paired corpus; no annotations enter the perception runtime.

Run in Blender --background --python-exit-code 1 --python this-file --
  --output test/fixtures/spatial_safety/blender-paired-holdout-v1
Use --pilot for the first pair in a scratch output directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = ROOT / "tool/blender/paired_scene_spec_v1.json"
PROTOCOL = ROOT / "docs/blender-paired-scenes-protocol-2026-10-04.md"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def generate(output, pilot=False):
    import bpy
    from mathutils import Vector
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import generate_spatial_corpus as base
    import generate_visible_passage_corpus as visible

    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    if (output / "corpus-manifest.json").exists():
        raise ValueError("Never overwrite a finished corpus; use a new version or scratch pilot")
    output.mkdir(parents=True, exist_ok=True)
    width, height = spec["width"], spec["height"]
    base.WIDTH, base.HEIGHT = width, height
    bpy.context.preferences.filepaths.save_version = 0

    def mat(name, color, seed, scale=5):
        value = base.material(name, (*color, 1))
        bsdf = value.node_tree.nodes.get("Principled BSDF")
        noise = value.node_tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 2
        ramp = value.node_tree.nodes.new("ShaderNodeValToRGB")
        for element, multiplier in zip(ramp.color_ramp.elements, (.65, 1.18)):
            element.color = (*(min(1, c * multiplier) for c in color), 1)
        coord = value.node_tree.nodes.new("ShaderNodeTexCoord")
        mapping = value.node_tree.nodes.new("ShaderNodeMapping")
        mapping.inputs["Location"].default_value = (seed % 17, seed % 23, seed % 11)
        value.node_tree.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        value.node_tree.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        value.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        value.node_tree.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        return value

    def box(name, center, size, semantic, material, bevel=0):
        obj = base.cube(name, center, tuple(v / 2 for v in size), semantic, material)
        if bevel:
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            obj.select_set(False)
            modifier = obj.modifiers.new("rounded-edges", "BEVEL")
            modifier.width, modifier.segments = bevel, 2
        return obj

    sequences = []
    for entry in spec["scenes"][:2] if pilot else spec["scenes"]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x, scene.render.resolution_y = width, height
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGB"
        scene.render.fps = 5
        scene.frame_start, scene.frame_end = 1, len(spec["frameOffsetsMs"])
        scene.world = bpy.data.worlds.new("paired-world")
        scene.world.use_nodes = True
        scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.55, .6, .7, 1)
        scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .2
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = -.5
        seed = entry["appearanceSeed"]
        floor = mat("tile-floor", (.36, .34, .3), seed, 12)
        wall = mat("wall-paint", (.62, .59, .54), seed, 6)
        cardboard = mat("cardboard", (.46, .28, .13), seed, 18)
        metal = mat("frame-paint", (.2, .22, .24), seed, 5)
        shirt = mat("shirt", (.1, .25, .42), seed, 10)
        trousers = mat("trousers", (.12, .13, .16), seed, 8)
        skin = mat("skin", (.58, .37, .24), seed, 5)
        edge = entry.get("edgeY", 9)
        if entry["kind"] == "drop":
            box("floor-near", (0, (edge - 1) / 2, -.08), (6, edge + 1, .16), 1, floor)
            drop = entry["dropM"]
            box("floor-lower", (0, (edge + 9) / 2, -drop - .08), (6, 9 - edge, .16), 6, floor)
            box("step-riser", (0, edge, -drop / 2), (6, .03, drop), 6, floor)
        else:
            box("floor", (0, 4, -.08), (6, 10, .16), 1, floor)
        # Joints are real shallow geometry, using the same material in both members.
        for index in range(1, 12):
            y = index * .7
            z = -entry.get("dropM", 0) if y > edge else 0
            box(f"joint-{index}", (0, y, z + .0005), (6, .012, .001), 1, metal)
        for x in (-3.06, 3.06):
            box(f"side-wall-{x}", (x, 4, 1.55), (.12, 10, 3.1), 8, wall)
        box("back-wall", (0, 9, 1.55), (6, .15, 3.1), 8, wall)
        box("ceiling", (0, 4, 3.12), (6, 10, .12), 8, wall)
        # Common background landmarks create useful texture without encoding the label.
        for index, x in enumerate((-2.1, -1.4, 1.4, 2.1)):
            box(f"back-panel-{index}", (x, 8.91, 1.4), (.48, .01, .7), 8, cardboard, .015)
        if entry["kind"] == "box":
            sx, sy, sz = entry["boxSizeM"]
            box("carton", (0, entry["boxCenterY"], sz / 2), (sx, sy, sz), 4, cardboard, .016)
            box("carton-tape", (0, entry["boxCenterY"] - sy / 2 - .002, sz / 2), (.07, .004, sz), 4, floor)
        elif entry["kind"] == "doorway":
            opening, top, y = entry["openingWidthM"], entry["openingHeightM"], entry["planeY"]
            post_width = (6 - opening) / 2
            for sign in (-1, 1):
                box(f"door-side-{sign}", (sign * (opening / 2 + post_width / 2), y, 1.55),
                    (post_width, .24, 3.1), 2, wall)
            box("lintel", (0, y, (top + 3.1) / 2), (opening, .24, 3.1 - top), 5, wall)
        person_parts = []
        if entry["kind"] == "person":
            person_parts.append(box("torso", (0, 0, 1.18), (.46, .29, .58), 10, shirt, .055))
            person_parts.append(box("hips", (0, 0, .82), (.36, .26, .19), 10, trousers, .025))
            for sign in (-1, 1):
                person_parts.append(box(f"leg-{sign}", (sign * .11, 0, .42), (.15, .18, .72), 10, trousers, .04))
                person_parts.append(box(f"arm-{sign}", (sign * .3, 0, 1.08), (.12, .15, .62), 10, shirt, .035))
                person_parts.append(box(f"shoe-{sign}", (sign * .11, -.04, .07), (.17, .3, .14), 10, metal, .03))
            bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=.145, location=(0, 0, 1.64))
            head = bpy.context.object
            head.name, head["semantic_id"] = "head", 10
            head.scale = (1, 1, 1.2)
            head.data.materials.append(skin)
            person_parts.append(head)
        bpy.ops.object.light_add(type="AREA", location=(0, 2.5, 2.9))
        bpy.context.object.data.energy, bpy.context.object.data.size = 100, 3
        bpy.ops.object.light_add(type="AREA", location=(0, 6.5, 2.9))
        bpy.context.object.data.energy, bpy.context.object.data.size = 80, 3
        bpy.ops.object.camera_add()
        camera = bpy.context.object
        camera.name = "phone-view"
        camera.data.lens, camera.data.sensor_width = spec["camera"]["lensMm"], spec["camera"]["sensorWidthMm"]
        scene.camera = camera
        original_locations = {obj.name: obj.location.copy() for obj in person_parts}
        for index, offset in enumerate(spec["frameOffsetsMs"]):
            t = index / (len(spec["frameOffsetsMs"]) - 1)
            yaw = entry.get("cameraYawAmplitudeDeg", 0) * math.sin(2 * math.pi * t)
            camera.location = (0, t * entry["cameraAdvanceM"], spec["camera"]["heightM"])
            camera.rotation_euler = visible.camera_rotation(yaw, -spec["camera"]["pitchDownDeg"], 0).to_euler()
            camera.keyframe_insert(data_path="location", frame=index + 1)
            camera.keyframe_insert(data_path="rotation_euler", frame=index + 1)
            for obj in person_parts:
                obj.location = original_locations[obj.name] + Vector((entry["personX"], entry["personStartY"] - t * entry["personAdvanceM"], 0))
                obj.keyframe_insert(data_path="location", frame=index + 1)
        scene.frame_set(1)
        folder = output / entry["id"]
        folder.mkdir(exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(folder / "scene.blend"), compress=True)
        frames = []
        for index, offset in enumerate(spec["frameOffsetsMs"]):
            scene.frame_set(index + 1)
            bpy.context.view_layer.update()
            rgb_path = folder / f"{index:02d}-rgb.png"
            depth_path = folder / f"{index:02d}-depth-mm.pgm"
            mask_path = folder / f"{index:02d}-semantic.pgm"
            scene.render.filepath = str(rgb_path)
            bpy.ops.render.render(write_still=True)
            deps = bpy.context.evaluated_depsgraph_get()
            projection = camera.calc_matrix_camera(deps, x=width, y=height, scale_x=1, scale_y=1)
            fx, fy = projection[0][0] * width / 2, projection[1][1] * height / 2
            depths, mask = [], []
            rotation = camera.matrix_world.to_quaternion()
            for row in range(height):
                for column in range(width):
                    local = Vector(((column + .5 - width / 2) / fx, -(row + .5 - height / 2) / fy, -1)).normalized()
                    hit, point, _, _, obj, _ = scene.ray_cast(deps, camera.location, rotation @ local, distance=20)
                    depths.append(round((point - camera.location).length * 1000) if hit else 0)
                    mask.append(int(obj.get("semantic_id", 0)) if hit else 0)
            base.write_pgm16(depth_path, depths)
            base.write_pgm8(mask_path, mask)
            center_count = sum(mask[y * width + x] in {2, 4, 5, 6, 10}
                               for y in range(height) for x in range(width // 3, width * 2 // 3))
            if entry["hazard"] and center_count < 40:
                raise RuntimeError(f"Hazard not observable in {entry['id']}/{index}: {center_count}")
            def asset(path):
                return {"path": path.relative_to(output).as_posix(), "sha256": sha(path)}
            frames.append({"frameIndex": index, "capturedOffsetMs": offset,
                           "rgb": asset(rgb_path), "depth": asset(depth_path), "semantic": asset(mask_path),
                           "cameraPose": {"locationMetres": list(camera.location), "rotationEulerRadians": list(camera.rotation_euler),
                                          "fx": fx, "fy": fy, "cx": width / 2, "cy": height / 2,
                                          "pitchDownDeg": spec["camera"]["pitchDownDeg"], "yawDeg": entry.get("cameraYawAmplitudeDeg", 0) * math.sin(2 * math.pi * index / 10)}})
        annotation_path = folder / "annotations.json"
        save(annotation_path, {"sceneId": entry["id"], "pair": entry["pair"], "physicalHazard": entry["hazard"],
                              "referencePassable": not entry["hazard"], "hazardOnsetMs": 0 if entry["hazard"] else None,
                              "userMoving": entry["cameraAdvanceM"] > 0,
                              "latestStopOffsetMs": spec["latestStopAfterOnsetMs"] if entry["hazard"] else None,
                              "compatibleCocoClassIds": [0] if entry["kind"] == "person" else [],
                              "parameters": entry, "labelSource": "predeclared scene geometry, not model output"})
        sequences.append({"sceneId": entry["id"], "pair": entry["pair"], "scene": {"path": f"{entry['id']}/scene.blend", "sha256": sha(folder / "scene.blend")},
                          "annotations": {"path": annotation_path.relative_to(output).as_posix(), "sha256": sha(annotation_path)}, "frames": frames})
        print(f"PAIRED_SCENE {entry['id']} {len(frames)} frames", flush=True)
    sources = [Path(__file__), SPEC_PATH, PROTOCOL, Path(base.__file__), Path(visible.__file__)]
    save(output / "corpus-manifest.json", {"schemaVersion": 1, "corpusId": spec["corpusId"], "pilotOnly": pilot,
        "blenderVersion": bpy.app.version_string, "seed": spec["seed"], "width": width, "height": height,
        "sources": {p.relative_to(ROOT).as_posix(): sha(p) for p in sources},
        "depthSemantics": "first-visible-ray-euclidean-range-mm; zero=unobserved",
        "semanticClasses": {"0": "unobserved", "1": "floor", "2": "post", "4": "box", "5": "lintel", "6": "drop", "8": "room", "10": "person"},
        "containsRecordedMedia": False, "promotionAllowed": False, "sequences": sequences})


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--pilot", action="store_true")
    args = parser.parse_args(argv)
    target = (ROOT / args.output).resolve()
    if not target.is_relative_to(ROOT) or target == ROOT:
        raise ValueError("Output must be a subdirectory of the workspace")
    if not args.pilot and target != ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1":
        raise ValueError("Full corpus uses its separate declared output directory")
    if args.pilot and not target.is_relative_to(ROOT / "scratch"):
        raise ValueError("Pilot output must remain in scratch")
    generate(target, args.pilot)

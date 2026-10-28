"""Blender-side renderer. Runtime images and evaluator-only geometry stay separate.

blender -b --python-exit-code 1 --python tool/simulation/generate_scenes.py -- 
  --output output/simulation-lab/corpus --smoke
Then run package_replay.py with ordinary Python (NumPy + Pillow).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment_spec import validate_spec

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).with_name("lab_spec.json")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def material(name, color, roughness=.7, glass=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    if glass:
        bsdf.inputs["Transmission Weight"].default_value = .92
        bsdf.inputs["IOR"].default_value = 1.45
    else:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 14
        ramp = nodes.new("ShaderNodeValToRGB")
        for e, scale in zip(ramp.color_ramp.elements, (.62, 1.15)):
            e.color = (*(min(1, c * scale) for c in color), 1)
        m.node_tree.links.new(noise.outputs["Fac"], ramp.inputs[0])
        m.node_tree.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .12
        bump.inputs["Distance"].default_value = .018
        m.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        m.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def box(name, loc, size, mat, hazard=False, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    o["hazard"] = hazard
    if bevel:
        mod = o.modifiers.new("edge-radius", "BEVEL")
        mod.width, mod.segments = bevel, 2
    return o


def cylinder(name, loc, radius, height, mat, hazard=False):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=radius, depth=height, location=loc)
    o = bpy.context.object
    o.name, o["hazard"] = name, hazard
    o.data.materials.append(mat)
    return o


def build(layout, blocked, wet):
    stone = material("concrete", (.36, .37, .34), .12 if wet else .85)
    wall = material("plaster", (.66, .62, .53))
    brick = material("brick", (.43, .19, .12))
    metal = material("metal", (.11, .14, .17), .22)
    wood = material("wood", (.39, .23, .10))
    white = material("paint", (.82, .82, .75))
    green = material("grass", (.08, .22, .07))
    floor_end = 2.4 if layout == "sidewalk" and blocked else 12
    box("walkway", (0, (floor_end-3)/2, -.12), (3.6, floor_end+3, .24), stone)
    movers = []
    if layout == "hallway":
        for sign in (-1, 1):
            box("wall", (sign*1.9, 4, 1.65), (.2, 14, 3.3), wall)
            for i in range(4):
                box("door-panel", (sign*1.79, 1.2+i*2.6, 1.05), (.025, .9, 2.1), wood)
        box("ceiling", (0, 4, 3.4), (4, 14, .2), white)
        for i in range(11):
            box("tile-joint", (0, i*.8, .002), (3.6, .014, .003), metal)
        if blocked:
            box("box-obstacle", (0, 2.6, .3), (.7, .65, .6), wood, True, .025)
    elif layout == "courtyard":
        box("lawn-left", (-3.6, 4, -.1), (3.4, 14, .15), green)
        box("lawn-right", (3.6, 4, -.1), (3.4, 14, .15), green)
        for sign in (-1, 1):
            box("bench-seat", (sign*2.3, 3.2, .48), (.65, 1.8, .12), wood)
            box("bench-back", (sign*2.57, 3.2, .85), (.09, 1.8, .72), wood)
            for i in range(3):
                cylinder("tree-trunk", (sign*3.8, 1+i*3.7, 1.2), .18, 2.4, wood)
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(sign*3.8, 1+i*3.7, 2.7))
                bpy.context.object.data.materials.append(green)
        cylinder("bollard", (0 if blocked else 1.35, 2.7, .55), .075, 1.1, metal, blocked)
    elif layout == "shop":
        box("shop-floor", (0, 7, -.1), (8, 8, .2), stone)
        for sign in (-1, 1):
            box("shopfront", (sign*2.0, 3.1, 1.6), (2.5, .25, 3.2), brick)
            box("frame", (sign*.74, 3.0, 1.3), (.08, .1, 2.6), metal)
            box("shelf", (sign*2.3, 6, .8), (.6, 2.3, 1.6), wood)
        box("header", (0, 3.1, 2.85), (6.5, .3, .5), wood)
        if blocked:
            glass = material("clear-glass", (.8, .92, .96), .06, glass=True)
            box("glass-door", (0, 3.0, 1.28), (1.4, .035, 2.5), glass, True)
            box("door-handle", (.44, 2.94, 1.05), (.04, .06, .35), metal, True)
            box("glass-visible-stripe", (0, 2.975, 1.2), (1.4, .008, .045), white, True)
    elif layout == "sidewalk":
        box("road", (3.3, 4, -.22), (3, 16, .1), metal)
        box("boundary-wall", (-2.5, 4, .8), (.3, 16, 1.6), brick)
        for i in range(10):
            box("paving-joint", (0, i*.9, .002), (3.6, .014, .003), white)
        if blocked:
            box("lower-walkway", (0, 7.2, -.48), (3.6, 9.6, .24), stone)
            box("step-face", (0, 2.4, -.18), (3.6, .03, .36), stone, True)
        for i in range(3):
            box("parked-car", (3.2, 2+i*4.2, .65), (1.5, 2.7, 1.2), wood, bevel=.16)
    elif layout == "underpass":
        for sign in (-1, 1):
            box("tunnel-wall", (sign*1.85, 4, 1.6), (.3, 14, 3.2), stone)
            for i in range(5):
                box("wall-stripe", (sign*1.69, i*2.2, .9), (.025, .4, .15), white)
        box("tunnel-ceiling", (0, 4, 3.2), (4, 14, .2), stone)
        box("cross-beam", (0, 2.5, 1.3 if blocked else 2.8), (3.5, .22, .22), metal, blocked)
    elif layout == "pedestrian":
        box("plaza", (0, 4, -.11), (14, 16, .2), stone)
        for i in range(4):
            box("planter", ((-1 if i%2 else 1)*3.3, 1+i*2, .4), (1.1, 1.1, .8), brick)
        shirt = material("shirt", (.12, .25, .55))
        skin = material("skin", (.58, .36, .24))
        x = 0 if blocked else 1.5
        for name, loc, size, mat in [
            ("torso", (x, 3.6, 1.14), (.46, .28, .62), shirt),
            ("leg-left", (x-.13, 3.6, .42), (.17, .2, .8), metal),
            ("leg-right", (x+.13, 3.6, .42), (.17, .2, .8), metal),
            ("arm-left", (x-.31, 3.6, 1.1), (.12, .16, .6), shirt),
            ("arm-right", (x+.31, 3.6, 1.1), (.12, .16, .6), shirt)]:
            movers.append(box(name, loc, size, mat, blocked, .035))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=.15, location=(x, 3.6, 1.64))
        head = bpy.context.object
        head.name, head["hazard"] = "head", blocked
        head.data.materials.append(skin)
        movers.append(head)
    else:
        raise ValueError(layout)
    return movers


def camera_pose(t, spec, shake):
    p = spec["camera"]
    # Position and rotation functions also drive the synthetic inertial samples.
    phase = 2*math.pi*1.8*t
    severity = spec["severity"]
    bob = .022*severity if shake else .006
    x = (.026*severity if shake else .005)*math.sin(phase*.5)
    z = p["heightM"] + bob*math.sin(phase)
    pitch = p["pitchDownDeg"] + (3.8*severity if shake else .35)*math.sin(phase+.3)
    roll = (3.5*severity if shake else .3)*math.sin(phase*.5+.4)
    yaw = (2.2*severity if shake else .2)*math.sin(phase*.7)
    forward = Vector((math.sin(math.radians(yaw))*math.cos(math.radians(pitch)),
                      math.cos(math.radians(yaw))*math.cos(math.radians(pitch)), -math.sin(math.radians(pitch))))
    q = forward.to_track_quat("-Z", "Y")
    from mathutils import Quaternion
    q = q @ Quaternion((0, 0, 1), math.radians(roll))
    return Vector((x, t*p["walkingSpeedMps"], z)), q


def sensor_sample(t, spec, shake):
    dt = 1/600
    pos, q = camera_pose(t, spec, shake)
    before, qb = camera_pose(t-dt, spec, shake)
    after, qa = camera_pose(t+dt, spec, shake)
    linear = (after-2*pos+before)/(dt*dt)
    proper = q.inverted() @ (Vector((0, 0, 9.81))+linear)
    axis, angle = (qb.inverted() @ qa).to_axis_angle()
    gyro = axis*(angle/(2*dt))
    return {"offsetUs": round(t*1e6), "accelerometer": list(proper), "gyroscope": list(gyro)}


def add_urban_context(folder, layout_index):
    """Optional user's FBX library, normalized to declared background metres."""
    names = ("building-a.fbx", "building-f.fbx", "building-j.fbx", "building-m.fbx")
    assets = []
    for index in range(4):
        path = folder/names[(index+layout_index)%len(names)]
        if not path.is_file():
            raise ValueError(f"Missing urban asset: {path}")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=str(path))
        meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        if not meshes:
            raise ValueError(f"Asset has no meshes: {path}")
        bounds = [o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
        low = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
        span = high-low
        scale = min(3/max(span.x, span.y), (6+index)/span.z)
        center = Vector(((low.x+high.x)/2, (low.y+high.y)/2, low.z))
        at = Vector(((-1 if index%2 else 1)*5.2, 5+index*3.6, 0))
        transform = Matrix.Translation(at)@Matrix.Scale(scale, 4)@Matrix.Translation(-center)
        for o in meshes:
            world = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = transform@world
        assets.append({"name": path.name, "sha256": sha(path), "scale": scale,
                       "backgroundPositionM": list(at), "geometryScope": "background distractor outside reference corridor"})
    return assets


def generate(args):
    spec_path = Path(args.spec).resolve() if args.spec else SPEC
    spec = json.loads(spec_path.read_text())
    if args.smoke:
        spec.update(width=192, height=288, fps=10, frames=7)
    if args.frames is not None:
        spec["frames"] = args.frames
    if args.severity is not None:
        spec["severity"] = args.severity
    validate_spec(spec)
    if not .25 <= spec["severity"] <= 3:
        raise ValueError("severity must be .25..3")
    if not 2 <= spec["frames"] <= 601:
        raise ValueError("frames must be 2..601")
    layouts = args.layouts.split(",") if args.layouts else spec["layouts"]
    conditions = args.conditions.split(",") if args.conditions else spec["conditions"]
    if not set(layouts) <= set(spec["layouts"]) or not set(conditions) <= set(spec["conditions"]):
        raise ValueError("Unknown layout/condition")
    root = (ROOT/args.output).resolve()
    if not root.is_relative_to(ROOT/"output") or root.exists():
        raise ValueError("Choose a new, absent directory inside output/")
    root.mkdir(parents=True)
    bpy.context.preferences.filepaths.save_version = 0
    all_sequences = []
    for layout_index, layout in enumerate(layouts):
        for blocked in (False, True):
            for condition in conditions:
                identifier = f"{layout}-{'blocked' if blocked else 'clear'}-{condition}"
                folder = root/identifier
                folder.mkdir()
                bpy.ops.wm.read_factory_settings(use_empty=True)
                scene = bpy.context.scene
                scene.render.engine = "BLENDER_EEVEE" if bpy.app.version >= (5, 0, 0) else "BLENDER_EEVEE_NEXT"
                scene.render.resolution_x, scene.render.resolution_y = spec["width"], spec["height"]
                scene.render.resolution_percentage = 100
                scene.render.image_settings.file_format = "PNG"
                scene.render.image_settings.color_mode = "RGB"
                scene.render.fps = spec["fps"]
                scene.frame_start, scene.frame_end = 1, spec["frames"]
                scene.view_settings.view_transform = "AgX"
                scene.world = bpy.data.worlds.new("environment")
                scene.world.use_nodes = True
                night = condition in {"lowlight", "mixed"}
                wet = condition in {"rain", "mixed"}
                shake = condition in {"shake", "mixed"}
                bg = scene.world.node_tree.nodes.get("Background")
                bg.inputs["Color"].default_value = (.55, .65, .8, 1)
                bg.inputs["Strength"].default_value = .06/spec["severity"] if night else .35
                movers = build(layout, blocked, wet)
                cross_scale = spec.get('geometry', {}).get('crossTrackScale', 1)
                for obj in scene.objects:
                    if obj.type == 'MESH':
                        obj.location.x *= cross_scale
                        obj.scale.x *= cross_scale
                controls = spec.get('materials', {})
                for mat in bpy.data.materials:
                    if not mat.use_nodes:
                        continue
                    for node in mat.node_tree.nodes:
                        if node.type == 'TEX_NOISE':
                            node.inputs['Scale'].default_value = controls.get('textureScale', 14)
                        elif node.type == 'BUMP':
                            node.inputs['Strength'].default_value = controls.get('bumpStrength', .12)
                        elif node.type == 'BSDF_PRINCIPLED':
                            rough = node.inputs['Roughness']
                            rough.default_value = min(1, rough.default_value * controls.get('roughnessMultiplier', 1))
                context_assets = add_urban_context((ROOT/args.urban_assets).resolve(), layout_index) if args.urban_assets and layout in {"courtyard", "shop", "sidewalk", "pedestrian"} else []
                locations = {o.name: o.location.copy() for o in movers}
                bpy.ops.object.light_add(type="AREA", location=(0, 1, 3))
                bpy.context.object.data.energy = 35/spec["severity"] if night else 260
                bpy.context.object.data.size = 4
                bpy.ops.object.light_add(type="AREA", location=(0, 6, 3))
                bpy.context.object.data.energy = 22/spec["severity"] if night else 180
                bpy.context.object.data.size = 4
                bpy.ops.object.camera_add()
                camera = bpy.context.object
                camera.name = "synthetic-phone-camera"
                camera.data.lens = spec["camera"]["lensMm"]
                camera.data.sensor_width = spec["camera"]["sensorWidthMm"]
                camera.data.sensor_fit = "HORIZONTAL"
                camera.rotation_mode = "QUATERNION"
                scene.camera = camera
                frames = []
                for index in range(spec["frames"]):
                    t = index/spec["fps"]
                    pos, q = camera_pose(t, spec, shake)
                    camera.location, camera.rotation_quaternion = pos, q
                    camera.keyframe_insert(data_path="location", frame=index+1)
                    camera.keyframe_insert(data_path="rotation_quaternion", frame=index+1)
                    for o in movers:
                        o.location = locations[o.name] + Vector((0, -.7*t, 0))
                        o.keyframe_insert(data_path="location", frame=index+1)
                bpy.ops.wm.save_as_mainfile(filepath=str(folder/"scene.blend"), compress=True)
                for index in range(spec["frames"]):
                    scene.frame_set(index+1)
                    bpy.context.view_layer.update()
                    path = folder/f"{index:04d}-render.png"
                    scene.render.filepath = str(path)
                    bpy.ops.render.render(write_still=True)
                    deps = bpy.context.evaluated_depsgraph_get()
                    proj = camera.calc_matrix_camera(deps, x=spec["width"], y=spec["height"])
                    # Evaluator-only sparse first-return witnesses. Never runtime inputs.
                    visible, samples = 0, 0
                    q = camera.matrix_world.to_quaternion()
                    for row in range(0, spec["height"], 6):
                        for col in range(spec["width"]//3, 2*spec["width"]//3, 4):
                            ray = Vector(((2*(col+.5)/spec["width"]-1)/proj[0][0],
                                          (1-2*(row+.5)/spec["height"])/proj[1][1], -1)).normalized()
                            hit, _, _, _, o, _ = scene.ray_cast(deps, camera.location, q@ray, distance=15)
                            samples += 1
                            if hit and o.get("hazard", False):
                                visible += 1
                    frames.append({"frameId": index+1, "offsetUs": round(index/spec["fps"]*1e6),
                                   "render": {"path": path.relative_to(root).as_posix(), "sha256": sha(path)},
                                   "cameraPositionM": list(camera.location), "cameraQuaternionWxyz": list(q),
                                   "visibleHazardWitnesses": visible, "witnessSamples": samples})
                duration = (spec["frames"]-1)/spec["fps"]
                sensors = [sensor_sample(i/spec["sensorHz"], spec, shake)
                           for i in range(round(duration*spec["sensorHz"])+1)]
                all_sequences.append({"id": identifier, "layout": layout, "pair": layout,
                    "physicalHazard": blocked, "condition": condition,
                    "seed": spec["seed"]+layout_index, "frames": frames, "sensors": sensors,
                    "contextAssets": context_assets,
                    "scene": {"path": (folder/"scene.blend").relative_to(root).as_posix(), "sha256": sha(folder/"scene.blend")}})
                save(root/"render-progress.json", {"completedSequences": len(all_sequences), "lastSequence": identifier})
                print(f"SIMULATION_RENDERED {identifier} {len(frames)}", flush=True)
    save(root/"render-manifest.json", {"schemaVersion": 1, "corpusId": spec["corpusId"],
        "spec": spec, "smoke": args.smoke, "blenderVersion": bpy.app.version_string,
        "generatorSha256": sha(__file__), "specValidatorSha256": sha(Path(__file__).with_name('experiment_spec.py')),
        "specSha256": sha(spec_path), "effectiveSpecSha256": hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest(),
        "promotionAllowed": False,
        "scope": spec["scope"], "sequences": all_sequences})


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--spec", help="Versioned JSON camera/geometry/material experiment specification")
    p.add_argument("--smoke", action="store_true")
    p.add_argument("--layouts")
    p.add_argument("--conditions")
    p.add_argument("--frames", type=int)
    p.add_argument("--severity", type=float)
    p.add_argument("--urban-assets", help="Optional local folder of building-*.fbx background assets")
    generate(p.parse_args(argv))

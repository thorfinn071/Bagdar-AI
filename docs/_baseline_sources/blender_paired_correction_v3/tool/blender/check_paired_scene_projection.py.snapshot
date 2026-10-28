"""Check exported observations against animated Blender first-return raycasts."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"

def pgm(path, dtype, maximum):
    with path.open("rb") as stream:
        assert stream.readline().strip() == b"P5"
        w, h = map(int, stream.readline().split())
        assert int(stream.readline()) == maximum
        return np.frombuffer(stream.read(), dtype=dtype).reshape(h, w)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--root", default=str(CORPUS))
parser.add_argument("--pilot", action="store_true")
args = parser.parse_args(argv)
root = Path(args.root).resolve()
manifest = json.loads((root / "corpus-manifest.json").read_text(encoding="utf-8"))
assert root.is_relative_to(ROOT) and manifest["pilotOnly"] == args.pilot
sequences = manifest["sequences"]
count = 0
for seq in sequences:
    bpy.ops.wm.open_mainfile(filepath=str(root / seq["scene"]["path"]))
    scene, camera = bpy.context.scene, bpy.context.scene.camera
    labels = json.loads((root / seq["annotations"]["path"]).read_text(encoding="utf-8"))
    parameters = labels["parameters"]
    if parameters["kind"] == "doorway":
        left, right, lintel = [bpy.data.objects[n] for n in ("door-side--1", "door-side-1", "lintel")]
        assert abs((right.location.x - right.dimensions.x / 2) - (left.location.x + left.dimensions.x / 2) - parameters["openingWidthM"]) < 1e-6
        assert abs(lintel.location.z - lintel.dimensions.z / 2 - parameters["openingHeightM"]) < 1e-6
    if parameters["kind"] == "drop":
        near, lower = bpy.data.objects["floor-near"], bpy.data.objects["floor-lower"]
        assert abs(near.location.y + near.dimensions.y / 2 - parameters["edgeY"]) < 1e-6
        assert abs(lower.location.z + lower.dimensions.z / 2 + parameters["dropM"]) < 1e-6
    for frame in (seq["frames"][0], seq["frames"][5], seq["frames"][-1]):
        scene.frame_set(frame["frameIndex"] + 1)
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        pose = frame["cameraPose"]
        assert np.allclose(camera.location, pose["locationMetres"], atol=1e-7)
        assert np.allclose(camera.rotation_euler, pose["rotationEulerRadians"], atol=1e-7)
        paths = {}
        for kind in ("rgb", "depth", "semantic"):
            asset = frame[kind]
            path = (root / asset["path"]).resolve()
            assert path.is_relative_to(root) and hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"]
            paths[kind] = path
        depth = pgm(paths["depth"], ">u2", 65535)
        h, w = depth.shape
        projection = camera.calc_matrix_camera(deps, x=w, y=h, scale_x=1, scale_y=1)
        assert abs(projection[0][0] * w / 2 - pose["fx"]) < 1e-5
        mask = pgm(paths["semantic"], "uint8", 255)
        for y in range(7, h, 27):
            for x in range(9, w, 31):
                local = Vector(((x + .5 - pose["cx"]) / pose["fx"], -(y + .5 - pose["cy"]) / pose["fy"], -1)).normalized()
                hit, point, _, _, obj, _ = scene.ray_cast(deps, camera.location, camera.matrix_world.to_quaternion() @ local, distance=20)
                assert hit == bool(depth[y, x])
                if hit:
                    assert abs((point - camera.location).length * 1000 - int(depth[y, x])) <= .51
                    assert int(obj.get("semantic_id", 0)) == mask[y, x]
                count += 1
    print("PROJECTION_CHECK " + seq["sceneId"], flush=True)
print(f"Projection, pose, first-return depth and mask: {count} sampled rays passed")

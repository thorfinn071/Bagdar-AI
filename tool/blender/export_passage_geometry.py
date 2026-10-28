"""Export conservative full-scene geometry, never camera visibility or labels.

Run Blender with the pinned contextual scene. Nothing is saved to scene.blend.
The output is an omniscient SYNTHETIC geometry oracle, not a depth sensor.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
import bmesh


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def volume(camera_xy: list[float]) -> dict:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    boxes, floors = [], []
    for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            vertices = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            if not vertices:
                raise ValueError("Empty mesh in complete geometry oracle")
            lo = [min(point[axis] for point in vertices) for axis in range(3)]
            hi = [max(point[axis] for point in vertices) for axis in range(3)]
            # Convert Blender x/y/z to walking lateral/forward/height.
            lo[0] -= camera_xy[0]
            hi[0] -= camera_xy[0]
            lo[1] -= camera_xy[1]
            hi[1] -= camera_xy[1]
            if hi[0] < -2 or lo[0] > 2 or hi[1] < 0.15 or lo[1] > 4:
                continue
            bounds = {
                "leftM": round(lo[0], 6), "rightM": round(hi[0], 6),
                "startM": round(lo[1], 6), "endM": round(hi[1], 6),
                "bottomM": round(lo[2], 6), "topM": round(hi[2], 6),
            }
            # Only a verified axis-aligned solid box with a flat near-zero top
            # can certify its entire footprint as floor. No semantic IDs/names.
            corner_box = len(vertices) == 8 and all(
                all(abs(point[axis] - value) < 1e-5 for axis, value in enumerate(corner))
                for corner in (
                    (x + camera_xy[0], y + camera_xy[1], z)
                    for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])
                ) for point in [min(vertices, key=lambda vertex: sum((vertex[i] - corner[i]) ** 2 for i in range(3)))]
            )
            # Vertices/bounds alone don't prove the floor surface exists: a
            # mesh may retain all corners after its top polygon is removed.
            floor_face = False
            for polygon in mesh.polygons:
                points = [vertices[index] for index in polygon.vertices]
                if len(points) != 4 or any(abs(point.z - hi[2]) > 1e-5 for point in points):
                    continue
                if all(
                    (abs(points[index].x - points[(index + 1) % 4].x) < 1e-5)
                    != (abs(points[index].y - points[(index + 1) % 4].y) < 1e-5)
                    for index in range(4)
                ):
                    floor_face = True
                    break
            if corner_box and floor_face and hi[2] <= 0.02 and lo[2] < hi[2]:
                floors.append(bounds)
            elif hi[2] > 0:
                boxes.append(bounds)
        finally:
            evaluated.to_mesh_clear()
    return {
        "scope": "complete_scene_geometry_oracle",
        "measurementErrorM": 0.001,
        "domain": {"leftM": -2.0, "rightM": 2.0, "startM": 0.15, "endM": 4.0, "topM": 3.0},
        "occupiedBounds": boxes,
        "floorBounds": floors,
    }


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    repo = Path(__file__).resolve().parents[2]
    root = repo / "test/fixtures/spatial_safety/blender-context-v3"
    scene_path = root / "scene.blend"
    if Path(bpy.data.filepath).resolve() != scene_path.resolve():
        raise ValueError("Load the pinned contextual scene.blend")
    manifest = json.loads((root / "corpus-manifest.json").read_text(encoding="utf-8"))
    if digest(scene_path) != manifest["scene"]["sha256"]:
        raise ValueError("Pinned scene hash mismatch")
    frames = []
    for asset in manifest["assets"]:
        for frame in asset["frames"]:
            # Replay the renderer's physical rider movement. Semantic object
            # metadata is used only to move the source scene, never exported
            # to or interpreted by the clearance evaluator.
            moving = [obj for obj in bpy.context.scene.objects if obj.get("semantic_id") == 10] if asset["sceneId"] == "context-crossing-rider" else []
            originals_x = [obj.location.x for obj in moving]
            try:
                for obj in moving:
                    obj.location.x += (-0.18, 0.0, 0.18)[frame["frameIndex"]]
                bpy.context.view_layer.update()
                frames.append({
                    "sceneId": asset["sceneId"], "frameIndex": frame["frameIndex"],
                    "capturedOffsetMs": frame["capturedOffsetMs"],
                    "rgbSha256": frame["rgb"]["sha256"],
                    "geometry": volume(frame["cameraPose"]["locationMetres"][:2]),
                })
            finally:
                for obj, x in zip(moving, originals_x):
                    obj.location.x = x
                bpy.context.view_layer.update()
    # Contrasts are changes to actual meshes, not rewritten expected labels.
    # They have no rendered RGB and are used with procedural adapter inputs.
    portal = [bpy.data.objects[name] for name in ("door-wall-left", "door-wall-right", "door-lintel")]
    originals = [(obj.location.copy(), obj.scale.copy()) for obj in portal]
    origin = next(asset for asset in manifest["assets"] if asset["sceneId"] == "context-doorway")["frames"][0]["cameraPose"]["locationMetres"][:2]
    contrasts = []
    for variant in ("narrow", "low-lintel", "offset", "interior-pole", "floor-box", "missing-floor-face"):
        added = None
        altered_floor = None
        original_mesh = None
        try:
            if variant == "narrow":
                portal[0].location.x += 0.30
                portal[1].location.x -= 0.30
            elif variant == "low-lintel":
                portal[2].location.z -= 0.50
            elif variant == "offset":
                for obj in portal:
                    obj.location.x += 0.80
            elif variant == "missing-floor-face":
                for obj in bpy.context.scene.objects:
                    if obj.type != "MESH":
                        continue
                    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
                    if points and min(point.x for point in points) < origin[0] - 2 and max(point.x for point in points) > origin[0] + 2 and -0.05 <= max(point.z for point in points) <= 0.02:
                        altered_floor = obj
                        break
                if altered_floor is None:
                    raise ValueError("Missing base floor for mesh contrast")
                original_mesh = altered_floor.data
                altered_floor.data = original_mesh.copy()
                mesh_edit = bmesh.new()
                try:
                    mesh_edit.from_mesh(altered_floor.data)
                    top_face = max(mesh_edit.faces, key=lambda face: face.normal.z)
                    bmesh.ops.delete(mesh_edit, geom=[top_face], context="FACES_ONLY")
                    mesh_edit.to_mesh(altered_floor.data)
                finally:
                    mesh_edit.free()
            else:
                bpy.ops.mesh.primitive_cube_add(location=(origin[0], 3.0, 0.8 if variant == "interior-pole" else 0.15))
                added = bpy.context.object
                added.scale = (0.04, 0.04, 0.8) if variant == "interior-pole" else (0.35, 0.2, 0.15)
            bpy.context.view_layer.update()
            contrasts.append({"id": variant, "geometry": volume(origin)})
        finally:
            if added is not None:
                bpy.data.objects.remove(added, do_unlink=True)
            if altered_floor is not None:
                temporary_mesh = altered_floor.data
                altered_floor.data = original_mesh
                bpy.data.meshes.remove(temporary_mesh)
            for obj, (location, scale) in zip(portal, originals):
                obj.location, obj.scale = location, scale
            bpy.context.view_layer.update()
    report = {
        "schemaVersion": 1, "scope": "synthetic_full_scene_geometry_not_camera_visibility",
        "sceneSha256": digest(scene_path),
        "corpusManifestSha256": digest(root / "corpus-manifest.json"),
        "exporterSha256": digest(Path(__file__)),
        "frames": frames, "contrasts": contrasts,
    }
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    output = (repo / args.output).resolve()
    if repo not in output.parents:
        raise ValueError("Output must remain in the repository")
    if args.check:
        if output.read_text(encoding="utf-8") != rendered:
            raise ValueError("Synthetic geometry export drift")
        print(f"Geometry oracle matches: {len(frames)} frames, {len(contrasts)} contrasts")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(f"Wrote geometry oracle: {len(frames)} frames, {len(contrasts)} contrasts")


if __name__ == "__main__":
    main()

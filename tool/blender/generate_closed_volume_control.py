"""Versioned scene-only control; reuses the sealed first-return exporter."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_volume_holdout as base
import bpy

OUTPUT = base.ROOT / 'scratch/closed-volume-control-2026-10-11'
SOURCES = base.SOURCES + [
    'tool/blender/generate_closed_volume_control.py',
    'tool/blender/closed_volume_control_spec_v1.json',
    'docs/closed-volume-control-protocol-2026-10-11.md',
]


def closed_scene_setup(entry, case, spec):
    scene, primary, moving, views = original_setup(entry, case, spec)
    for name in ('room-left', 'room-right'):
        bpy.data.objects[name].location.z = 1.69
        bpy.data.objects[name].scale.z = 1.69
    bpy.context.view_layer.update()
    return scene, primary, moving, views


original_setup = base.scene_setup
base.scene_setup = closed_scene_setup
base.OUTPUT = OUTPUT
base.CORPUS = OUTPUT / 'corpus'
base.OPTICS = OUTPUT / 'optical'
base.SPEC = base.ROOT / 'tool/blender/closed_volume_control_spec_v1.json'
base.SOURCES = SOURCES
original_save_json = base.g.save_json


def save_control_json(path, value):
    if path == base.CORPUS / 'manifest.json':
        value['corpusId'] = 'closed-volume-control-2026-10-11'
        value['scope'] = 'related diagnostic scene controls; not independent holdout'
    original_save_json(path, value)


base.g.save_json = save_control_json

if __name__ == '__main__':
    base.main()

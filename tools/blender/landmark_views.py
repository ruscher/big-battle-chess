"""Orthographic front/side views with a metric grid, for placing skeleton landmarks.

    blender -b --factory-startup --python tools/blender/landmark_views.py -- <model> <out_prefix> <face_fix_deg> <height_m>

The model is normalised exactly like build_characters.normalize() (rotation
about Z, scaled to height, feet on the ground, centred), then rendered with
an orthographic camera whose frame maps 1 px to a known size. A JSON file
with the mapping is written so tools can convert pixels to metres.
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
src, prefix, fix_deg, target_h = argv[0], argv[1], float(argv[2]), float(argv[3])

bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(src)[1].lower()
if ext in (".glb", ".gltf"):
    bpy.ops.import_scene.gltf(filepath=src)
else:
    bpy.ops.import_scene.fbx(filepath=src)

import build_characters as bc  # noqa: E402

objs = list(bpy.data.objects)
bc.normalize(objs, target_h, fix_deg)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
size = 1200
scene.render.resolution_x = size
scene.render.resolution_y = size
extent = target_h * 1.15
cam_data = bpy.data.cameras.new("Ortho")
cam_data.type = "ORTHO"
cam_data.ortho_scale = extent
cam = bpy.data.objects.new("Ortho", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
center = Vector((0, 0, target_h * 0.5))
for label, loc in (("front", Vector((0, -10, 0))), ("side", Vector((10, 0, 0)))):
    cam.location = center + loc
    cam.rotation_euler = (-loc).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{prefix}_{label}.png"
    bpy.ops.render.render(write_still=True)
with open(prefix + "_views.json", "w") as f:
    json.dump({"size": size, "extent": extent, "center_z": center.z}, f)
print("VIEWS", prefix)

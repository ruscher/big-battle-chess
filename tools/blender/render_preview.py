"""Renders review images (front, three-quarter, side, back) of a model.

    blender -b --factory-startup --python tools/blender/render_preview.py -- <model> <out_prefix> [eevee|workbench] [size]

Models are framed automatically from their bounding box, lit with a
three-point rig and rendered with textures, so materials and missing maps
are visible. Output: <out_prefix>_front.png, _34.png, _side.png, _back.png.
"""
import bpy
import math
import os
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, prefix = argv[0], argv[1]
engine = argv[2] if len(argv) > 2 else "eevee"
size = int(argv[3]) if len(argv) > 3 else 900
ext = os.path.splitext(src)[1].lower()

if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src)
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=src)

scene = bpy.context.scene
meshes = [o for o in scene.objects if o.type == "MESH" and o.visible_get()]
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
        hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
center = (lo + hi) * 0.5
height = max(hi.z - lo.z, 1e-3)
radius = max((hi - lo).length * 0.5, 1e-3)

if engine == "workbench":
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
else:
    for name in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = name
            break
        except TypeError:
            continue
world = bpy.data.worlds.new("Preview") if scene.world is None else scene.world
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.05, 0.05, 0.06, 1)
    bg.inputs[1].default_value = 0.6
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.film_transparent = False
scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"

def light(name, kind, energy, loc, color=(1, 1, 1), size_l=2.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size_l * radius
    ob = bpy.data.objects.new(name, data)
    ob.location = center + Vector(loc) * radius
    d = center - ob.location
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)

scale_e = radius * radius
light("Key", "AREA", 900 * scale_e, (-2.2, -2.6, 2.0), (1.0, 0.93, 0.85))
light("Fill", "AREA", 300 * scale_e, (2.8, -1.4, 0.8), (0.75, 0.82, 1.0))
light("Rim", "AREA", 700 * scale_e, (0.5, 3.0, 2.4), (1.0, 0.95, 0.9))

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 70
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
dist = radius * 3.1
views = {"front": -90, "34": -55, "side": 0, "back": 90}
# Models may face -Y (Blender convention for glTF/FBX characters).
for label, deg in views.items():
    a = math.radians(deg)
    cam.location = center + Vector((math.cos(a) * dist, math.sin(a) * dist, height * 0.08))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{prefix}_{label}.png"
    bpy.ops.render.render(write_still=True)
print("PREVIEW done", prefix, "height", round(height, 3))

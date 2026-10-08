"""Blender model audit: writes a JSON integrity report for a 3D file.

    blender -b --factory-startup --python tools/blender/audit_model.py -- <model> <report.json>

Supports .blend (opened), .glb/.gltf, .fbx and .obj (imported into an empty
scene). Reports meshes, triangles, UV layers, materials and their image
textures, armatures, bones, actions, shape keys, dimensions, and simple
topology warnings (loose vertices, zero-area faces, missing UVs).
"""
import bpy
import bmesh
import json
import os
import sys
import time

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: -- <model> <report.json>")
src, out = argv[0], argv[1]
ext = os.path.splitext(src)[1].lower()
t0 = time.time()

if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=src)
    else:
        raise SystemExit("unsupported format " + ext)

depsgraph = bpy.context.evaluated_depsgraph_get()
report = {"file": os.path.basename(src), "format": ext, "import_seconds": round(time.time() - t0, 1),
          "meshes": [], "armatures": [], "actions": [], "materials": [], "images": [], "warnings": []}
total_tris = 0
mins = [1e9] * 3
maxs = [-1e9] * 3
for obj in bpy.data.objects:
    if obj.type == "MESH":
        me = obj.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total_tris += tris
        bm = bmesh.new()
        bm.from_mesh(me)
        loose = sum(1 for v in bm.verts if not v.link_edges)
        degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-12)
        non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
        for corner in obj.bound_box:
            w = obj.matrix_world @ __import__("mathutils").Vector(corner)
            for i in range(3):
                mins[i] = min(mins[i], w[i])
                maxs[i] = max(maxs[i], w[i])
        entry = {
            "name": obj.name, "verts": len(me.vertices), "tris": tris,
            "uv_layers": [uv.name for uv in me.uv_layers],
            "materials": [s.material.name if s.material else None for s in obj.material_slots],
            "vertex_groups": len(obj.vertex_groups),
            "armature_modifier": any(m.type == "ARMATURE" for m in obj.modifiers),
            "parent": obj.parent.name if obj.parent else None,
            "shape_keys": len(me.shape_keys.key_blocks) if me.shape_keys else 0,
            "loose_verts": loose, "degenerate_faces": degenerate, "non_manifold_edges": non_manifold,
        }
        if not me.uv_layers:
            report["warnings"].append(f"{obj.name}: no UV map")
        report["meshes"].append(entry)
    elif obj.type == "ARMATURE":
        bones = obj.data.bones
        report["armatures"].append({
            "name": obj.name, "bones": len(bones),
            "sample_bones": [b.name for b in bones][:60],
            "scale": list(obj.scale),
        })

for act in bpy.data.actions:
    report["actions"].append({"name": act.name, "frame_range": list(act.frame_range),
                              "fcurves": len(getattr(act, "fcurves", [])) if hasattr(act, "fcurves") else None})

for mat in bpy.data.materials:
    textures = []
    if mat.use_nodes and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                links = [l.to_socket.name for l in n.outputs[0].links] if n.outputs else []
                textures.append({"image": n.image.name, "to": links})
    report["materials"].append({"name": mat.name, "textures": textures})

for img in bpy.data.images:
    report["images"].append({"name": img.name, "size": list(img.size), "filepath": img.filepath,
                             "packed": img.packed_file is not None, "has_data": img.has_data})
    if img.source == "FILE" and not img.packed_file and img.filepath and not os.path.exists(bpy.path.abspath(img.filepath)):
        report["warnings"].append(f"missing image file: {img.filepath}")

report["total_tris"] = total_tris
report["dimensions"] = [round(maxs[i] - mins[i], 4) for i in range(3)] if total_tris else None
report["bbox_min"] = [round(v, 4) for v in mins] if total_tris else None
report["unit_scale"] = bpy.context.scene.unit_settings.scale_length

with open(out, "w") as f:
    json.dump(report, f, indent=1)
print(f"AUDIT {report['file']}: {len(report['meshes'])} meshes, {total_tris} tris, "
      f"{len(report['armatures'])} armatures, {len(report['actions'])} actions, dims {report['dimensions']}")

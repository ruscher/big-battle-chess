"""Big Battle Chess character build pipeline (Blender 5.x, no add-ons).

    blender -b --factory-startup --python tools/blender/build_characters.py -- <archetype> [--src DIR] [--out DIR]

Archetypes: rook (Iron Juggernaut), king (Sun Knight), knight_warrior
(Medieval Knight). Each build:
  1. imports the source from build/asset_work (never the originals),
  2. normalizes scale (metres), orientation (faces -Y = +Z in Godot) and
     origin (feet at 0),
  3. wires PBR materials (base colour, normal, occlusion/roughness/metallic),
  4. rigs when needed (shared humanoid skeleton + region-aware skinning),
  5. builds LOD variants (board / arena) by controlled decimation,
  6. saves an editable .blend and exports glTF (separate shared textures).

The outputs go to assets/characters_ext/<archetype>/ which is git-ignored:
third-party derived meshes are never committed (see docs/ASSET_LICENSES.md).
"""
import bpy
import bmesh
import json
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORK = os.path.join(ROOT, "build", "asset_work")
OUT = os.path.join(ROOT, "assets", "characters_ext")


def log(*a):
    print("[build]", *a, flush=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def apply_transforms(objs):
    select_only(objs)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def load_image(path, non_color=False):
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def pbr_material(name, base, normal=None, orm=None, metallic=None, roughness=None):
    """Principled material the glTF exporter maps 1:1 (ORM packed: R=AO, G=rough, B=metal)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = load_image(base)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if normal:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = load_image(normal, True)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if orm:
        otex = nt.nodes.new("ShaderNodeTexImage")
        otex.image = load_image(orm, True)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(otex.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        # glTF occlusion: exporter looks for a "glTF Material Output" group.
        grp = _gltf_settings_group()
        gnode = nt.nodes.new("ShaderNodeGroup")
        gnode.node_tree = grp
        nt.links.new(sep.outputs["Red"], gnode.inputs["Occlusion"])
    else:
        if metallic:
            mtex = nt.nodes.new("ShaderNodeTexImage")
            mtex.image = load_image(metallic, True)
            nt.links.new(mtex.outputs["Color"], bsdf.inputs["Metallic"])
        if roughness:
            rtex = nt.nodes.new("ShaderNodeTexImage")
            rtex.image = load_image(roughness, True)
            nt.links.new(rtex.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def _gltf_settings_group():
    name = "glTF Material Output"
    if name in bpy.data.node_groups:
        return bpy.data.node_groups[name]
    g = bpy.data.node_groups.new(name, "ShaderNodeTree")
    g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    return g


def make_orm(ao_path, metal_smooth_path, out_path):
    """Unity AO + MetallicSmoothness (R=metal, A=smooth) -> glTF ORM."""
    if os.path.exists(out_path):
        return out_path
    ao = load_image(ao_path, True)
    ms = load_image(metal_smooth_path, True)
    w, h = ms.size
    a = np.empty(w * h * 4, dtype=np.float32)
    ao.scale(w, h) if tuple(ao.size) != (w, h) else None
    ao.pixels.foreach_get(a)
    ao_px = a.reshape(-1, 4)[:, 0].copy()
    ms.pixels.foreach_get(a)
    msp = a.reshape(-1, 4)
    out = np.empty((w * h, 4), dtype=np.float32)
    out[:, 0] = ao_px
    out[:, 1] = 1.0 - msp[:, 3]
    out[:, 2] = msp[:, 0]
    out[:, 3] = 1.0
    img = bpy.data.images.new(os.path.basename(out_path), w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(out.ravel())
    img.filepath_raw = out_path
    img.file_format = "PNG"
    img.save()
    return out_path


def normalize(objs, target_height, face_fix_deg=0.0):
    """Rotate about Z, scale to target height, put feet on the ground, centre XY."""
    roots = [o for o in objs if o.parent is None]
    if face_fix_deg:
        for o in roots:
            o.rotation_euler.z += math.radians(face_fix_deg)
    bpy.context.view_layer.update()
    lo, hi = bbox([o for o in objs if o.type == "MESH"])
    s = target_height / (hi.z - lo.z)
    for o in roots:
        o.scale *= s
    bpy.context.view_layer.update()
    lo, hi = bbox([o for o in objs if o.type == "MESH"])
    shift = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    for o in roots:
        o.location += shift
    bpy.context.view_layer.update()
    apply_transforms(roots + [o for o in objs if o.parent is not None])
    return s


def decimate(obj, ratio):
    if ratio >= 0.999:
        return
    mod = obj.modifiers.new("LOD", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    # Keep UV seams and skin weights; decimate before the armature modifier.
    while obj.modifiers[0] != mod:
        obj.modifiers.move(obj.modifiers.find(mod.name), 0)
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)


def tri_count(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH")


def export_gltf(path, objs, tex_dir="textures"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    select_only(objs)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLTF_SEPARATE", export_texture_dir=tex_dir,
        use_selection=True, export_apply=False, export_animations=False,
        export_skins=True, export_yup=True, export_image_format="AUTO",
        export_materials="EXPORT", export_tangents=True,
    )
    log("exported", os.path.relpath(path, ROOT), tri_count([o for o in objs if o.type == "MESH"]), "tris")


def save_work_blend(name):
    """Editable working file, kept outside res:// so Godot does not import it."""
    d = os.path.join(ROOT, "build", "character_blend")
    os.makedirs(d, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, f"{name}_work.blend"))


def report(name, data):
    os.makedirs(os.path.join(OUT, name), exist_ok=True)
    with open(os.path.join(OUT, name, "build_report.json"), "w") as f:
        json.dump(data, f, indent=1)


# ---------------------------------------------------------------------------
# Rook — Iron Juggernaut (rigged by its author, UE-style 88-bone skeleton)
# ---------------------------------------------------------------------------

def build_rook():
    src = os.path.join(WORK, "iron_juggernaut")
    tex = os.path.join(src, "Texture", "Unity")
    out_dir = os.path.join(OUT, "rook")
    texout = os.path.join(out_dir, "textures")
    os.makedirs(texout, exist_ok=True)
    sets = {}
    for part in ("Armor", "Cloth"):
        for tile in ("1001", "1002"):
            base = os.path.join(tex, f"T_{part}_AlbedoTransparency_Utility - sRGB - Texture.{tile}.png")
            normal = os.path.join(tex, f"T_{part}_Normal_Utility - Raw.{tile}.png")
            orm = make_orm(os.path.join(tex, f"T_{part}_AO_Utility - Raw.{tile}.png"),
                           os.path.join(tex, f"T_{part}_MetallicSmoothness_Utility - Raw.{tile}.png"),
                           os.path.join(texout, f"rook_{part.lower()}_{tile}_orm.png"))
            sets[(part, tile)] = (base, normal, orm)
    results = {}
    for lod, fbx in (("board", "LowPoly.fbx"), ("arena", "MidPoly.fbx")):
        reset()
        bpy.ops.import_scene.fbx(filepath=os.path.join(src, fbx))
        objs = list(bpy.data.objects)
        arm = next(o for o in objs if o.type == "ARMATURE")
        normalize(objs, 1.92)
        mats = {
            "M_Armor1": pbr_material("rook_armor_a", *sets[("Armor", "1001")]),
            "M_Armor2": pbr_material("rook_armor_b", *sets[("Armor", "1002")]),
            "M_Cloth1": pbr_material("rook_cloth_a", *sets[("Cloth", "1001")]),
            "M_Cloth2": pbr_material("rook_cloth_b", *sets[("Cloth", "1002")]),
        }
        dark = bpy.data.materials.get("M_Dark")
        if dark:
            dark.use_nodes = True
            b = dark.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Base Color"].default_value = (0.02, 0.02, 0.025, 1)
                b.inputs["Roughness"].default_value = 0.6
        for o in meshes():
            for slot in o.material_slots:
                if slot.material and slot.material.name in mats:
                    slot.material = mats[slot.material.name]
            for p in o.data.polygons:
                p.use_smooth = True
        arm.name = "Skeleton"
        path = os.path.join(out_dir, f"rook_{lod}.gltf")
        export_gltf(path, objs)
        if lod == "arena":
            save_work_blend("rook")
        results[lod] = {"tris": tri_count(meshes()), "bones": len(arm.data.bones)}
    report("rook", {"source": "Iron Juggernaut (LowPoly/MidPoly FBX)", "lods": results})


# ---------------------------------------------------------------------------
# Unrigged models: original humanoid skeleton + region-aware skinning
# ---------------------------------------------------------------------------

BONES = [
    # name, head landmark, tail landmark, parent, thickness (weighting radius, m)
    ("pelvis", "pelvis", "spine", None, 0.16),
    ("spine_01", "spine", "chest", "pelvis", 0.17),
    ("spine_02", "chest", "neck", "spine_01", 0.19),
    ("neck", "neck", "head", "spine_02", 0.08),
    ("head", "head", "head_top", "neck", 0.13),
    ("clavicle_l", "neck", "shoulder_l", "spine_02", 0.08),
    ("upperarm_l", "shoulder_l", "elbow_l", "clavicle_l", 0.085),
    ("lowerarm_l", "elbow_l", "wrist_l", "upperarm_l", 0.075),
    ("hand_l", "wrist_l", "hand_end_l", "lowerarm_l", 0.06),
    ("clavicle_r", "neck", "shoulder_r", "spine_02", 0.08),
    ("upperarm_r", "shoulder_r", "elbow_r", "clavicle_r", 0.085),
    ("lowerarm_r", "elbow_r", "wrist_r", "upperarm_r", 0.075),
    ("hand_r", "wrist_r", "hand_end_r", "lowerarm_r", 0.06),
    ("thigh_l", "hip_l", "knee_l", "pelvis", 0.11),
    ("calf_l", "knee_l", "ankle_l", "thigh_l", 0.09),
    ("foot_l", "ankle_l", "toe_l", "calf_l", 0.07),
    ("thigh_r", "hip_r", "knee_r", "pelvis", 0.11),
    ("calf_r", "knee_r", "ankle_r", "thigh_r", 0.09),
    ("foot_r", "ankle_r", "toe_r", "calf_r", 0.07),
]
# Bones that must never influence the opposite side of the body.
SIDE = {n: (1 if n.endswith("_l") else -1) for n, *_ in BONES if n.endswith(("_l", "_r"))}


def mirror(lm):
    """Fill *_r landmarks from *_l (x mirrored) when only one side is given."""
    out = dict(lm)
    for k, v in lm.items():
        if k.endswith("_l") and k[:-2] + "_r" not in lm:
            out[k[:-2] + "_r"] = (-v[0], v[1], v[2])
    return out


def build_armature(landmarks):
    lm = {k: Vector(v) for k, v in mirror(landmarks).items()}
    data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", data)
    bpy.context.scene.collection.objects.link(arm)
    select_only([arm])
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, h, t, parent, _r in BONES:
        b = data.edit_bones.new(name)
        b.head = lm[h]
        b.tail = lm[t]
        if (b.tail - b.head).length < 1e-3:
            b.tail = b.head + Vector((0, 0, 0.05))
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm, lm


def _segment_distance(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    closest = a + t[:, None] * ab
    return np.linalg.norm(P - closest, axis=1)


def mesh_islands(me):
    """Connected-component id per vertex (numpy array) using edges."""
    n = len(me.vertices)
    parent = np.arange(n)

    def find(i):
        root = i
        while parent[root] != root:
            root = parent[root]
        while parent[i] != root:
            parent[i], i = root, parent[i]
        return root

    edges = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", edges)
    for a, b in edges.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    return np.array([find(i) for i in range(n)])


def vertex_texture_values(mesh_obj, image_path, channel=0):
    """Samples a texture channel at each vertex's (average) UV coordinate."""
    img = load_image(image_path, True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[:, :, channel]
    me = mesh_obj.data
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    vidx = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vidx)
    acc = np.zeros((len(me.vertices), 2))
    cnt = np.zeros(len(me.vertices))
    np.add.at(acc, vidx, uv)
    np.add.at(cnt, vidx, 1)
    uvv = acc / np.maximum(cnt, 1)[:, None]
    xs = np.clip((uvv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    ys = np.clip((uvv[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    return px[ys, xs]


def skin(mesh_obj, arm, lm, regions, power=6.0, max_influences=4, rigid_size=0.22,
         vertex_metal=None, cloth_excludes=(), metal_threshold=0.35, cutoffs=None, smooth_iters=0):
    """Inverse-distance skinning to bone segments, made production-friendly:

    * small mesh islands (armour plates, buckles, rivets) move rigidly: every
      vertex of an island gets the island's average weights;
    * override regions are applied per island (majority vote) so a sword,
      shield or halo never tears in two;
    * "gradient" regions blend bones along height (capes, tabards).

    regions: {"bone": name | {name: w}, "capsule": [a, b, r] | "box": [lo, hi],
              "gradient": [[z, {name: w}], ...], "mode": "island" | "vertex"}
    """
    me = mesh_obj.data
    P = np.array([v.co for v in me.vertices], dtype=np.float64)
    names = [b[0] for b in BONES]
    W = np.zeros((len(P), len(names)))
    for i, (name, h, t, _p, radius) in enumerate(BONES):
        a = np.array(lm[h], dtype=np.float64)
        b = np.array(lm[t], dtype=np.float64)
        d = _segment_distance(P, a, b) / radius
        w = 1.0 / np.power(d + 0.15, power)
        if name in SIDE:
            w[(P[:, 0] * SIDE[name]) < -0.03] = 0.0
        if vertex_metal is not None and name in cloth_excludes:
            w[vertex_metal < metal_threshold] = 0.0
        if cutoffs and name in cutoffs:
            # Hard reach limit: drapery hanging near a limb must not follow it.
            w[d * radius > cutoffs[name]] = 0.0
        W[:, i] = w
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)

    if smooth_iters:
        # Laplacian smoothing over mesh edges spreads joint deformation and
        # removes hard weight seams on fused (sculpted) surfaces.
        edges = np.empty(len(me.edges) * 2, dtype=np.int64)
        me.edges.foreach_get("vertices", edges)
        e = edges.reshape(-1, 2)
        deg = np.zeros(len(P))
        np.add.at(deg, e[:, 0], 1)
        np.add.at(deg, e[:, 1], 1)
        for _ in range(smooth_iters):
            acc = np.zeros_like(W)
            np.add.at(acc, e[:, 0], W[e[:, 1]])
            np.add.at(acc, e[:, 1], W[e[:, 0]])
            W = 0.5 * W + 0.5 * acc / np.maximum(deg, 1)[:, None]
        log(f"  weights smoothed ({smooth_iters} iterations)")

    isl = mesh_islands(me)
    uniq, inverse, counts = np.unique(isl, return_inverse=True, return_counts=True)
    lo = np.full((len(uniq), 3), 1e9)
    hi = np.full((len(uniq), 3), -1e9)
    np.minimum.at(lo, inverse, P)
    np.maximum.at(hi, inverse, P)
    size = np.linalg.norm(hi - lo, axis=1)
    rigid = size[inverse] < rigid_size
    sums = np.zeros((len(uniq), len(names)))
    np.add.at(sums, inverse, W)
    avg = sums / counts[:, None]
    W[rigid] = avg[inverse[rigid]]
    log(f"  islands: {len(uniq)}, rigid vertices: {int(rigid.sum())}/{len(P)}")

    for reg in regions:
        if "capsule" in reg:
            a, b, r = np.array(reg["capsule"][0]), np.array(reg["capsule"][1]), reg["capsule"][2]
            mask = _segment_distance(P, a, b) < r
        else:
            blo, bhi = np.array(reg["box"][0]), np.array(reg["box"][1])
            mask = np.all((P >= blo) & (P <= bhi), axis=1)
        if vertex_metal is not None and "metal_min" in reg:
            mask &= vertex_metal >= reg["metal_min"]
        if vertex_metal is not None and "metal_max" in reg:
            mask &= vertex_metal <= reg["metal_max"]
        if reg.get("mode", "island") == "island":
            frac = np.zeros(len(uniq))
            np.add.at(frac, inverse, mask.astype(np.float64))
            frac /= counts
            mask = frac[inverse] > reg.get("majority", 0.5)
        if "gradient" in reg:
            stops = reg["gradient"]
            zs = np.array([s_[0] for s_ in stops])
            for vi in np.nonzero(mask)[0]:
                z = P[vi, 2]
                k = int(np.clip(np.searchsorted(zs, z) - 1, 0, len(stops) - 2))
                t = float(np.clip((z - zs[k]) / max(zs[k + 1] - zs[k], 1e-6), 0, 1))
                W[vi] = 0.0
                for bn, bw in stops[k][1].items():
                    W[vi, names.index(bn)] += bw * (1 - t)
                for bn, bw in stops[k + 1][1].items():
                    W[vi, names.index(bn)] += bw * t
            label = "gradient"
        else:
            target = reg["bone"] if isinstance(reg["bone"], dict) else {reg["bone"]: 1.0}
            W[mask] = 0.0
            for bn, bw in target.items():
                W[mask, names.index(bn)] = bw
            label = str(list(target))
        log(f"  region {label}: {int(mask.sum())} verts")
    idx = np.argsort(-W, axis=1)[:, max_influences:]
    np.put_along_axis(W, idx, 0.0, axis=1)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    mesh_obj.vertex_groups.clear()
    groups = [mesh_obj.vertex_groups.new(name=n) for n in names]
    for j, g in enumerate(groups):
        col = W[:, j]
        for vi in np.nonzero(col > 1e-4)[0]:
            g.add([int(vi)], float(col[vi]), "REPLACE")
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mesh_obj.parent = arm


def make_orm_from(rough_path, metal_path, out_path, size=2048):
    if os.path.exists(out_path):
        return out_path
    r = load_image(rough_path, True)
    m = load_image(metal_path, True)
    for img in (r, m):
        if tuple(img.size) != (size, size):
            img.scale(size, size)
    buf = np.empty(size * size * 4, dtype=np.float32)
    r.pixels.foreach_get(buf)
    rough = buf.reshape(-1, 4)[:, 0].copy()
    m.pixels.foreach_get(buf)
    metal = buf.reshape(-1, 4)[:, 0].copy()
    out = np.ones((size * size, 4), dtype=np.float32)
    out[:, 1] = rough
    out[:, 2] = metal
    img = bpy.data.images.new(os.path.basename(out_path), size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(out.ravel())
    img.filepath_raw = out_path
    img.file_format = "PNG"
    img.save()
    return out_path


def pose_test_render(arm, prefix):
    """Workbench renders of a test pose to validate skinning in Blender."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    pb = arm.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"
    pb["upperarm_r"].rotation_euler = (math.radians(-70), 0, 0)
    pb["lowerarm_r"].rotation_euler = (math.radians(-40), 0, 0)
    pb["upperarm_l"].rotation_euler = (0, 0, math.radians(-35))
    pb["thigh_l"].rotation_euler = (math.radians(-45), 0, 0)
    pb["calf_l"].rotation_euler = (math.radians(60), 0, 0)
    pb["spine_02"].rotation_euler = (0, math.radians(20), 0)
    bpy.context.view_layer.update()
    lo, hi = bbox(meshes())
    cam_data = bpy.data.cameras.new("TestCam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("TestCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    c = (lo + hi) * 0.5
    dist = (hi - lo).length * 1.4
    for label, d in (("front", Vector((0.3, -1, 0.15))), ("side", Vector((1, -0.25, 0.15)))):
        cam.location = c + d.normalized() * dist
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{prefix}_{label}.png"
        bpy.ops.render.render(write_still=True)
    for b in pb:
        b.rotation_euler = (0, 0, 0)
    bpy.data.objects.remove(cam)


def detach_regions(mesh_obj, cfg):
    """Cuts contact bridges between rigid props and the body (e.g. a sword tip
    resting on a robe in a single sculpted shell): faces that mix region and
    non-region vertices below `detach_below` are deleted so the prop can move
    freely, while the grip (above the threshold) stays connected."""
    removed = 0
    for reg in cfg["regions"]:
        if "detach_below" not in reg or "capsule" not in reg:
            continue
        a, b, r = (np.array(reg["capsule"][0]), np.array(reg["capsule"][1]), reg["capsule"][2])
        bm = bmesh.new()
        bm.from_mesh(mesh_obj.data)
        P = np.array([v.co for v in bm.verts])
        inside = _segment_distance(P, a, b) < r
        doomed = []
        for f in bm.faces:
            ids = [v.index for v in f.verts]
            flags = inside[ids]
            if flags.any() and not flags.all() and f.calc_center_median().z < reg["detach_below"]:
                doomed.append(f)
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        removed += len(doomed)
        bm.to_mesh(mesh_obj.data)
        bm.free()
    if removed:
        log(f"  detached props: {removed} bridging faces removed")


def build_humanoid(name, cfg):
    out_dir = os.path.join(OUT, name)
    texout = os.path.join(out_dir, "textures")
    os.makedirs(texout, exist_ok=True)
    results = {}
    for lod, target_tris in cfg["lods"].items():
        reset()
        src = cfg["src"]
        if src.endswith(".fbx"):
            bpy.ops.import_scene.fbx(filepath=src)
        else:
            bpy.ops.import_scene.gltf(filepath=src)
        for o in list(bpy.data.objects):
            if o.type != "MESH":
                bpy.data.objects.remove(o)
        objs = meshes()
        normalize(objs, cfg["height"], cfg.get("face_fix", 0.0))
        select_only(objs)
        if len(objs) > 1:
            bpy.ops.object.join()
        body = meshes()[0]
        body.name = name
        tris = tri_count([body])
        if target_tris < tris:
            decimate(body, target_tris / tris)
        for p in body.data.polygons:
            p.use_smooth = True
        detach_regions(body, cfg)
        mat = cfg["material"]()
        body.data.materials.clear()
        body.data.materials.append(mat)
        arm, lm = build_armature(cfg["landmarks"])
        metal = vertex_texture_values(body, cfg["metal_map"]) if cfg.get("metal_map") else None
        skin(body, arm, {k: Vector(v) for k, v in mirror(cfg["landmarks"]).items()}, cfg["regions"],
             vertex_metal=metal, cloth_excludes=cfg.get("cloth_excludes", ()), cutoffs=cfg.get("cutoffs"),
             smooth_iters=cfg.get("smooth_iters", 0))
        if lod == "arena":
            save_work_blend(name)
            pose_test_render(arm, os.path.join(WORK, "previews", f"{name}_posetest"))
        export_gltf(os.path.join(out_dir, f"{name}_{lod}.gltf"), [arm, body])
        results[lod] = {"tris": tri_count([body]), "bones": len(arm.data.bones)}
    report(name, {"source": cfg["src_label"], "lods": results, "landmarks": cfg["landmarks"]})


def _sun_knight_material():
    t = os.path.join(WORK, "sun_knight", "PBR_Textures.jpeg")
    orm = make_orm_from(os.path.join(t, "SunKnightWarrior_roughness.JPEG"), os.path.join(t, "SunKnightWarrior_metallic.JPEG"),
                        os.path.join(OUT, "king", "textures", "king_orm.png"))
    return pbr_material("king_armor", os.path.join(t, "SunKnightWarrior_basecolor.JPEG"),
                        os.path.join(t, "SunKnightWarrior_normal.JPEG"), orm)


def _medieval_knight_material():
    t = os.path.join(WORK, "medieval_knight")
    orm = make_orm_from(os.path.join(t, "texture_pbr_20250901_roughness.png"), os.path.join(t, "texture_pbr_20250901_metallic.png"),
                        os.path.join(OUT, "warrior", "textures", "warrior_orm.png"))
    return pbr_material("warrior_armor", os.path.join(t, "texture_pbr_20250901.png"),
                        os.path.join(t, "texture_pbr_20250901_normal.png"), orm)


KING = {
    "src": os.path.join(WORK, "sun_knight", "SunKnightWarrior.fbx"),
    "src_label": "Dark Fantasy Sun Knight Warrior (FBX + PBR JPEG)",
    "height": 2.25, "face_fix": -90.0, "smooth_iters": 12,
    "cutoffs": {"upperarm_l": 0.13, "upperarm_r": 0.13, "lowerarm_l": 0.1, "lowerarm_r": 0.1, "hand_l": 0.1, "hand_r": 0.09,
                "clavicle_l": 0.16, "clavicle_r": 0.16},
    "lods": {"board": 24000, "arena": 90000},
    "material": _sun_knight_material,
    # Measured from vertex slices (tools/blender: centerline analysis of the normalised mesh).
    "landmarks": {
        "pelvis": (0.0, -0.04, 0.98), "spine": (0.0, -0.03, 1.1), "chest": (0.0, -0.02, 1.28),
        "neck": (0.0, 0.0, 1.55), "head": (0.0, -0.02, 1.64), "head_top": (0.0, -0.04, 1.9),
        "shoulder_l": (0.26, -0.03, 1.42), "elbow_l": (0.31, -0.06, 1.06), "wrist_l": (0.32, -0.22, 0.86), "hand_end_l": (0.33, -0.4, 0.74),
        "shoulder_r": (-0.26, 0.0, 1.42), "elbow_r": (-0.33, 0.06, 1.06), "wrist_r": (-0.37, -0.08, 0.84), "hand_end_r": (-0.36, -0.2, 0.74),
        "hip_l": (0.12, -0.05, 0.92), "knee_l": (0.17, -0.06, 0.48), "ankle_l": (0.22, -0.1, 0.1), "toe_l": (0.24, -0.26, 0.02),
        "hip_r": (-0.12, -0.05, 0.92), "knee_r": (-0.18, -0.03, 0.48), "ankle_r": (-0.14, -0.08, 0.1), "toe_r": (-0.15, -0.24, 0.02),
    },
    "regions": [
        # Single sculpted shell: regions are per vertex.
        {"gradient": [[0.0, {"pelvis": 1.0}], [0.9, {"pelvis": 0.7, "spine_01": 0.3}], [1.25, {"spine_01": 0.6, "spine_02": 0.4}],
                      [1.5, {"spine_02": 1.0}], [2.0, {"spine_02": 1.0}]],
         "box": [(-0.75, 0.12, 0.0), (0.75, 1.0, 1.55)], "mode": "vertex"},
        {"bone": "head", "box": [(-0.75, -0.6, 1.64), (0.75, 0.75, 2.5)], "mode": "vertex"},
        # Blade axis fitted by PCA on the vertices (see docs/CHARACTER_PIPELINE.md).
        {"bone": "hand_r", "capsule": [(-0.37, -0.19, 0.76), (-0.095, -0.6, -0.01), 0.07], "mode": "vertex",
         "detach_below": 0.6},
    ],
}

WARRIOR = {
    "src": os.path.join(WORK, "medieval_knight", "Medieval Knight Warrior 001.glb"),
    "src_label": "Medieval Knight Warrior 001 (GLB + 4K PBR)",
    "height": 1.86, "face_fix": 0.0,
    "lods": {"board": 18000, "arena": 50000},
    "material": _medieval_knight_material,
    "landmarks": {
        "pelvis": (0.0, 0.0, 0.98), "spine": (0.0, 0.0, 1.1), "chest": (0.0, 0.01, 1.28),
        "neck": (0.0, 0.02, 1.53), "head": (0.0, 0.01, 1.6), "head_top": (0.0, 0.0, 1.85),
        "shoulder_l": (0.24, 0.02, 1.45), "elbow_l": (0.3, 0.02, 1.16), "wrist_l": (0.32, 0.0, 0.96), "hand_end_l": (0.33, -0.01, 0.88),
        "shoulder_r": (-0.24, 0.02, 1.45), "elbow_r": (-0.32, 0.01, 1.16), "wrist_r": (-0.35, -0.01, 0.95), "hand_end_r": (-0.33, -0.12, 0.85),
        "hip_l": (0.1, 0.0, 0.94), "knee_l": (0.12, -0.02, 0.5), "ankle_l": (0.14, 0.01, 0.1), "toe_l": (0.15, -0.14, 0.02),
    },
    "regions": [
        # Cape layers behind the body follow the torso, blending down to the pelvis.
        {"gradient": [[0.0, {"pelvis": 1.0}], [0.9, {"pelvis": 0.7, "spine_01": 0.3}], [1.25, {"spine_01": 0.6, "spine_02": 0.4}],
                      [1.5, {"spine_02": 1.0}], [2.0, {"spine_02": 1.0}]],
         "box": [(-0.7, 0.05, 0.0), (0.7, 0.8, 1.6)], "mode": "island", "majority": 0.6},
        {"bone": "lowerarm_l", "box": [(0.25, -0.35, 0.5), (0.6, 0.5, 1.28)], "mode": "island", "majority": 0.6},
        {"bone": "hand_r", "capsule": [(-0.34, 0.03, 0.86), (-0.30, -0.78, 0.15), 0.075], "mode": "island", "majority": 0.5},
    ],
}


def build_king():
    build_humanoid("king", KING)


def build_warrior():
    build_humanoid("warrior", WARRIOR)


BUILDERS = {"rook": build_rook, "king": build_king, "warrior": build_warrior}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(BUILDERS)
    for n in names:
        if n.startswith("--"):
            continue
        log("building", n)
        BUILDERS[n]()


if __name__ == "__main__":
    main()

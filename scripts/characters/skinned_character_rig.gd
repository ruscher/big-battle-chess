class_name SkinnedCharacterRig
extends CharacterRig
## Imported, skinned character with the same contract as the procedural
## CharacterRig (build/play/set_time_scale/set_fade/weapon_tip/...).
##
## Animation reuses the authored clip library: a PoseAnimator drives an
## invisible joint rig exactly like the procedural character, and every frame
## the joints' rotations are retargeted onto the model's Skeleton3D:
##
##   posed_global(bone) = delta(joint) * limb_fix(bone) * rest_global(bone)
##
## where delta is the joint's rotation away from its identity rest (expressed
## in skeleton space) and limb_fix turns A/T-pose limbs to the "arms down"
## rest the clips were authored for. Unmapped bones (twists, fingers,
## clavicles) keep their rest pose and simply follow their parents.
## Impact events, slow motion and skip work unchanged.

const FACTION_SHADER := preload("res://shaders/faction_pbr.gdshader")
const MARKERS := ["hand_r", "hand_l", "elbow_l", "chest", "head"]

static var _material_cache: Dictionary = {}
## Profiling: total microseconds spent retargeting (all rigs).
static var retarget_usec: int = 0

var context: String = "board"
var skeleton: Skeleton3D
var model_root: Node3D

var _vroot: Node3D
var _vjoints: Dictionary = {}
var _info: Dictionary = {}
var _bone_of_joint: Dictionary = {}     # joint name -> bone idx
var _joint_of_bone: Dictionary = {}     # bone idx -> joint name
var _order: PackedInt32Array = []       # bones to evaluate, parents first
var _rest_global: Array[Basis] = []
var _rest_local: Array[Basis] = []
var _fix: Dictionary = {}               # bone idx -> Quaternion (skeleton space)
var _skel_basis := Basis.IDENTITY       # skeleton space -> model space
var _skel_basis_inv := Basis.IDENTITY
var _pelvis: int = -1
var _pelvis_rest_pos := Vector3.ZERO
var _unit_scale: float = 1.0
var _posed: Array[Basis] = []
# Flattened evaluation data (built once in _setup_retarget).
var _eval_bones := PackedInt32Array()
var _eval_parent := PackedInt32Array()
var _eval_joint := PackedInt32Array()      # index into _joint_list, -1 when unmapped
var _eval_fix: Array[Quaternion] = []
var _joint_list: Array[Node3D] = []
var _joint_parent := PackedInt32Array()     # parent index in _joint_list (-1 = virtual root)
var _joint_global: Array[Basis] = []
var _frame_phase: int = 0
var _halo: Node3D
## Per-joint fraction of the authored local rotation to apply (e.g. a shield
## strapped along the forearm needs a straighter elbow to stay upright).
var _joint_scale: Dictionary = {}


static func clear_material_cache() -> void:
	_material_cache.clear()


func build(type: int, color: int) -> void:
	piece_type = type
	piece_color = color
	archetype = CharacterRig.ARCHETYPES[type]
	_info = CharacterLibrary.info(type)
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * float(_info.get("scale", 1.0))
	add_child(body)

	# Invisible joint rig animated by the shared clip library.
	_vroot = Node3D.new()
	_vroot.name = "VirtualRig"
	body.add_child(_vroot)
	_build_virtual_joints()

	model_root = Node3D.new()
	model_root.name = "Model"
	body.add_child(model_root)
	var instance := CharacterLibrary.scene(type, context).instantiate()
	model_root.add_child(instance)
	skeleton = _find_skeleton(instance)
	for mi in instance.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
		_apply_faction_materials(mi as MeshInstance3D, color)
	_unit_scale = float(_info.get("height", 1.9)) / 1.9

	for m in MARKERS:
		var marker := Node3D.new()
		marker.name = "Marker_" + m
		add_child(marker)
		joints[m] = marker

	animator = PoseAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(_vjoints, PoseLibrary.humanoid_poses(), PoseLibrary.humanoid_clips())
	animator.event_triggered.connect(func(e: StringName) -> void: anim_event.emit(e))
	_joint_scale = _info.get("joint_scale", {})
	if skeleton:
		_setup_retarget()
	if _info.get("halo", false):
		_build_halo(color)
	process_priority = 10  # after the animator has posed the joints
	animator.play(&"idle", 0.0)
	animator.advance(0.0)
	_retarget()


func _build_virtual_joints() -> void:
	var b := 1.0
	var base := _vjoint("base", _vroot, Vector3.ZERO)
	var hips := _vjoint("hips", base, Vector3(0, 0.98, 0))
	var spine := _vjoint("spine", hips, Vector3(0, 0.1, 0))
	var chest := _vjoint("chest", spine, Vector3(0, 0.15, 0))
	var neck := _vjoint("neck", chest, Vector3(0, 0.36, 0))
	_vjoint("head", neck, Vector3(0, 0.07, 0))
	for s in [1.0, -1.0]:
		var suffix := "_l" if s > 0 else "_r"
		var shoulder := _vjoint("shoulder" + suffix, chest, Vector3(0.205 * b * s, 0.27, 0))
		var elbow := _vjoint("elbow" + suffix, shoulder, Vector3(0, -0.29, 0))
		_vjoint("hand" + suffix, elbow, Vector3(0, -0.27, 0))
		var thigh := _vjoint("thigh" + suffix, hips, Vector3(0.1 * b * s, -0.06, 0))
		var knee := _vjoint("knee" + suffix, thigh, Vector3(0, -0.44, 0))
		_vjoint("foot" + suffix, knee, Vector3(0, -0.42, 0))


func _vjoint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = name.to_pascal_case()
	j.position = pos
	parent.add_child(j)
	_vjoints[name] = j
	return j


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


# --------------------------------------------------------------------------
# Retargeting
# --------------------------------------------------------------------------

func _relative_basis(node: Node3D, ancestor: Node3D) -> Basis:
	var b := Basis.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			b = (n as Node3D).transform.basis * b
		n = n.get_parent()
	return b


func _setup_retarget() -> void:
	_skel_basis = _relative_basis(skeleton, model_root)
	_skel_basis_inv = _skel_basis.inverse()
	var map: Dictionary = CharacterLibrary.BONE_MAPS[_info.get("map", "ue")]
	var count := skeleton.get_bone_count()
	_rest_global.resize(count)
	_rest_local.resize(count)
	_posed.resize(count)
	for i in count:
		_rest_global[i] = skeleton.get_bone_global_rest(i).basis
		_rest_local[i] = skeleton.get_bone_rest(i).basis
	var needed := {}
	for joint: String in map:
		var idx := skeleton.find_bone(map[joint])
		if idx < 0:
			push_warning("SkinnedCharacterRig: bone %s missing" % map[joint])
			continue
		_bone_of_joint[joint] = idx
		_joint_of_bone[idx] = joint
		var p := idx
		while p >= 0:
			needed[p] = true
			p = skeleton.get_bone_parent(p)
	# Parent-first evaluation order over the bones that matter.
	var order: Array[int] = []
	var visited := {}
	for idx: int in needed:
		_collect_order(idx, order, visited)
	_order = PackedInt32Array(order)
	var down := (_skel_basis_inv * Vector3.DOWN).normalized()
	for joint: String in CharacterLibrary.LIMB_FIX:
		if not _bone_of_joint.has(joint):
			continue
		var idx: int = _bone_of_joint[joint]
		var child := _main_child(idx)
		if child < 0:
			continue
		var dir := (skeleton.get_bone_global_rest(child).origin - skeleton.get_bone_global_rest(idx).origin).normalized()
		_fix[idx] = Quaternion(dir, down)
	# Hands follow their forearm's correction.
	for side in ["_l", "_r"]:
		if _bone_of_joint.has("hand" + side) and _bone_of_joint.has("elbow" + side):
			_fix[_bone_of_joint["hand" + side]] = _fix.get(_bone_of_joint["elbow" + side], Quaternion.IDENTITY)
	_pelvis = _bone_of_joint.get("hips", -1)
	if _pelvis >= 0:
		_pelvis_rest_pos = skeleton.get_bone_rest(_pelvis).origin
	# Joints in parent-first order (they were created that way).
	var jindex := {}
	for name: String in _vjoints:
		var j: Node3D = _vjoints[name]
		jindex[j] = _joint_list.size()
		_joint_list.append(j)
	for j in _joint_list:
		_joint_parent.append(jindex.get(j.get_parent(), -1))
	_joint_global.resize(_joint_list.size())
	for idx in _order:
		_eval_bones.append(idx)
		_eval_parent.append(skeleton.get_bone_parent(idx))
		_eval_joint.append(jindex[_vjoints[_joint_of_bone[idx]]] if _joint_of_bone.has(idx) else -1)
		_eval_fix.append(_fix.get(idx, Quaternion.IDENTITY))
	_frame_phase = get_instance_id() & 1


func _collect_order(idx: int, order: Array[int], visited: Dictionary) -> void:
	if visited.has(idx):
		return
	var parent := skeleton.get_bone_parent(idx)
	if parent >= 0:
		_collect_order(parent, order, visited)
	visited[idx] = true
	order.append(idx)


## Child bone that continues the limb (the one farthest from the bone).
func _main_child(idx: int) -> int:
	var best := -1
	var best_d := -1.0
	var origin := skeleton.get_bone_global_rest(idx).origin
	for c in skeleton.get_bone_children(idx):
		var name := skeleton.get_bone_name(c)
		if name.contains("twist") or name.contains("corrective"):
			continue
		var d := skeleton.get_bone_global_rest(c).origin.distance_to(origin)
		if d > best_d:
			best_d = d
			best = c
	return best


func _retarget() -> void:
	if skeleton == null:
		return
	for joint: String in _joint_scale:
		var j: Node3D = _vjoints[joint]
		j.quaternion = Quaternion.IDENTITY.slerp(j.quaternion, float(_joint_scale[joint]))
	# Joint rotations relative to the virtual root, accumulated top-down.
	for i in _joint_list.size():
		var local := _joint_list[i].basis
		var p := _joint_parent[i]
		_joint_global[i] = local if p < 0 else _joint_global[p] * local
	var count := _eval_bones.size()
	for k in count:
		var idx := _eval_bones[k]
		var parent := _eval_parent[k]
		var parent_posed := _posed[parent] if parent >= 0 else Basis.IDENTITY
		var posed: Basis
		var ji := _eval_joint[k]
		if ji >= 0:
			var delta := _skel_basis_inv * _joint_global[ji].orthonormalized() * _skel_basis
			posed = Basis(delta.get_rotation_quaternion() * _eval_fix[k]) * _rest_global[idx]
			skeleton.set_bone_pose_rotation(idx, (parent_posed.inverse() * posed).get_rotation_quaternion())
		else:
			posed = parent_posed * _rest_local[idx]
		_posed[idx] = posed
	if _pelvis >= 0:
		var hips: Node3D = _vjoints["hips"]
		var offset: Vector3 = (hips.position - animator.rest_offsets.get("hips", hips.position)) * _unit_scale
		skeleton.set_bone_pose_position(_pelvis, _pelvis_rest_pos + _skel_basis_inv * offset)
	# The procedural "base" joint (falls, kneeling to the floor) moves the whole model.
	var base: Node3D = _vjoints["base"]
	model_root.transform = Transform3D(base.basis, (base.position - animator.rest_offsets.get("base", Vector3.ZERO)) * _unit_scale)
	_update_markers()


## Sacred (Dawn) or eclipse (Umbral) halo behind the head: an energy ring
## that makes the war-cleric readable from the board camera.
func _build_halo(color: int) -> void:
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = MaterialLibrary.torus(0.17, 0.2)
	var energy: Color = FactionStyle.get_style(color)["energy"]
	halo.material_override = MaterialLibrary.energy_material(energy, 2.6)
	halo.rotation_degrees = Vector3(90, 0, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.name = "HaloHolder"
	(joints["head"] as Node3D).add_child(holder)
	holder.add_child(halo)
	_halo = holder


func _bone_world(idx: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin


func _update_markers() -> void:
	if not is_inside_tree():
		return
	for m: String in MARKERS:
		var idx: int = _bone_of_joint.get(m, -1)
		if idx >= 0:
			(joints[m] as Node3D).global_position = _bone_world(idx)
	if _halo:
		var head: int = _bone_of_joint.get("head", -1)
		var s := global_basis.get_scale().y
		var b := global_basis.orthonormalized()
		var origin := _bone_world(head) + b.y * 0.16 * s - b.z * 0.13 * s
		_halo.global_transform = Transform3D(b.scaled(Vector3.ONE * s), origin)


func _process(_delta: float) -> void:
	# Board idles are subtle: update them at half rate (alternating rigs) to
	# spread CPU cost; arena fighters always update every frame.
	if context == "board" and animator.current_clip == &"idle":
		_frame_phase ^= 1
		if _frame_phase == 0:
			return
	var t0 := Time.get_ticks_usec()
	_retarget()
	retarget_usec += Time.get_ticks_usec() - t0


# --------------------------------------------------------------------------
# Materials: shared textures, faction look via shader parameters
# --------------------------------------------------------------------------

func _apply_faction_materials(mi: MeshInstance3D, color: int) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		if src is StandardMaterial3D:
			mi.set_surface_override_material(s, _faction_material(src as StandardMaterial3D, color))


const LOOK_DEFAULTS := {
	"dawn": {
		"metal_tint": Color(0.96, 0.9, 0.76), "metal_tint_amount": 0.75, "metal_lum_scale": 3.4, "metal_gain": 1.0,
		"metal_roughness_mul": 0.62, "cloth_tint": Color(0.15, 0.24, 0.55), "cloth_tint_amount": 0.7, "cloth_gain": 1.15,
		"accent_color": Color(1.0, 0.76, 0.32), "accent_amount": 0.0, "accent_hue": 0.0, "rim_color": Color(1.0, 0.85, 0.55),
	},
	"umbral": {
		"metal_tint": Color(0.42, 0.38, 0.46), "metal_tint_amount": 0.55, "metal_lum_scale": 1.5, "metal_gain": 0.75,
		"metal_roughness_mul": 1.05, "cloth_tint": Color(0.42, 0.05, 0.07), "cloth_tint_amount": 0.75, "cloth_gain": 0.95,
		"accent_color": Color(0.75, 0.08, 0.12), "accent_amount": 0.0, "accent_hue": 0.0, "rim_color": Color(1.0, 0.3, 0.35),
	},
}


func _faction_material(src: StandardMaterial3D, color: int) -> Material:
	var key := "%d:%d:%d" % [src.get_instance_id(), color, piece_type]
	if _material_cache.has(key):
		return _material_cache[key]
	if src.albedo_texture == null:
		# Untextured part (e.g. dark visor interior): keep a plain material.
		var plain := src.duplicate() as StandardMaterial3D
		plain.albedo_color = Color(0.03, 0.03, 0.035) if color == Chess.BLACK else src.albedo_color
		_material_cache[key] = plain
		return plain
	var m := ShaderMaterial.new()
	m.shader = FACTION_SHADER
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("has_normal", src.normal_texture != null)
	if src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
	var orm: Texture2D = src.roughness_texture if src.roughness_texture else src.metallic_texture
	m.set_shader_parameter("has_orm", orm != null)
	if orm:
		m.set_shader_parameter("orm_tex", orm)
	m.set_shader_parameter("fallback_metallic", src.metallic)
	m.set_shader_parameter("fallback_roughness", src.roughness)
	var faction := "dawn" if color == Chess.WHITE else "umbral"
	var look: Dictionary = LOOK_DEFAULTS[faction].duplicate()
	look.merge(_info.get("look", {}).get(faction, {}), true)
	for p: String in look:
		m.set_shader_parameter(p, look[p])
	_material_cache[key] = m
	return m


# --------------------------------------------------------------------------
# CharacterRig contract
# --------------------------------------------------------------------------

func weapon_tip() -> Vector3:
	var hand: int = _bone_of_joint.get("hand_r", -1)
	var elbow: int = _bone_of_joint.get("elbow_r", -1)
	if skeleton == null or hand < 0 or elbow < 0:
		return global_position + Vector3.UP
	var h := _bone_world(hand)
	var dir := (h - _bone_world(elbow)).normalized()
	return h + dir * float(_info.get("tip_offset", 0.15)) * global_basis.get_scale().y


func weapon_base() -> Vector3:
	var hand: int = _bone_of_joint.get("hand_r", -1)
	return _bone_world(hand) if skeleton and hand >= 0 else global_position + Vector3.UP


func chest_position() -> Vector3:
	var idx: int = _bone_of_joint.get("chest", -1)
	return _bone_world(idx) if skeleton and idx >= 0 else global_position + Vector3.UP * height() * 0.7


func head_position() -> Vector3:
	var idx: int = _bone_of_joint.get("head", -1)
	if skeleton == null or idx < 0:
		return global_position + Vector3.UP * height()
	return _bone_world(idx) + Vector3.UP * 0.12 * global_basis.get_scale().y


func height() -> float:
	return float(_info.get("height", 1.9)) * float(_info.get("scale", 1.0))


func reset_pose_state() -> void:
	pass

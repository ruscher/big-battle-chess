class_name CharacterRig
extends Node3D
## Procedural, articulated medieval warrior for one chess piece.
##
## Built entirely from shared primitive meshes and PBR materials (no external
## assets required). The same rig is used on the board (scaled down) and in
## the battle arena (full size). Animation is driven by PoseAnimator clips;
## knights ride a HorseRig and only animate their upper body in combat.

signal anim_event(event_name: StringName)


## Per piece type: body proportions and gear (index 0 = Dawn, 1 = Umbral).
const ARCHETYPES := {
	Chess.PAWN: {"scale": 0.93, "bulk": 0.95, "helm": "sallet", "weapon": ["spear", "falchion"], "shield": ["round", "buckler"], "skirt": "short", "cape": false},
	Chess.KNIGHT: {"scale": 1.0, "bulk": 1.0, "helm": "winged", "weapon": ["lance", "glaive"], "shield": ["kite", "kite"], "skirt": "short", "cape": true, "mounted": true},
	Chess.BISHOP: {"scale": 1.02, "bulk": 0.92, "helm": "mitre", "weapon": ["staff", "scythe"], "shield": ["", ""], "skirt": "robe", "cape": true},
	Chess.ROOK: {"scale": 1.1, "bulk": 1.38, "helm": "tower", "weapon": ["hammer", "maul"], "shield": ["tower", "tower"], "skirt": "short", "cape": false},
	Chess.QUEEN: {"scale": 1.04, "bulk": 0.84, "helm": "queen", "weapon": ["rapier", "rapier"], "shield": ["", ""], "skirt": "gown", "cape": true},
	Chess.KING: {"scale": 1.1, "bulk": 1.12, "helm": "king", "weapon": ["greatsword", "greatsword"], "shield": ["", ""], "skirt": "long", "cape": true},
}

const RIDER_LEGS := ["thigh_l", "knee_l", "foot_l", "thigh_r", "knee_r", "foot_r", "hips"]

var piece_type: int = Chess.PAWN
var piece_color: int = Chess.WHITE
var animator: PoseAnimator
var horse: HorseRig
var weapon: Node3D
var shield: Node3D
var joints: Dictionary = {}
var archetype: Dictionary = {}

var _shield_anchor: Node3D
var _meshes: Array[GeometryInstance3D] = []
var _locomotion: StringName = &""


func build(type: int, color: int) -> void:
	piece_type = type
	piece_color = color
	archetype = ARCHETYPES[type]
	var side := 0 if color == Chess.WHITE else 1
	var b: float = archetype["bulk"]
	var root := Node3D.new()
	root.name = "Body"
	root.scale = Vector3.ONE * float(archetype["scale"])
	add_child(root)

	var rider_parent: Node3D = root
	if archetype.get("mounted", false):
		horse = HorseRig.new()
		horse.name = "Horse"
		root.add_child(horse)
		horse.build(color)
		rider_parent = horse.saddle

	var armor := MaterialLibrary.get_material("armor", color)
	var trim := MaterialLibrary.get_material("trim", color)
	var cloth := MaterialLibrary.get_material("cloth", color)
	var cloth_alt := MaterialLibrary.get_material("cloth_alt", color)
	var leather := MaterialLibrary.get_material("leather", color)
	var skirt: String = archetype["skirt"]

	var base := _joint("base", rider_parent, Vector3(0, -0.9, 0) if horse else Vector3.ZERO)
	var hips := _joint("hips", base, Vector3(0, 0.98, 0))
	GearBuilder.part(hips, MaterialLibrary.cylinder(0.15 * b, 0.165 * b, 0.2), armor, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.75))
	GearBuilder.part(hips, MaterialLibrary.torus(0.145 * b, 0.175 * b), leather, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 1.3, 0.78))
	GearBuilder.part(hips, MaterialLibrary.box(Vector3(0.055, 0.05, 0.02)), trim, Vector3(0, 0.07, 0.135 * b))
	match skirt:
		"short":
			GearBuilder.part(hips, MaterialLibrary.cylinder(0.17 * b, 0.235 * b, 0.27, 16), cloth_alt, Vector3(0, -0.14, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
			GearBuilder.part(hips, MaterialLibrary.torus(0.215 * b, 0.235 * b), trim, Vector3(0, -0.27, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
		"robe":
			GearBuilder.part(hips, MaterialLibrary.cylinder(0.17 * b, 0.37 * b, 0.86, 18), cloth, Vector3(0, -0.44, 0))
			GearBuilder.part(hips, MaterialLibrary.torus(0.355 * b, 0.375 * b), trim, Vector3(0, -0.86, 0))
			GearBuilder.part(hips, MaterialLibrary.box(Vector3(0.12, 0.8, 0.02)), cloth_alt, Vector3(0, -0.42, 0.19 * b + 0.06), Vector3(-13, 0, 0))
		"gown":
			GearBuilder.part(hips, MaterialLibrary.cylinder(0.15 * b, 0.46 * b, 0.9, 20), cloth_alt, Vector3(0, -0.45, 0))
			GearBuilder.part(hips, MaterialLibrary.cylinder(0.16 * b, 0.4 * b, 0.7, 20), cloth, Vector3(0, -0.36, 0.025), Vector3.ZERO, Vector3(0.92, 1, 1))
			GearBuilder.part(hips, MaterialLibrary.torus(0.445 * b, 0.47 * b), trim, Vector3(0, -0.89, 0))
		"long":
			GearBuilder.part(hips, MaterialLibrary.cylinder(0.18 * b, 0.32 * b, 0.62, 18), cloth_alt, Vector3(0, -0.3, 0))
			GearBuilder.part(hips, MaterialLibrary.torus(0.305 * b, 0.33 * b), trim, Vector3(0, -0.6, 0))

	var spine := _joint("spine", hips, Vector3(0, 0.1, 0))
	GearBuilder.part(spine, MaterialLibrary.cylinder(0.14 * b, 0.145 * b, 0.18), armor, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 1, 0.78))
	var chest := _joint("chest", spine, Vector3(0, 0.15, 0))
	var chest_mat := cloth_alt if skirt == "gown" else armor
	GearBuilder.part(chest, MaterialLibrary.cylinder(0.21 * b, 0.155 * b, 0.34), chest_mat, Vector3(0, 0.16, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	GearBuilder.part(chest, MaterialLibrary.sphere(0.165 * b), chest_mat, Vector3(0, 0.18, 0.035), Vector3.ZERO, Vector3(1.1, 1.0, 0.78))
	GearBuilder.part(chest, MaterialLibrary.cylinder(0.1, 0.125, 0.08), armor, Vector3(0, 0.34, 0))
	GearBuilder.part(chest, MaterialLibrary.torus(0.1, 0.13), trim, Vector3(0, 0.33, 0), Vector3.ZERO, Vector3(1, 1, 0.85))
	if skirt == "short" or skirt == "long":
		GearBuilder.part(chest, MaterialLibrary.box(Vector3(0.25 * b, 0.6, 0.016)), cloth, Vector3(0, -0.06, 0.135 * b), Vector3(-4, 0, 0))
		GearBuilder.part(chest, MaterialLibrary.quad(Vector2(0.17, 0.17)), MaterialLibrary.emblem_material(color), Vector3(0, 0.12, 0.146 * b), Vector3(-4, 0, 0))
	else:
		GearBuilder.part(chest, MaterialLibrary.quad(Vector2(0.15, 0.15)), MaterialLibrary.emblem_material(color), Vector3(0, 0.18, 0.165 * b), Vector3(-8, 0, 0))
	if piece_type == Chess.KING:
		GearBuilder.part(chest, MaterialLibrary.torus(0.14 * b, 0.21 * b), MaterialLibrary.get_material("cloth", color), Vector3(0, 0.3, -0.01), Vector3.ZERO, Vector3(1, 1.6, 0.85))
	if archetype["cape"]:
		var cape_len := 1.0 if horse == null else 0.75
		var cape := GearBuilder.part(chest, MaterialLibrary.cloth_plane(0.46 * b, cape_len), MaterialLibrary.cloth_material(color, color == Chess.WHITE, randf() * 6.0, 0.07),
			Vector3(0, 0.31, -0.115 * b), Vector3(9, 0, 0))
		cape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED

	var neck := _joint("neck", chest, Vector3(0, 0.36, 0))
	GearBuilder.part(neck, MaterialLibrary.cylinder(0.06, 0.068, 0.1), leather, Vector3(0, 0.03, 0))
	var head := _joint("head", neck, Vector3(0, 0.07, 0))
	GearBuilder.build_head(head, archetype["helm"], color)

	for s in [1.0, -1.0]:
		var suffix := "_l" if s > 0 else "_r"
		var shoulder := _joint("shoulder" + suffix, chest, Vector3(0.205 * b * s, 0.27, 0))
		GearBuilder.part(shoulder, MaterialLibrary.sphere(0.105 * b), armor, Vector3(0.035 * s, 0.02, 0), Vector3(0, 0, -12 * s), Vector3(1.28, 0.85, 1.15))
		GearBuilder.part(shoulder, MaterialLibrary.torus(0.085 * b, 0.108 * b), trim, Vector3(0.04 * s, -0.035, 0), Vector3(0, 0, -15 * s), Vector3(1.15, 1, 1.1))
		if piece_color == Chess.BLACK and (piece_type == Chess.ROOK or piece_type == Chess.KING or piece_type == Chess.KNIGHT):
			GearBuilder.part(shoulder, MaterialLibrary.cylinder(0.0, 0.03, 0.14, 6), trim, Vector3(0.07 * s, 0.1, 0), Vector3(0, 0, -35 * s))
		GearBuilder.part(shoulder, MaterialLibrary.capsule(0.062 * b, 0.3), leather, Vector3(0, -0.14, 0))
		GearBuilder.part(shoulder, MaterialLibrary.cylinder(0.072 * b, 0.064 * b, 0.2), armor, Vector3(0, -0.15, 0))
		var elbow := _joint("elbow" + suffix, shoulder, Vector3(0, -0.29, 0))
		GearBuilder.part(elbow, MaterialLibrary.sphere(0.07), armor, Vector3(0, 0, 0.012))
		GearBuilder.part(elbow, MaterialLibrary.cylinder(0.04, 0.075, 0.07, 10), trim, Vector3(0, 0.0, -0.045), Vector3(90, 0, 0))
		GearBuilder.part(elbow, MaterialLibrary.cylinder(0.072, 0.058, 0.24), armor, Vector3(0, -0.13, 0))
		GearBuilder.part(elbow, MaterialLibrary.cylinder(0.085, 0.07, 0.07), armor, Vector3(0, -0.235, 0))
		GearBuilder.part(elbow, MaterialLibrary.torus(0.07, 0.085), trim, Vector3(0, -0.205, 0))
		var hand := _joint("hand" + suffix, elbow, Vector3(0, -0.27, 0))
		GearBuilder.part(hand, MaterialLibrary.box(Vector3(0.095, 0.11, 0.095)), armor, Vector3(0, -0.045, 0))
		GearBuilder.part(hand, MaterialLibrary.box(Vector3(0.1, 0.035, 0.1)), trim, Vector3(0, 0.005, 0))

		var thigh := _joint("thigh" + suffix, hips, Vector3(0.1 * b * s, -0.06, 0))
		GearBuilder.part(thigh, MaterialLibrary.capsule(0.088 * b, 0.44), cloth_alt if skirt != "short" else leather, Vector3(0, -0.21, 0))
		GearBuilder.part(thigh, MaterialLibrary.cylinder(0.1 * b, 0.084 * b, 0.3), armor, Vector3(0, -0.18, 0.008))
		var knee := _joint("knee" + suffix, thigh, Vector3(0, -0.44, 0))
		GearBuilder.part(knee, MaterialLibrary.sphere(0.075), armor, Vector3(0, 0.0, 0.035), Vector3.ZERO, Vector3(1, 1, 0.9))
		GearBuilder.part(knee, MaterialLibrary.cylinder(0.02, 0.075, 0.05, 10), trim, Vector3(0.05 * s, 0.0, 0.03), Vector3(0, 0, 90 * s))
		GearBuilder.part(knee, MaterialLibrary.capsule(0.06, 0.4), leather, Vector3(0, -0.2, -0.005))
		GearBuilder.part(knee, MaterialLibrary.cylinder(0.078, 0.064, 0.38), armor, Vector3(0, -0.2, 0.006))
		var foot := _joint("foot" + suffix, knee, Vector3(0, -0.42, 0))
		GearBuilder.part(foot, MaterialLibrary.box(Vector3(0.12, 0.09, 0.2)), armor, Vector3(0, -0.02, 0.02))
		GearBuilder.part(foot, MaterialLibrary.prism(Vector3(0.11, 0.08, 0.12)), armor, Vector3(0, -0.03, 0.17), Vector3(90, 0, 0))

	weapon = GearBuilder.build_weapon(joints["hand_r"], archetype["weapon"][side], color)
	var shield_kind: String = archetype["shield"][side]
	if not shield_kind.is_empty():
		_shield_anchor = Node3D.new()
		_shield_anchor.name = "ShieldAnchor"
		root.add_child(_shield_anchor)
		shield = GearBuilder.build_shield(_shield_anchor, shield_kind, color)

	for node in find_children("*", "GeometryInstance3D", true, false):
		_meshes.append(node)

	animator = PoseAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(joints, PoseLibrary.humanoid_poses(), PoseLibrary.humanoid_clips())
	animator.event_triggered.connect(func(e: StringName) -> void: anim_event.emit(e))
	if horse:
		animator.overrides = _ride_overrides()
		horse.animator.event_triggered.connect(func(e: StringName) -> void: anim_event.emit(e))
	animator.play(&"idle", 0.0)


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = name.to_pascal_case()
	j.position = pos
	parent.add_child(j)
	joints[name] = j
	return j


func _ride_overrides() -> Dictionary:
	var ride: Dictionary = PoseLibrary.humanoid_poses()["ride"]
	var o := {}
	for k in RIDER_LEGS:
		o[k] = ride.get(k, Vector3.ZERO)
	o["hips:offset"] = Vector3.ZERO
	o["base"] = Vector3.ZERO
	o["base:offset"] = Vector3.ZERO
	return o


func _process(_delta: float) -> void:
	if _shield_anchor != null:
		# Keep the shield strapped to the left forearm but facing the rig's
		# front (a light-weight IK substitute that reads well in every pose).
		var elbow: Node3D = joints["elbow_l"]
		var hand: Node3D = joints["hand_l"]
		var chest: Node3D = joints["chest"]
		var mid := elbow.global_position.lerp(hand.global_position, 0.55)
		var basis := chest.global_basis.orthonormalized().rotated(chest.global_basis.y.normalized(), deg_to_rad(28))
		var forward := basis.z.normalized()
		var s := (_shield_anchor.get_parent() as Node3D).global_basis.get_scale()
		_shield_anchor.global_transform = Transform3D(basis.scaled(s), mid + forward * 0.07 * s.x)


# --------------------------------------------------------------------------
# Animation API
# --------------------------------------------------------------------------

## Plays a clip. Locomotion clips ("walk", "run") are routed to the horse for
## mounted pieces while the rider keeps a riding guard.
func play(clip: StringName, blend: float = 0.15, speed: float = 1.0) -> void:
	if horse:
		match clip:
			&"walk":
				horse.animator.play(&"walk", blend, speed)
				animator.play(&"guard", blend)
				return
			&"run":
				horse.animator.play(&"gallop", blend, speed)
				animator.play(&"guard", blend)
				return
			&"idle", &"guard", &"victory", &"salute", &"power_up":
				horse.animator.play(&"stand", blend)
			&"death":
				horse.animator.play(&"fall", blend)
				animator.overrides = {}
			&"surrender":
				horse.animator.play(&"stand", blend)
	animator.play(clip, blend, speed)


func play_horse(clip: StringName, blend: float = 0.15, speed: float = 1.0) -> void:
	if horse:
		horse.animator.play(clip, blend, speed)


func clip_length(clip: StringName, speed: float = 1.0) -> float:
	return animator.clip_length(clip, speed)


func event_time(clip: StringName, event_name: StringName, speed: float = 1.0) -> float:
	return animator.event_time(clip, event_name, speed)


func set_time_scale(value: float) -> void:
	animator.time_scale = value
	if horse:
		horse.animator.time_scale = value


func reset_pose_state() -> void:
	if horse:
		animator.overrides = _ride_overrides()


## Fades the whole character (0 = opaque, 1 = invisible).
func set_fade(amount: float) -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.transparency = amount


func set_cast_shadows(enabled: bool) -> void:
	for m in _meshes:
		if is_instance_valid(m) and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func weapon_tip() -> Vector3:
	var tip := weapon.get_node_or_null("Tip") as Node3D if weapon else null
	return tip.global_position if tip else global_position + Vector3.UP


func weapon_base() -> Vector3:
	var base := weapon.get_node_or_null("Base") as Node3D if weapon else null
	return base.global_position if base else global_position + Vector3.UP


## World position of the chest (camera focus / impact point).
func chest_position() -> Vector3:
	return (joints["chest"] as Node3D).global_position + Vector3.UP * 0.15 * global_basis.get_scale().y


func head_position() -> Vector3:
	return (joints["head"] as Node3D).global_position + Vector3.UP * 0.12 * global_basis.get_scale().y


## Approximate standing height in local units (before node scale).
func height() -> float:
	return (2.75 if horse else 1.9) * float(archetype.get("scale", 1.0))

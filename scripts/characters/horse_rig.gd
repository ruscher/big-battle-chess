class_name HorseRig
extends Node3D
## Armoured warhorse for the knight pieces. Faces +Z. Exposes `saddle`, the
## node the rider's base is parented to, so the rider follows the gallop.


var animator: PoseAnimator
var saddle: Node3D
var joints: Dictionary = {}


func build(color: int) -> void:
	var coat := MaterialLibrary.get_material("horse", color)
	var armor := MaterialLibrary.get_material("armor", color)
	var trim := MaterialLibrary.get_material("trim", color)
	var dark := MaterialLibrary.get_material("dark", color)
	var leather := MaterialLibrary.get_material("leather", color)
	var hair := dark if color == Chess.BLACK else MaterialLibrary.get_material("cloth", color)

	var base := _joint("hbase", self, Vector3.ZERO)
	var body := _joint("body", base, Vector3(0, 1.22, 0))
	GearBuilder.part(body, MaterialLibrary.capsule(0.3, 1.3), coat, Vector3.ZERO, Vector3(90, 0, 0))
	GearBuilder.part(body, MaterialLibrary.sphere(0.31), coat, Vector3(0, 0.02, 0.48), Vector3.ZERO, Vector3(1, 1.05, 0.9))
	GearBuilder.part(body, MaterialLibrary.sphere(0.32), coat, Vector3(0, 0.05, -0.48), Vector3.ZERO, Vector3(1.02, 1.0, 0.95))
	# Caparison: cloth draped over the flanks, carrying the faction emblem.
	GearBuilder.part(body, MaterialLibrary.capsule(0.335, 1.12), MaterialLibrary.get_material("cloth_alt", color), Vector3(0, 0.02, -0.02), Vector3(90, 0, 0), Vector3(1, 0.92, 1))
	for s in [-1.0, 1.0]:
		var flank := GearBuilder.part(body, MaterialLibrary.cloth_plane(1.05, 0.5), MaterialLibrary.cloth_material(color, false, 0.7 + s, 0.035),
			Vector3(0.335 * s, 0.05, -0.02), Vector3(0, 90 * s, 0))
		flank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		GearBuilder.part(body, MaterialLibrary.quad(Vector2(0.28, 0.28)), MaterialLibrary.emblem_material(color), Vector3(0.343 * s, -0.12, -0.05), Vector3(0, 90 * s, 0))
	GearBuilder.part(body, MaterialLibrary.box(Vector3(0.4, 0.08, 0.46)), leather, Vector3(0, 0.31, -0.05))
	GearBuilder.part(body, MaterialLibrary.box(Vector3(0.42, 0.12, 0.06)), trim, Vector3(0, 0.34, 0.18))
	saddle = GearBuilder.marker(body, "Saddle", Vector3(0, 0.34, -0.05))

	var neck := _joint("neck", body, Vector3(0, 0.12, 0.6))
	GearBuilder.part(neck, MaterialLibrary.capsule(0.16, 0.8), coat, Vector3(0, 0.3, 0.14), Vector3(32, 0, 0))
	GearBuilder.part(neck, MaterialLibrary.cylinder(0.17, 0.2, 0.42, 14), armor, Vector3(0, 0.3, 0.15), Vector3(32, 0, 0), Vector3(1, 1, 0.9))
	GearBuilder.part(neck, MaterialLibrary.box(Vector3(0.05, 0.62, 0.1)), hair, Vector3(0, 0.36, -0.02), Vector3(32, 0, 0))
	var head := _joint("head", neck, Vector3(0, 0.62, 0.36))
	GearBuilder.part(head, MaterialLibrary.capsule(0.11, 0.62), coat, Vector3(0, -0.06, 0.2), Vector3(112, 0, 0))
	GearBuilder.part(head, MaterialLibrary.sphere(0.1), coat, Vector3(0, -0.17, 0.44), Vector3.ZERO, Vector3(0.95, 0.8, 1.05))
	GearBuilder.part(head, MaterialLibrary.box(Vector3(0.16, 0.05, 0.5)), armor, Vector3(0, 0.03, 0.22), Vector3(22, 0, 0))
	GearBuilder.part(head, MaterialLibrary.box(Vector3(0.03, 0.06, 0.4)), trim, Vector3(0, 0.07, 0.22), Vector3(22, 0, 0))
	for s in [-1.0, 1.0]:
		GearBuilder.part(head, MaterialLibrary.prism(Vector3(0.05, 0.12, 0.03)), coat, Vector3(0.06 * s, 0.1, 0.0), Vector3(-15, 0, 10 * s))
		var eye_mat := MaterialLibrary.get_material("eyes", color) if color == Chess.BLACK else dark
		GearBuilder.part(head, MaterialLibrary.sphere(0.022), eye_mat, Vector3(0.095 * s, -0.01, 0.15))
	if color == Chess.BLACK:
		GearBuilder.part(head, MaterialLibrary.cylinder(0.0, 0.03, 0.2, 6), MaterialLibrary.get_material("mask", color), Vector3(0, 0.13, 0.12), Vector3(-30, 0, 0))

	for leg in [["fl", 0.17, 0.5], ["fr", -0.17, 0.5], ["bl", 0.17, -0.52], ["br", -0.17, -0.52]]:
		var name: String = leg[0]
		var upper := _joint("leg_" + name, body, Vector3(leg[1], -0.16, leg[2]))
		var thick := 0.085 if name.begins_with("b") else 0.075
		GearBuilder.part(upper, MaterialLibrary.capsule(thick, 0.55), coat, Vector3(0, -0.24, 0))
		var lower := _joint("knee_" + name, upper, Vector3(0, -0.5, 0))
		GearBuilder.part(lower, MaterialLibrary.capsule(0.048, 0.46), coat, Vector3(0, -0.22, 0))
		GearBuilder.part(lower, MaterialLibrary.cylinder(0.065, 0.06, 0.12, 10), hair, Vector3(0, -0.38, 0))
		GearBuilder.part(lower, MaterialLibrary.cylinder(0.06, 0.075, 0.08, 10), dark, Vector3(0, -0.47, 0.01))

	var tail := _joint("tail", body, Vector3(0, 0.14, -0.8))
	GearBuilder.part(tail, MaterialLibrary.capsule(0.055, 0.62), hair, Vector3(0, -0.28, 0))

	animator = PoseAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.breathing = 0.0
	animator.setup(joints, PoseLibrary.horse_poses(), PoseLibrary.horse_clips())
	animator.play(&"stand", 0.0)


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = name.to_pascal_case()
	j.position = pos
	parent.add_child(j)
	joints[name] = j
	return j

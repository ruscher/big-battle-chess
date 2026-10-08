class_name GearBuilder
extends RefCounted
## Builds helmets, weapons and shields from primitive meshes.
## Weapons are built in hand space: grip at the origin, blade along +Z.
## Each weapon exposes "Tip" and "Base" markers (Node3D) for trails/sparks.



static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func marker(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


# --------------------------------------------------------------------------
# Helmets / heads (head joint space, neck top at origin)
# --------------------------------------------------------------------------

static func build_head(head: Node3D, kind: String, color: int) -> void:
	var armor := MaterialLibrary.get_material("armor", color)
	var trim := MaterialLibrary.get_material("trim", color)
	var dark := MaterialLibrary.get_material("dark", color)
	var cloth := MaterialLibrary.get_material("cloth", color)
	var cloth_alt := MaterialLibrary.get_material("cloth_alt", color)
	var umbral := color == Chess.BLACK
	match kind:
		"sallet":
			part(head, MaterialLibrary.sphere(0.125), armor, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1.05, 1.12))
			part(head, MaterialLibrary.cylinder(0.165, 0.185, 0.022), armor, Vector3(0, 0.115, -0.01), Vector3(-8, 0, 0))
			part(head, MaterialLibrary.box(Vector3(0.17, 0.02, 0.02)), dark, Vector3(0, 0.115, 0.13))
			if umbral:
				part(head, MaterialLibrary.prism(Vector3(0.03, 0.14, 0.2)), armor, Vector3(0, 0.27, -0.01), Vector3(0, 90, 0))
			else:
				part(head, MaterialLibrary.box(Vector3(0.02, 0.045, 0.24)), trim, Vector3(0, 0.235, 0))
		"tower":
			part(head, MaterialLibrary.cylinder(0.145, 0.135, 0.29, 16), armor, Vector3(0, 0.13, 0))
			part(head, MaterialLibrary.torus(0.13, 0.155), trim, Vector3(0, 0.27, 0))
			for i in 6:
				var a := TAU * i / 6.0
				part(head, MaterialLibrary.box(Vector3(0.055, 0.06, 0.045)), armor,
					Vector3(sin(a) * 0.125, 0.31, cos(a) * 0.125), Vector3(0, rad_to_deg(a), 0))
			part(head, MaterialLibrary.box(Vector3(0.18, 0.022, 0.02)), dark, Vector3(0, 0.15, 0.138))
			part(head, MaterialLibrary.box(Vector3(0.022, 0.13, 0.02)), dark, Vector3(0, 0.11, 0.14))
			if umbral:
				for s in [-1.0, 1.0]:
					part(head, MaterialLibrary.cylinder(0.0, 0.03, 0.16, 8), trim, Vector3(0.12 * s, 0.24, 0), Vector3(0, 0, -50 * s))
		"winged":
			part(head, MaterialLibrary.sphere(0.128), armor, Vector3(0, 0.125, 0), Vector3.ZERO, Vector3(1, 1.1, 1.15))
			part(head, MaterialLibrary.box(Vector3(0.15, 0.02, 0.02)), dark, Vector3(0, 0.12, 0.138))
			part(head, MaterialLibrary.box(Vector3(0.022, 0.07, 0.26)), trim, Vector3(0, 0.255, 0))
			if umbral:
				for s in [-1.0, 1.0]:
					part(head, MaterialLibrary.cylinder(0.0, 0.034, 0.22, 8), MaterialLibrary.get_material("mask", color),
						Vector3(0.12 * s, 0.24, 0.02), Vector3(-25, 0, -38 * s))
					part(head, MaterialLibrary.cylinder(0.0, 0.018, 0.12, 8), MaterialLibrary.get_material("mask", color),
						Vector3(0.2 * s, 0.36, 0.0), Vector3(-10, 0, -8 * s))
			else:
				for s in [-1.0, 1.0]:
					part(head, MaterialLibrary.prism(Vector3(0.02, 0.24, 0.16), 0.0 if s > 0 else 1.0), trim,
						Vector3(0.13 * s, 0.22, -0.04), Vector3(0, 90, 18 * s))
				part(head, MaterialLibrary.capsule(0.035, 0.3), cloth_alt, Vector3(0, 0.3, -0.12), Vector3(-60, 0, 0))
		"mitre":
			if umbral:
				part(head, MaterialLibrary.sphere(0.135), cloth, Vector3(0, 0.12, -0.01), Vector3.ZERO, Vector3(1, 1.15, 1.15))
				part(head, MaterialLibrary.sphere(0.1), dark, Vector3(0, 0.11, 0.05), Vector3.ZERO, Vector3(0.9, 1.0, 0.8))
				for i in 5:
					var a := (i - 2) * 0.35
					part(head, MaterialLibrary.cylinder(0.0, 0.025, 0.2 + 0.06 * (2 - absi(i - 2)), 6), trim,
						Vector3(sin(a) * 0.1, 0.3, cos(a) * 0.06 - 0.02), Vector3(-8, 0, -rad_to_deg(a) * 0.6))
			else:
				part(head, MaterialLibrary.sphere(0.128), armor, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1.05, 1.1))
				part(head, MaterialLibrary.box(Vector3(0.15, 0.02, 0.02)), dark, Vector3(0, 0.12, 0.135))
				part(head, MaterialLibrary.cylinder(0.03, 0.125, 0.34, 4), cloth, Vector3(0, 0.36, 0), Vector3(0, 45, 0), Vector3(1, 1, 0.6))
				part(head, MaterialLibrary.box(Vector3(0.04, 0.3, 0.012)), trim, Vector3(0, 0.35, 0.05), Vector3(-9, 0, 0))
				part(head, MaterialLibrary.box(Vector3(0.12, 0.035, 0.012)), trim, Vector3(0, 0.38, 0.046), Vector3(-9, 0, 0))
		"queen":
			part(head, MaterialLibrary.sphere(0.105), MaterialLibrary.get_material("mask", color), Vector3(0, 0.12, 0.01), Vector3.ZERO, Vector3(0.88, 1.12, 0.95))
			part(head, MaterialLibrary.sphere(0.122), cloth_alt, Vector3(0, 0.14, -0.035), Vector3.ZERO, Vector3(1, 1.08, 1.05))
			for s in [-1.0, 1.0]:
				part(head, MaterialLibrary.box(Vector3(0.035, 0.008, 0.01)), dark, Vector3(0.035 * s, 0.135, 0.105), Vector3(0, 0, 8 * s))
			part(head, MaterialLibrary.torus(0.098, 0.112), MaterialLibrary.get_material("trim", color), Vector3(0, 0.215, 0), Vector3(-12, 0, 0))
			for i in 5:
				var a := (i - 2) * 0.42
				var h := 0.07 + (0.06 if i == 2 else 0.0)
				part(head, MaterialLibrary.cylinder(0.0, 0.016, h, 6), trim, Vector3(sin(a) * 0.105, 0.24 + h * 0.5, cos(a) * 0.105 - 0.015))
			part(head, MaterialLibrary.sphere(0.018), MaterialLibrary.get_material("gem", color), Vector3(0, 0.25, 0.1))
			var veil := part(head, MaterialLibrary.cloth_plane(0.26, 0.55), MaterialLibrary.cloth_material(color, true, 1.3, 0.04),
				Vector3(0, 0.2, -0.1), Vector3(14, 0, 0))
			veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		"king":
			part(head, MaterialLibrary.sphere(0.13), armor, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1.08, 1.12))
			part(head, MaterialLibrary.box(Vector3(0.16, 0.02, 0.02)), dark, Vector3(0, 0.125, 0.14))
			part(head, MaterialLibrary.box(Vector3(0.02, 0.1, 0.02)), dark, Vector3(0, 0.085, 0.142))
			var crown_mat := trim if not umbral else MaterialLibrary.get_material("mask", color)
			part(head, MaterialLibrary.torus(0.125, 0.15), crown_mat, Vector3(0, 0.215, 0))
			for i in 7:
				var a := TAU * i / 7.0
				var h := 0.09 if not umbral else 0.08 + 0.07 * float(i % 2)
				part(head, MaterialLibrary.cylinder(0.0, 0.026, h, 6), crown_mat,
					Vector3(sin(a) * 0.138, 0.235 + h * 0.5, cos(a) * 0.138), Vector3(rad_to_deg(cos(a)) * 0.15, 0, -rad_to_deg(sin(a)) * 0.15))
			part(head, MaterialLibrary.sphere(0.022), MaterialLibrary.get_material("gem", color), Vector3(0, 0.215, 0.148))
		_:
			part(head, MaterialLibrary.sphere(0.125), armor, Vector3(0, 0.12, 0))
	if umbral and kind != "queen":
		for s in [-1.0, 1.0]:
			part(head, MaterialLibrary.sphere(0.013), MaterialLibrary.get_material("eyes", color), Vector3(0.042 * s, 0.123, 0.128))


# --------------------------------------------------------------------------
# Weapons (hand space)
# --------------------------------------------------------------------------

static func build_weapon(hand: Node3D, kind: String, color: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"
	root.position = Vector3(0, -0.05, 0)
	hand.add_child(root)
	var steel := MaterialLibrary.get_material("steel", color)
	var trim := MaterialLibrary.get_material("trim", color)
	var leather := MaterialLibrary.get_material("leather", color)
	var wood := MaterialLibrary.get_material("wood", color)
	var tip_z := 1.0
	match kind:
		"sword", "falchion", "rapier", "greatsword":
			var length := 0.82
			var width := 0.055
			var guard := 0.2
			match kind:
				"falchion": length = 0.72; width = 0.085
				"rapier": length = 0.98; width = 0.022; guard = 0.14
				"greatsword": length = 1.18; width = 0.085; guard = 0.34
			var grip_len := 0.16 if kind != "greatsword" else 0.3
			part(root, MaterialLibrary.cylinder(0.018, 0.02, grip_len, 8), leather, Vector3(0, 0, -grip_len * 0.25), Vector3(90, 0, 0))
			part(root, MaterialLibrary.sphere(0.032), trim, Vector3(0, 0, -grip_len * 0.75 - 0.02))
			part(root, MaterialLibrary.box(Vector3(guard, 0.03, 0.04)), trim, Vector3(0, 0, grip_len * 0.25 + 0.02))
			if kind == "rapier":
				part(root, MaterialLibrary.torus(0.04, 0.055), trim, Vector3(0, 0, grip_len * 0.25 + 0.02), Vector3(90, 0, 0))
			var blade_start := grip_len * 0.25 + 0.04
			part(root, MaterialLibrary.box(Vector3(width, 0.014, length)), steel, Vector3(0, 0, blade_start + length * 0.5))
			part(root, MaterialLibrary.box(Vector3(width * 0.25, 0.016, length * 0.85)), trim if color == Chess.WHITE else MaterialLibrary.get_material("energy", color),
				Vector3(0, 0, blade_start + length * 0.45))
			part(root, MaterialLibrary.prism(Vector3(width, width * 2.2, 0.014)), steel, Vector3(0, 0, blade_start + length + width * 1.1), Vector3(90, 0, 0))
			if kind == "greatsword" and color == Chess.BLACK:
				for i in 3:
					part(root, MaterialLibrary.prism(Vector3(0.05, 0.07, 0.014)), steel,
						Vector3(width * 0.6, 0, blade_start + 0.3 + i * 0.3), Vector3(90, 0, -90))
			tip_z = blade_start + length + width * 2.0
		"spear", "glaive", "lance":
			var shaft := 1.8 if kind != "lance" else 2.5
			if kind == "lance":
				part(root, MaterialLibrary.cylinder(0.014, 0.06, shaft, 12), wood if color == Chess.BLACK else MaterialLibrary.get_material("cloth_alt", color),
					Vector3(0, 0, shaft * 0.5 - 0.2), Vector3(90, 0, 0))
				part(root, MaterialLibrary.cylinder(0.03, 0.12, 0.18, 12), trim, Vector3(0, 0, 0.12), Vector3(90, 0, 0))
				tip_z = shaft - 0.2
			else:
				part(root, MaterialLibrary.cylinder(0.02, 0.02, shaft, 8), wood, Vector3(0, 0, shaft * 0.5 - 0.55), Vector3(90, 0, 0))
				part(root, MaterialLibrary.cylinder(0.026, 0.026, 0.08, 8), trim, Vector3(0, 0, shaft - 0.58), Vector3(90, 0, 0))
				if kind == "spear":
					part(root, MaterialLibrary.prism(Vector3(0.09, 0.3, 0.02)), steel, Vector3(0, 0, shaft - 0.4), Vector3(90, 0, 0))
					tip_z = shaft - 0.25
				else:
					part(root, MaterialLibrary.prism(Vector3(0.14, 0.42, 0.018), 0.15), steel, Vector3(0.03, 0, shaft - 0.33), Vector3(90, 0, 0))
					part(root, MaterialLibrary.prism(Vector3(0.06, 0.1, 0.018)), steel, Vector3(-0.05, 0, shaft - 0.5), Vector3(90, 0, 90))
					tip_z = shaft - 0.12
		"hammer", "maul":
			part(root, MaterialLibrary.cylinder(0.025, 0.025, 1.15, 8), wood, Vector3(0, 0, 0.3), Vector3(90, 0, 0))
			part(root, MaterialLibrary.cylinder(0.03, 0.03, 0.2, 8), leather, Vector3(0, 0, -0.05), Vector3(90, 0, 0))
			var head_mat := steel
			part(root, MaterialLibrary.box(Vector3(0.15, 0.36, 0.15)), head_mat, Vector3(0, 0, 0.88))
			part(root, MaterialLibrary.box(Vector3(0.17, 0.05, 0.17)), trim, Vector3(0, 0.12, 0.88))
			part(root, MaterialLibrary.box(Vector3(0.17, 0.05, 0.17)), trim, Vector3(0, -0.12, 0.88))
			if kind == "maul":
				for s in [-1.0, 1.0]:
					part(root, MaterialLibrary.cylinder(0.0, 0.04, 0.12, 6), steel, Vector3(0, 0.23 * s, 0.88), Vector3(0, 0, 0 if s > 0 else 180))
			else:
				part(root, MaterialLibrary.prism(Vector3(0.1, 0.16, 0.03)), steel, Vector3(0, 0, 1.03), Vector3(90, 0, 0))
			tip_z = 0.95
		"staff", "scythe":
			part(root, MaterialLibrary.cylinder(0.022, 0.022, 1.75, 8), wood, Vector3(0, 0, 0.27), Vector3(90, 0, 0))
			part(root, MaterialLibrary.cylinder(0.03, 0.03, 0.06, 8), trim, Vector3(0, 0, 1.12), Vector3(90, 0, 0))
			if kind == "staff":
				part(root, MaterialLibrary.torus(0.085, 0.105), trim, Vector3(0, 0, 1.25), Vector3(0, 0, 0))
				part(root, MaterialLibrary.torus(0.085, 0.105), trim, Vector3(0, 0, 1.25), Vector3(0, 90, 90))
				part(root, MaterialLibrary.sphere(0.065), MaterialLibrary.get_material("energy", color), Vector3(0, 0, 1.25))
				tip_z = 1.25
			else:
				part(root, MaterialLibrary.prism(Vector3(0.07, 0.24, 0.07)), MaterialLibrary.get_material("gem", color), Vector3(0, 0, 1.28), Vector3(90, 0, 0))
				part(root, MaterialLibrary.prism(Vector3(0.5, 0.12, 0.016), 0.0), steel, Vector3(-0.24, 0, 1.13), Vector3(0, 0, 0))
				tip_z = 1.36
		_:
			push_warning("GearBuilder: unknown weapon " + kind)
	marker(root, "Tip", Vector3(0, 0, tip_z))
	marker(root, "Base", Vector3(0, 0, minf(0.15, tip_z * 0.2)))
	return root


# --------------------------------------------------------------------------
# Shields (face toward +Z, centred on the origin)
# --------------------------------------------------------------------------

static func build_shield(parent: Node3D, kind: String, color: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Shield"
	parent.add_child(root)
	var armor := MaterialLibrary.get_material("armor", color)
	var trim := MaterialLibrary.get_material("trim", color)
	var face := MaterialLibrary.get_material("cloth_alt", color)
	var emblem := MaterialLibrary.emblem_material(color)
	match kind:
		"round":
			part(root, MaterialLibrary.cylinder(0.27, 0.27, 0.035, 24), face, Vector3.ZERO, Vector3(90, 0, 0))
			part(root, MaterialLibrary.torus(0.255, 0.285), trim, Vector3.ZERO, Vector3(90, 0, 0))
			part(root, MaterialLibrary.half_sphere(0.07), trim, Vector3(0, 0, 0.018), Vector3(90, 0, 0))
			part(root, MaterialLibrary.quad(Vector2(0.36, 0.36)), emblem, Vector3(0, 0, 0.0185))
		"buckler":
			part(root, MaterialLibrary.cylinder(0.2, 0.2, 0.03, 20), armor, Vector3.ZERO, Vector3(90, 0, 0))
			part(root, MaterialLibrary.torus(0.19, 0.215), trim, Vector3.ZERO, Vector3(90, 0, 0))
			part(root, MaterialLibrary.cylinder(0.0, 0.05, 0.12, 8), trim, Vector3(0, 0, 0.07), Vector3(90, 0, 0))
		"kite":
			part(root, MaterialLibrary.box(Vector3(0.38, 0.4, 0.035)), face, Vector3(0, 0.1, 0))
			part(root, MaterialLibrary.prism(Vector3(0.38, 0.32, 0.035)), face, Vector3(0, -0.26, 0), Vector3(0, 0, 180))
			part(root, MaterialLibrary.box(Vector3(0.4, 0.035, 0.045)), trim, Vector3(0, 0.3, 0))
			part(root, MaterialLibrary.quad(Vector2(0.3, 0.3)), emblem, Vector3(0, 0.05, 0.019))
		"tower":
			part(root, MaterialLibrary.box(Vector3(0.52, 0.92, 0.05)), armor, Vector3.ZERO)
			part(root, MaterialLibrary.box(Vector3(0.44, 0.84, 0.01)), face, Vector3(0, 0, 0.028))
			for y in [-0.44, 0.44]:
				part(root, MaterialLibrary.box(Vector3(0.56, 0.045, 0.07)), trim, Vector3(0, y, 0))
			for x in [-0.26, 0.26]:
				part(root, MaterialLibrary.box(Vector3(0.045, 0.92, 0.07)), trim, Vector3(x, 0, 0))
			part(root, MaterialLibrary.quad(Vector2(0.38, 0.38)), emblem, Vector3(0, 0.06, 0.034))
			if color == Chess.BLACK:
				for y in [-0.25, 0.0, 0.25]:
					part(root, MaterialLibrary.cylinder(0.0, 0.035, 0.12, 6), trim, Vector3(0, y - 0.15, 0.08), Vector3(90, 0, 0))
	return root

class_name CombatVFX
extends Node3D
## Spawns short-lived combat effects (GPU particles, energy meshes, lights).
## Every effect frees itself; `speed_scale` follows the director's slow
## motion; particle counts honour graphics preset and accessibility settings.

const SLASH_SHADER := preload("res://shaders/slash_trail.gdshader")

var visual_layer: int = 1
var speed_scale: float = 1.0
var particle_scale: float = 1.0
var flash_scale: float = 1.0

var _active: Array[Dictionary] = []   # {node, life, age, update: Callable}
var _quad_materials: Dictionary = {}


func spawn(kind: String, at: Vector3, color: Color, strength: float = 1.0, extra: Dictionary = {}) -> Node3D:
	match kind:
		"sparks": return _sparks(at, color, strength)
		"impact": return _impact(at, color, strength)
		"shockwave": return _shockwave(at, color, strength)
		"dust": return _dust(at, strength)
		"slash_arc", "slash_burst": return _slash(at, color, strength, extra)
		"pillar", "pillar_warn": return _pillar(at, color, strength, kind == "pillar_warn")
		"lightning": return _lightning(at, color, strength)
		"magic_burst": return _magic_burst(at, color, strength)
		"charge": return _charge(at, color, strength)
		"dissolve": return _dissolve(at, color, strength)
		"dash_trail": return _dash_trail(at, color, strength, extra)
		"afterimage": return _afterimage(at, color, strength)
		"golden_wave": return _golden_wave(at, color, strength)
		"embers": return _embers(at, color, strength)
	push_warning("CombatVFX: unknown effect " + kind)
	return null


func _process(delta: float) -> void:
	var dt := delta * speed_scale
	var i := 0
	while i < _active.size():
		var fx: Dictionary = _active[i]
		var node: Node3D = fx["node"]
		if not is_instance_valid(node):
			_active.remove_at(i)
			continue
		fx["age"] = float(fx["age"]) + dt
		var k := clampf(float(fx["age"]) / float(fx["life"]), 0.0, 1.0)
		if fx.has("update"):
			(fx["update"] as Callable).call(node, k, dt)
		for p in node.find_children("*", "GPUParticles3D", true, false):
			(p as GPUParticles3D).speed_scale = speed_scale
		if k >= 1.0:
			node.queue_free()
			_active.remove_at(i)
			continue
		i += 1


func clear_all() -> void:
	for fx in _active:
		if is_instance_valid(fx["node"]):
			(fx["node"] as Node).queue_free()
	_active.clear()


func _track(node: Node3D, life: float, update: Callable = Callable()) -> void:
	add_child(node)
	_set_layers(node)
	var entry := {"node": node, "life": life, "age": 0.0}
	if update.is_valid():
		entry["update"] = update
	_active.append(entry)


func _set_layers(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = visual_layer
	if node is Light3D:
		(node as Light3D).light_cull_mask = visual_layer
	for c in node.get_children():
		_set_layers(c)


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

func _billboard_material(color: Color, energy: float, soft: bool = true) -> StandardMaterial3D:
	var key := "%s:%.2f:%s" % [color.to_html(), energy, soft]
	if _quad_materials.has(key):
		return _quad_materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.albedo_texture = _soft_dot() if soft else null
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_quad_materials[key] = m
	return m


static var _dot_texture: GradientTexture2D


static func _soft_dot() -> GradientTexture2D:
	if _dot_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_texture = GradientTexture2D.new()
		_dot_texture.gradient = g
		_dot_texture.fill = GradientTexture2D.FILL_RADIAL
		_dot_texture.fill_from = Vector2(0.5, 0.5)
		_dot_texture.fill_to = Vector2(0.5, 0.0)
		_dot_texture.width = 64
		_dot_texture.height = 64
	return _dot_texture


func _particles(amount: int, lifetime: float, size: Vector2, color: Color, energy: float,
		velocity: Vector2, spread: float, gravity: Vector3, direction: Vector3 = Vector3.UP,
		streak: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(amount * particle_scale))
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.speed_scale = speed_scale
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = velocity.x
	pm.initial_velocity_max = velocity.y
	pm.gravity = gravity
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	if streak:
		pm.particle_flag_align_y = true
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = _billboard_material(color, energy, not streak)
	if streak:
		var m := (quad.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		quad.material = m
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _light(color: Color, energy: float, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy * flash_scale
	l.omni_range = range_m
	l.shadow_enabled = false
	return l


func _energy_mesh(mesh: Mesh, color: Color, intensity: float, ring: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MaterialLibrary.energy_material(color, intensity, ring)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _fade_light(light: OmniLight3D, start_energy: float, k: float) -> void:
	light.light_energy = start_energy * pow(1.0 - k, 2.0)


# --------------------------------------------------------------------------
# Effects
# --------------------------------------------------------------------------

func _sparks(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var hot := color.lerp(Color(1.0, 0.85, 0.5), 0.6)
	root.add_child(_particles(int(48 * s) + 12, 0.45, Vector2(0.025, 0.22), hot, 4.0,
		Vector2(4.0, 9.0) * (0.7 + s * 0.5), 180.0, Vector3(0, -9.0, 0), Vector3.UP, true))
	root.add_child(_particles(6, 0.18, Vector2(0.5, 0.5) * (0.6 + s), hot, 3.0, Vector2(0.0, 0.3), 180.0, Vector3.ZERO))
	var light := _light(hot, 4.0 * s, 4.0)
	root.add_child(light)
	_track(root, 0.6, func(n: Node3D, k: float, _dt: float) -> void: _fade_light(light, 4.0 * s, minf(1.0, k * 2.5)))
	return root


func _impact(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var shell := _energy_mesh(MaterialLibrary.sphere(0.5), color, 3.0)
	root.add_child(shell)
	root.add_child(_particles(int(30 * s) + 10, 0.6, Vector2(0.03, 0.3), color.lerp(Color.WHITE, 0.4), 4.0,
		Vector2(5.0, 12.0) * s, 180.0, Vector3(0, -6, 0), Vector3.UP, true))
	var light := _light(color, 8.0 * s, 6.0)
	root.add_child(light)
	_track(root, 0.5, func(n: Node3D, k: float, _dt: float) -> void:
		shell.scale = Vector3.ONE * (0.4 + k * 2.6 * s)
		(shell.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 - k)
		_fade_light(light, 8.0 * s, k))
	return root


func _shockwave(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.05, at.z)
	var ring := _energy_mesh(MaterialLibrary.cylinder(1.0, 1.0, 0.25, 48), color, 4.0, true)
	ring.position.y = 0.12
	root.add_child(ring)
	var disc := _energy_mesh(MaterialLibrary.torus(0.85, 1.0), color.lerp(Color.WHITE, 0.3), 3.0)
	root.add_child(disc)
	var dust := _particles(int(40 * s) + 10, 1.1, Vector2(0.9, 0.9), Color(0.6, 0.55, 0.5), 0.35,
		Vector2(3.0, 6.0) * s, 90.0, Vector3(0, -1.0, 0), Vector3.UP)
	(dust.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	(dust.process_material as ParticleProcessMaterial).emission_ring_radius = 0.6
	(dust.process_material as ParticleProcessMaterial).emission_ring_inner_radius = 0.3
	(dust.process_material as ParticleProcessMaterial).emission_ring_height = 0.1
	(dust.process_material as ParticleProcessMaterial).emission_ring_axis = Vector3.UP
	(dust.draw_pass_1.surface_get_material(0) as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	root.add_child(dust)
	var light := _light(color, 6.0 * s, 8.0)
	light.position.y = 0.6
	root.add_child(light)
	_track(root, 1.1, func(n: Node3D, k: float, _dt: float) -> void:
		var r := 0.3 + ease(k, 0.4) * 5.5 * s
		ring.scale = Vector3(r, 1.0 - k * 0.7, r)
		disc.scale = Vector3(r * 0.95, 1.0, r * 0.95)
		(ring.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 - k)
		(disc.material_override as ShaderMaterial).set_shader_parameter("fade", (1.0 - k) * 0.8)
		_fade_light(light, 6.0 * s, k))
	return root


func _dust(at: Vector3, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.1, at.z)
	var p := _particles(int(24 * s) + 6, 1.4, Vector2(0.7, 0.7) * (0.6 + s * 0.6), Color(0.55, 0.5, 0.45), 0.3,
		Vector2(0.8, 2.2), 75.0, Vector3(0, 0.25, 0), Vector3.UP)
	(p.draw_pass_1.surface_get_material(0) as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	root.add_child(p)
	_track(root, 1.5)
	return root


## Crescent arc mesh oriented toward `extra.facing` (horizontal slash).
func _slash(at: Vector3, color: Color, s: float, extra: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var facing: Vector3 = extra.get("facing", Vector3.RIGHT)
	if facing.length() > 0.01:
		root.look_at_from_position(at, at + facing, Vector3.UP)
	var mesh := _arc_mesh(1.3 * s, 0.35 * s, 200.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = SLASH_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("intensity", 4.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(randf_range(-35, 35), 0, randf_range(-25, 25))
	root.add_child(mi)
	var light := _light(color, 5.0 * s, 5.0)
	root.add_child(light)
	_track(root, 0.45, func(n: Node3D, k: float, _dt: float) -> void:
		mat.set_shader_parameter("progress", ease(minf(1.0, k * 2.2), 0.5) * 1.6)
		mat.set_shader_parameter("fade", 1.0 - maxf(0.0, k - 0.4) / 0.6)
		_fade_light(light, 5.0 * s, k))
	return root


static func _arc_mesh(radius: float, width: float, degrees: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var start := deg_to_rad(-degrees * 0.5)
	var span := deg_to_rad(degrees)
	for i in segments:
		var u0 := float(i) / segments
		var u1 := float(i + 1) / segments
		var a0 := start + span * u0
		var a1 := start + span * u1
		var w0 := width * sin(u0 * PI)
		var w1 := width * sin(u1 * PI)
		var p0i := Vector3(sin(a0), 0, -cos(a0)) * (radius - w0 * 0.5)
		var p0o := Vector3(sin(a0), 0, -cos(a0)) * (radius + w0 * 0.5)
		var p1i := Vector3(sin(a1), 0, -cos(a1)) * (radius - w1 * 0.5)
		var p1o := Vector3(sin(a1), 0, -cos(a1)) * (radius + w1 * 0.5)
		for v in [[p0i, Vector2(u0, 0)], [p0o, Vector2(u0, 1)], [p1o, Vector2(u1, 1)],
				[p0i, Vector2(u0, 0)], [p1o, Vector2(u1, 1)], [p1i, Vector2(u1, 0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _pillar(at: Vector3, color: Color, s: float, warn: bool) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.0, at.z)
	if warn:
		var glyph := _energy_mesh(MaterialLibrary.torus(1.0, 1.15), color, 3.0)
		glyph.position.y = 0.05
		root.add_child(glyph)
		_track(root, 0.6, func(n: Node3D, k: float, _dt: float) -> void:
			glyph.scale = Vector3.ONE * (1.6 - k * 0.8)
			glyph.rotation.y = k * 3.0)
		return root
	var beam := _energy_mesh(MaterialLibrary.cylinder(0.9, 0.9, 30.0, 24), color.lerp(Color.WHITE, 0.35), 5.0)
	beam.position.y = 15.0
	root.add_child(beam)
	var core := _energy_mesh(MaterialLibrary.cylinder(0.35, 0.35, 30.0, 16), Color.WHITE, 6.0)
	core.position.y = 15.0
	root.add_child(core)
	var motes := _particles(int(60 * s), 1.6, Vector2(0.12, 0.12), color, 4.0, Vector2(2.0, 7.0), 15.0, Vector3(0, 2, 0))
	(motes.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	(motes.process_material as ParticleProcessMaterial).emission_sphere_radius = 1.0
	root.add_child(motes)
	var light := _light(color, 16.0 * s, 14.0)
	light.position.y = 2.0
	root.add_child(light)
	_track(root, 1.7, func(n: Node3D, k: float, _dt: float) -> void:
		var w := (1.0 - pow(k, 3.0)) * (0.4 + minf(1.0, k * 8.0) * 0.8) * s
		beam.scale = Vector3(w, 1, w)
		core.scale = Vector3(w, 1, w)
		_fade_light(light, 16.0 * s, k))
	return root


func _lightning(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var bolt_color := color.lerp(Color(0.85, 0.9, 1.0), 0.5)
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = bolt_color * 3.0
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var light := _light(bolt_color, 14.0 * s, 12.0)
	light.position.y = 2.0
	root.add_child(light)
	_build_bolt(im, 9.0, 0.09 * s)
	root.add_child(_sparks_child(bolt_color, s))
	_track(root, 0.5, func(n: Node3D, k: float, _dt: float) -> void:
		if randf() < 0.35:
			_build_bolt(im, 9.0, 0.09 * s)
		mat.albedo_color = bolt_color * 3.0 * (1.0 - k)
		_fade_light(light, 14.0 * s, k))
	return root


func _sparks_child(color: Color, s: float) -> GPUParticles3D:
	return _particles(int(30 * s) + 8, 0.5, Vector2(0.03, 0.25), color, 4.0, Vector2(3, 8), 180.0, Vector3(0, -8, 0), Vector3.UP, true)


static func _build_bolt(im: ImmediateMesh, height: float, width: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Vector3.ZERO
	var steps := 14
	for i in steps:
		var next := Vector3(randf_range(-0.45, 0.45), height * float(i + 1) / steps, randf_range(-0.45, 0.45))
		var w := width * (1.0 - float(i) / steps * 0.5)
		var side := Vector3(w, 0, 0)
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
		im.surface_add_vertex(next + side)
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(next + side)
		im.surface_add_vertex(next - side)
		var side_z := Vector3(0, 0, w)
		im.surface_add_vertex(p - side_z)
		im.surface_add_vertex(p + side_z)
		im.surface_add_vertex(next + side_z)
		im.surface_add_vertex(p - side_z)
		im.surface_add_vertex(next + side_z)
		im.surface_add_vertex(next - side_z)
		p = next
	im.surface_end()


func _magic_burst(at: Vector3, color: Color, s: float) -> Node3D:
	var root := _impact(at, color, s)
	var ring := _energy_mesh(MaterialLibrary.torus(0.6, 0.75), color, 3.0)
	ring.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(ring)
	_set_layers(ring)
	var motes := _particles(int(36 * s) + 6, 0.9, Vector2(0.1, 0.1), color.lerp(Color.WHITE, 0.3), 4.0,
		Vector2(1.5, 4.0), 180.0, Vector3(0, 1.2, 0))
	root.add_child(motes)
	_set_layers(motes)
	return root


func _charge(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var orb := _energy_mesh(MaterialLibrary.sphere(0.18), color, 4.0)
	root.add_child(orb)
	var motes := _particles(int(30 * s) + 6, 0.6, Vector2(0.06, 0.06), color, 5.0, Vector2(-2.5, -1.5), 180.0, Vector3.ZERO)
	(motes.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	(motes.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.9
	motes.explosiveness = 0.2
	root.add_child(motes)
	var light := _light(color, 3.0, 3.0)
	root.add_child(light)
	_track(root, 0.6, func(n: Node3D, k: float, _dt: float) -> void:
		orb.scale = Vector3.ONE * (0.4 + k * 1.2)
		_fade_light(light, 3.0, 1.0 - k))
	return root


func _dissolve(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at - Vector3(0, 0.6, 0)
	var motes := _particles(int(90 * s) + 10, 2.2, Vector2(0.07, 0.07), color, 3.0, Vector2(0.3, 1.2), 30.0, Vector3(0, 1.4, 0))
	(motes.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(motes.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.7, 0.4, 0.7)
	motes.explosiveness = 0.15
	motes.lifetime = 2.0
	root.add_child(motes)
	_track(root, 2.6)
	return root


func _dash_trail(at: Vector3, color: Color, s: float, extra: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var streaks := _particles(int(26 * s) + 6, 0.35, Vector2(0.04, 1.2), color.lerp(Color.WHITE, 0.4), 3.5,
		Vector2(0.2, 0.6), 30.0, Vector3.ZERO, Vector3.RIGHT, true)
	(streaks.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	(streaks.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.5
	root.add_child(streaks)
	_track(root, 0.6)
	return root


func _afterimage(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at - Vector3(0, 0.3, 0)
	var ghost := _energy_mesh(MaterialLibrary.capsule(0.35, 1.7), color, 1.2)
	root.add_child(ghost)
	_track(root, 0.35, func(n: Node3D, k: float, _dt: float) -> void:
		(ghost.material_override as ShaderMaterial).set_shader_parameter("fade", (1.0 - k) * 0.7))
	return root


func _golden_wave(at: Vector3, color: Color, s: float) -> Node3D:
	var root := _shockwave(Vector3(at.x, 0, at.z), color, s)
	var slash := _slash(at, color, s * 1.3, {})
	slash.rotation_degrees.z = 90.0
	return root


func _embers(at: Vector3, color: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var p := _particles(int(40 * s), 3.0, Vector2(0.05, 0.05), color, 4.0, Vector2(0.2, 0.8), 60.0, Vector3(0, 0.5, 0))
	p.explosiveness = 0.0
	root.add_child(p)
	_track(root, 3.2)
	return root


## Persistent aura shell around a fighter; caller removes it.
func make_aura(color: Color) -> Node3D:
	var root := Node3D.new()
	var shell := _energy_mesh(MaterialLibrary.capsule(0.75, 2.6), color, 1.6)
	shell.position.y = 1.1
	root.add_child(shell)
	var motes := GPUParticles3D.new()
	motes.amount = maxi(4, int(40 * particle_scale))
	motes.lifetime = 1.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.7
	pm.emission_ring_inner_radius = 0.4
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3.ZERO
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.5)
	var m := _billboard_material(color, 4.0, false).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = m
	motes.draw_pass_1 = quad
	root.add_child(motes)
	var light := _light(color, 3.0, 5.0)
	light.position.y = 1.2
	root.add_child(light)
	add_child(root)
	_set_layers(root)
	return root

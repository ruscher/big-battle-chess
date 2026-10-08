class_name BattleArena
extends Node3D
## The "Arena of Fate": a dusk colosseum where captures are fought out. It
## lives on its own render layer with its own lights and Environment, so it
## never affects the board scene and costs nothing while hidden.

const LAYER := 2
const BOARD_SHADER := preload("res://shaders/board_square.gdshader")

var environment: Environment
var key_light: DirectionalLight3D
var rim_light: DirectionalLight3D

var _braziers: Array[OmniLight3D] = []
var _mode: String = "normal"
var _mode_color := Color.WHITE
var _key_goal := Color(1.0, 0.72, 0.5)
var _key_energy_goal: float = 1.6
var _rim_goal := Color(0.45, 0.55, 1.0)
var _rim_energy_goal: float = 1.2
var _ambient_goal: float = 0.5
var _flash: float = 0.0
var _floor_material: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	_build_environment()
	_build_geometry()
	_apply_layers(self)
	visible = false


func set_board_theme(index: int) -> void:
	var t := BoardTheme.get_theme(index)
	_floor_material.set_shader_parameter("light_color", (t["light"] as Color).darkened(0.1))
	_floor_material.set_shader_parameter("dark_color", t["dark"])
	_floor_material.set_shader_parameter("vein_color", t["vein"])
	_floor_material.set_shader_parameter("grain", t["grain"])
	_floor_material.set_shader_parameter("vein_strength", t["vein_strength"])
	_floor_material.set_shader_parameter("light_roughness", maxf(0.3, t["light_roughness"]))
	_floor_material.set_shader_parameter("dark_roughness", maxf(0.3, t["dark_roughness"]))


func _apply_layers(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = LAYER
	if node is Light3D:
		(node as Light3D).light_cull_mask = LAYER
	for c in node.get_children():
		_apply_layers(c)


func _build_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.09, 0.06, 0.16)
	sky_mat.sky_horizon_color = Color(0.85, 0.36, 0.2)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.04, 0.03, 0.04)
	sky_mat.ground_horizon_color = Color(0.45, 0.2, 0.14)
	sky_mat.sun_angle_max = 8.0
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.55, 0.32, 0.25)
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.4
	environment.volumetric_fog_density = 0.012
	environment.volumetric_fog_albedo = Color(0.9, 0.7, 0.6)
	environment.volumetric_fog_emission = Color(0.05, 0.02, 0.03)
	environment.ssao_enabled = true
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.08

	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-16, -58, 0)
	key_light.light_color = _key_goal
	key_light.light_energy = _key_energy_goal
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 40.0
	add_child(key_light)
	rim_light = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-30, 125, 0)
	rim_light.light_color = _rim_goal
	rim_light.light_energy = _rim_energy_goal
	add_child(rim_light)


func _stone_material(color: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	m.normal_enabled = true
	m.normal_texture = tex
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	add_child(mi)
	return mi


func _build_geometry() -> void:
	var stone := _stone_material(Color(0.42, 0.38, 0.35))
	var dark_stone := _stone_material(Color(0.2, 0.18, 0.18))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.68, 0.32)
	gold.metallic = 1.0
	gold.roughness = 0.3

	# Platform with a giant chessboard inlay: the fight happens "inside" the square.
	_mesh(MaterialLibrary.cylinder(11.0, 11.6, 1.0, 64), stone, Vector3(0, -0.5, 0))
	_mesh(MaterialLibrary.cylinder(12.4, 13.2, 0.6, 64), dark_stone, Vector3(0, -1.0, 0))
	_mesh(MaterialLibrary.cylinder(14.2, 15.5, 0.6, 64), stone, Vector3(0, -1.5, 0))
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(14.0, 14.0)
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = BOARD_SHADER
	_floor_material.set_shader_parameter("clearcoat_amount", 0.3)
	_mesh(floor_plane, _floor_material, Vector3(0, 0.002, 0), Vector3(0, 45, 0))
	_mesh(MaterialLibrary.torus(10.6, 11.0), gold, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	set_board_theme(0)

	# Ring of monoliths, some of them broken.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 12:
		var a := TAU * i / 12.0 + 0.13
		var r := 16.0
		var h := rng.randf_range(6.0, 9.5) if i % 3 != 1 else rng.randf_range(2.5, 4.0)
		var p := Vector3(sin(a) * r, h * 0.5 - 1.2, cos(a) * r)
		var pillar := _mesh(MaterialLibrary.box(Vector3(1.4, h, 1.4)), stone, p, Vector3(rng.randf_range(-3, 3), rad_to_deg(a), rng.randf_range(-3, 3)))
		pillar.position.y = h * 0.5 - 1.2
		_mesh(MaterialLibrary.box(Vector3(1.8, 0.4, 1.8)), dark_stone, Vector3(p.x, -1.0, p.z), Vector3(0, rad_to_deg(a), 0))
		if i % 3 != 1:
			_mesh(MaterialLibrary.box(Vector3(1.9, 0.45, 1.9)), dark_stone, Vector3(p.x, h - 1.2 + 0.2, p.z), Vector3(0, rad_to_deg(a), 0))
			# Faction banners alternate around the ring.
			var color := i % 2
			var banner := _mesh(MaterialLibrary.cloth_plane(1.1, 3.6), MaterialLibrary.cloth_material(color, true, float(i), 0.12),
				Vector3(sin(a) * (r - 0.75), h - 1.6, cos(a) * (r - 0.75)), Vector3(0, rad_to_deg(a) + 180.0, 0))
			banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			_mesh(MaterialLibrary.quad(Vector2(0.8, 0.8)), MaterialLibrary.emblem_material(color, 0.6),
				Vector3(sin(a) * (r - 0.78), h - 2.6, cos(a) * (r - 0.78)), Vector3(0, rad_to_deg(a) + 180.0, 0))
		else:
			for k in 3:
				_mesh(MaterialLibrary.box(Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.4, 0.8), rng.randf_range(0.5, 1.1))), stone,
					Vector3(p.x + rng.randf_range(-1.5, 1.5), -0.8, p.z + rng.randf_range(-1.5, 1.5)),
					Vector3(rng.randf_range(0, 40), rng.randf_range(0, 180), rng.randf_range(0, 40)))

	# Braziers with fire and flickering light.
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(sin(a) * 12.2, 0, cos(a) * 12.2)
		_mesh(MaterialLibrary.cylinder(0.25, 0.35, 1.2, 12), dark_stone, p + Vector3(0, -0.1, 0))
		_mesh(MaterialLibrary.cylinder(0.65, 0.3, 0.45, 16), gold, p + Vector3(0, 0.7, 0))
		var fire := _fire_particles()
		fire.position = p + Vector3(0, 0.95, 0)
		add_child(fire)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.25)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = p + Vector3(0, 1.6, 0)
		light.shadow_enabled = i % 2 == 0
		add_child(light)
		_braziers.append(light)

	# Distant mountains frame the horizon.
	for i in 18:
		var a := TAU * i / 18.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(110.0, 150.0)
		var h := rng.randf_range(25.0, 60.0)
		var m := _mesh(MaterialLibrary.cylinder(0.0, rng.randf_range(25.0, 45.0), h, 6), _stone_material(Color(0.12, 0.09, 0.12), 1.0),
			Vector3(sin(a) * r, h * 0.5 - 8.0, cos(a) * r), Vector3(0, rng.randf_range(0, 60), 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Floating embers.
	var embers := GPUParticles3D.new()
	embers.amount = 160
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	embers.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 16, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 14)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.15, 0.05, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	embers.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.albedo_color = Color(3.0, 1.2, 0.4)
	quad.material = em
	embers.draw_pass_1 = quad
	add_child(embers)


func _fire_particles() -> GPUParticles3D:
	var fire := GPUParticles3D.new()
	fire.amount = 48
	fire.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.1))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	pm.scale_curve = scale_tex
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.4, 1))
	g.add_point(0.4, Color(1.0, 0.35, 0.1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.05, 0.02, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = CombatVFX._soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(2.5, 2.0, 1.6)
	quad.material = m
	fire.draw_pass_1 = quad
	return fire


## Lighting moods driven by the battle: normal, charge, finisher, victory.
func set_light_mode(mode: String, color: Color = Color.WHITE) -> void:
	_mode = mode
	_mode_color = color
	match mode:
		"charge":
			_key_goal = Color(0.6, 0.5, 0.55)
			_key_energy_goal = 0.55
			_rim_goal = color
			_rim_energy_goal = 3.2
			_ambient_goal = 0.22
		"finisher":
			_flash = 1.0 * Settings.flash_scale()
			_key_goal = Color(1.0, 0.72, 0.5)
			_key_energy_goal = 1.6
			_rim_goal = color
			_rim_energy_goal = 2.0
			_ambient_goal = 0.5
		"victory":
			_key_goal = Color(1.0, 0.82, 0.55)
			_key_energy_goal = 2.0
			_rim_goal = color.lerp(Color.WHITE, 0.3)
			_rim_energy_goal = 1.8
			_ambient_goal = 0.6
		_:
			_key_goal = Color(1.0, 0.72, 0.5)
			_key_energy_goal = 1.6
			_rim_goal = Color(0.45, 0.55, 1.0)
			_rim_energy_goal = 1.2
			_ambient_goal = 0.5


func reset_lighting() -> void:
	set_light_mode("normal")
	key_light.light_color = _key_goal
	key_light.light_energy = _key_energy_goal
	rim_light.light_color = _rim_goal
	rim_light.light_energy = _rim_energy_goal
	environment.ambient_light_energy = _ambient_goal
	_flash = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var w := 1.0 - exp(-delta * 4.0)
	key_light.light_color = key_light.light_color.lerp(_key_goal, w)
	key_light.light_energy = lerpf(key_light.light_energy, _key_energy_goal + _flash * 4.0, w * 3.0)
	rim_light.light_color = rim_light.light_color.lerp(_rim_goal, w)
	rim_light.light_energy = lerpf(rim_light.light_energy, _rim_energy_goal, w)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, _ambient_goal, w)
	_flash = maxf(0.0, _flash - delta * 2.5)
	for i in _braziers.size():
		_braziers[i].light_energy = 2.0 + sin(_time * 11.0 + i * 1.7) * 0.25 + sin(_time * 23.0 + i) * 0.15

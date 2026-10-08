class_name HallEnvironment
extends Node3D
## Procedural medieval settings around the board. Each preset changes the
## architecture details, the light mood and the sky, but always keeps the
## board the brightest, clearest element of the frame.

const FLOOR_SHADER := preload("res://shaders/board_square.gdshader")

const PRESETS := [
	{
		"id": "royal_hall", "name_key": "ENV_ROYAL_HALL", "roof": true,
		"sky_top": Color(0.05, 0.05, 0.08), "sky_horizon": Color(0.2, 0.16, 0.14),
		"ambient": Color(0.55, 0.45, 0.38), "ambient_energy": 0.35,
		"sun_color": Color(1.0, 0.86, 0.68), "sun_energy": 1.25, "sun_rot": Vector3(-48, -32, 0),
		"fill_color": Color(0.45, 0.55, 0.85), "fill_energy": 0.35,
		"fog": Color(0.3, 0.24, 0.2), "fog_density": 0.004, "vol_fog": 0.018, "vol_albedo": Color(1.0, 0.9, 0.8),
		"stone": Color(0.42, 0.38, 0.34), "trim": Color(0.85, 0.65, 0.32),
		"window": Color(1.0, 0.85, 0.6), "fire": Color(1.0, 0.6, 0.28), "torch_energy": 2.4,
		"floor_light": Color(0.42, 0.38, 0.34), "floor_dark": Color(0.26, 0.23, 0.21),
	},
	{
		"id": "shadow_fortress", "name_key": "ENV_SHADOW_FORTRESS", "roof": true,
		"sky_top": Color(0.02, 0.01, 0.03), "sky_horizon": Color(0.12, 0.04, 0.08),
		"ambient": Color(0.35, 0.25, 0.45), "ambient_energy": 0.3,
		"sun_color": Color(0.7, 0.62, 0.95), "sun_energy": 1.0, "sun_rot": Vector3(-55, 40, 0),
		"fill_color": Color(0.9, 0.2, 0.25), "fill_energy": 0.45,
		"fog": Color(0.12, 0.06, 0.12), "fog_density": 0.008, "vol_fog": 0.03, "vol_albedo": Color(0.8, 0.6, 1.0),
		"stone": Color(0.2, 0.19, 0.22), "trim": Color(0.55, 0.12, 0.16),
		"window": Color(0.85, 0.15, 0.25), "fire": Color(0.85, 0.35, 1.0), "torch_energy": 2.2,
		"floor_light": Color(0.22, 0.21, 0.24), "floor_dark": Color(0.1, 0.09, 0.11),
	},
	{
		"id": "cathedral", "name_key": "ENV_CATHEDRAL", "roof": true,
		"sky_top": Color(0.15, 0.2, 0.35), "sky_horizon": Color(0.6, 0.62, 0.7),
		"ambient": Color(0.55, 0.58, 0.7), "ambient_energy": 0.45,
		"sun_color": Color(1.0, 0.95, 0.85), "sun_energy": 1.5, "sun_rot": Vector3(-38, -70, 0),
		"fill_color": Color(0.7, 0.5, 1.0), "fill_energy": 0.3,
		"fog": Color(0.45, 0.45, 0.55), "fog_density": 0.003, "vol_fog": 0.025, "vol_albedo": Color(1.0, 0.95, 0.9),
		"stone": Color(0.62, 0.6, 0.56), "trim": Color(0.8, 0.7, 0.45),
		"window": Color(0.5, 0.65, 1.0), "fire": Color(1.0, 0.75, 0.45), "torch_energy": 1.6,
		"floor_light": Color(0.7, 0.68, 0.64), "floor_dark": Color(0.36, 0.34, 0.33),
	},
	{
		"id": "dawn_ruins", "name_key": "ENV_DAWN_RUINS", "roof": false,
		"sky_top": Color(0.22, 0.35, 0.6), "sky_horizon": Color(1.0, 0.68, 0.45),
		"ambient": Color(0.75, 0.68, 0.62), "ambient_energy": 0.6,
		"sun_color": Color(1.0, 0.78, 0.55), "sun_energy": 1.7, "sun_rot": Vector3(-14, -105, 0),
		"fill_color": Color(0.5, 0.65, 1.0), "fill_energy": 0.4,
		"fog": Color(0.8, 0.66, 0.58), "fog_density": 0.006, "vol_fog": 0.015, "vol_albedo": Color(1.0, 0.85, 0.75),
		"stone": Color(0.55, 0.52, 0.46), "trim": Color(0.6, 0.62, 0.5),
		"window": Color(1.0, 0.8, 0.6), "fire": Color(1.0, 0.6, 0.3), "torch_energy": 1.4,
		"floor_light": Color(0.5, 0.48, 0.42), "floor_dark": Color(0.36, 0.34, 0.3),
	},
]

var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var preset_index: int = 0

var _content: Node3D
var _torches: Array[OmniLight3D] = []
var _torch_energy: float = 2.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


static func count() -> int:
	return PRESETS.size()


static func name_key(index: int) -> String:
	return PRESETS[clampi(index, 0, PRESETS.size() - 1)]["name_key"]


func build(index: int, world_env: WorldEnvironment) -> void:
	preset_index = clampi(index, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[preset_index]
	if _content:
		_content.queue_free()
	_torches.clear()
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)
	_rng.seed = 4242 + preset_index
	_build_environment(p, world_env)
	_build_architecture(p)
	_torch_energy = p["torch_energy"]


func _build_environment(p: Dictionary, world_env: WorldEnvironment) -> void:
	environment = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = p["sky_top"]
	sm.sky_horizon_color = p["sky_horizon"]
	sm.ground_horizon_color = p["sky_horizon"]
	sm.ground_bottom_color = (p["sky_top"] as Color).darkened(0.5)
	sm.sun_angle_max = 12.0
	sky.sky_material = sm
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = p["ambient"]
	environment.ambient_light_energy = p["ambient_energy"]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_hdr_threshold = 1.2
	environment.fog_enabled = true
	environment.fog_light_color = p["fog"]
	environment.fog_density = p["fog_density"]
	environment.fog_aerial_perspective = 0.3
	environment.volumetric_fog_density = p["vol_fog"]
	environment.volumetric_fog_albedo = p["vol_albedo"]
	environment.volumetric_fog_length = 48.0
	environment.volumetric_fog_ambient_inject = 0.2
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.05
	world_env.environment = environment

	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 45.0
		sun.directional_shadow_blend_splits = true
		sun.light_cull_mask = 1
		add_child(sun)
		fill = DirectionalLight3D.new()
		fill.name = "Fill"
		fill.light_cull_mask = 1
		add_child(fill)
	sun.rotation_degrees = p["sun_rot"]
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.light_volumetric_fog_energy = 1.4
	fill.rotation_degrees = Vector3(-25, (p["sun_rot"] as Vector3).y + 180.0, 0)
	fill.light_color = p["fill_color"]
	fill.light_energy = p["fill_energy"]


func _stone(color: Color, scale: float = 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.88
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 5.0
	m.normal_enabled = true
	m.normal_texture = tex
	m.normal_scale = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	_content.add_child(mi)
	return mi


func _build_architecture(p: Dictionary) -> void:
	var stone := _stone(p["stone"])
	var dark := _stone((p["stone"] as Color).darkened(0.35))
	var trim := StandardMaterial3D.new()
	trim.albedo_color = p["trim"]
	trim.metallic = 0.9
	trim.roughness = 0.35
	var roofed: bool = p["roof"]
	var ruins: bool = not roofed

	# Floor of large flagstones (reuses the board shader with many cells).
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	floor_mat.set_shader_parameter("light_color", p["floor_light"])
	floor_mat.set_shader_parameter("dark_color", p["floor_dark"])
	floor_mat.set_shader_parameter("vein_color", (p["floor_light"] as Color).darkened(0.3))
	floor_mat.set_shader_parameter("vein_strength", 0.25)
	floor_mat.set_shader_parameter("vein_scale", 6.0)
	floor_mat.set_shader_parameter("light_roughness", 0.75)
	floor_mat.set_shader_parameter("dark_roughness", 0.8)
	floor_mat.set_shader_parameter("clearcoat_amount", 0.15 if preset_index != 2 else 0.45)
	floor_mat.set_shader_parameter("groove_width", 0.025)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(64, 64)
	_mesh(floor_mesh, floor_mat, Vector3(0, -0.53, 0))

	# Dais under the board.
	_mesh(MaterialLibrary.cylinder(7.0, 7.4, 0.5, 8), stone, Vector3(0, -0.78, 0), Vector3(0, 22.5, 0))
	_mesh(MaterialLibrary.cylinder(7.8, 8.4, 0.3, 8), dark, Vector3(0, -0.68, 0), Vector3(0, 22.5, 0))
	_mesh(MaterialLibrary.torus(7.0, 7.2), trim, Vector3(0, -0.53, 0), Vector3(0, 22.5, 0), Vector3(1, 0.4, 1))

	# Colonnades on both sides.
	for side in [-1.0, 1.0]:
		for i in 5:
			var z := -16.0 + i * 8.0
			var x: float = side * 14.0
			var broken := ruins and _rng.randf() < 0.45
			var h := 13.0 if not broken else _rng.randf_range(3.0, 8.0)
			_column(Vector3(x, -0.53, z), h, stone, dark, trim, broken)
			if not broken and i % 2 == 0:
				_banner(Vector3(x - side * 0.95, 9.5, z), side, 0 if side < 0 else 1)
			if i % 2 == 1:
				_torch(Vector3(x - side * 0.9, 3.4, z), p)

	# Back walls with tall windows (light shafts through volumetric fog).
	if not ruins:
		for zsign in [-1.0, 1.0]:
			var wall_z: float = zsign * 22.0
			_mesh(MaterialLibrary.box(Vector3(36, 18, 1.5)), stone, Vector3(0, 8.5, wall_z))
			for k in 3:
				var wx := -9.0 + k * 9.0
				var glass := StandardMaterial3D.new()
				glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				glass.albedo_color = (p["window"] as Color) * (1.8 if preset_index != 1 else 1.2)
				if preset_index == 2:
					glass.albedo_color = [Color(0.5, 0.7, 2.0), Color(2.0, 0.6, 0.5), Color(1.6, 1.4, 0.5)][k]
				_mesh(MaterialLibrary.box(Vector3(3.0, 8.0, 0.3)), glass, Vector3(wx, 9.0, wall_z - zsign * 0.7))
				_mesh(MaterialLibrary.cylinder(1.5, 1.5, 0.32, 24), glass, Vector3(wx, 13.0, wall_z - zsign * 0.7), Vector3(90, 0, 0))
				_mesh(MaterialLibrary.box(Vector3(0.25, 11.5, 0.5)), dark, Vector3(wx, 10.0, wall_z - zsign * 0.85))
				_mesh(MaterialLibrary.box(Vector3(3.4, 0.25, 0.5)), dark, Vector3(wx, 9.5, wall_z - zsign * 0.85))
				# Shaft of light from each window.
				var spot := SpotLight3D.new()
				spot.light_color = glass.albedo_color.clamp(Color(0, 0, 0), Color(1, 1, 1))
				spot.light_energy = 6.0
				spot.spot_range = 32.0
				spot.spot_angle = 14.0
				spot.light_volumetric_fog_energy = 3.0
				spot.light_cull_mask = 1
				spot.position = Vector3(wx, 12.0, wall_z - zsign * 1.5)
				spot.look_at_from_position(spot.position, Vector3(wx * 0.3, -0.5, wall_z * 0.15))
				_content.add_child(spot)
		_mesh(MaterialLibrary.box(Vector3(1.5, 18, 46)), stone, Vector3(-18.5, 8.5, 0))
		_mesh(MaterialLibrary.box(Vector3(1.5, 18, 46)), stone, Vector3(18.5, 8.5, 0))
		var ceiling := _mesh(MaterialLibrary.box(Vector3(38, 1.0, 46)), dark, Vector3(0, 17.5, 0))
		ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 6:
			_mesh(MaterialLibrary.box(Vector3(36, 0.8, 0.8)), dark, Vector3(0, 16.6, -18 + i * 7.2))
		# Chandeliers.
		for z in [-7.0, 7.0]:
			_chandelier(Vector3(0, 11.0, z), trim, p)
	else:
		# Ruined outer walls and distant peaks under the dawn sky.
		for i in 10:
			var a := TAU * i / 10.0
			var r := 24.0 + _rng.randf_range(-2, 2)
			var h := _rng.randf_range(2.0, 9.0)
			_mesh(MaterialLibrary.box(Vector3(_rng.randf_range(4, 8), h, 1.4)), stone,
				Vector3(sin(a) * r, h * 0.5 - 0.5, cos(a) * r), Vector3(0, rad_to_deg(a), _rng.randf_range(-4, 4)))
		for i in 14:
			var a := TAU * i / 14.0
			var r := _rng.randf_range(90, 130)
			var h := _rng.randf_range(30, 70)
			var m := _mesh(MaterialLibrary.cylinder(0.0, _rng.randf_range(25, 45), h, 6), _stone(Color(0.35, 0.38, 0.48), 0.05),
				Vector3(sin(a) * r, h * 0.5 - 6.0, cos(a) * r), Vector3(0, _rng.randf_range(0, 60), 0))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in 4:
			var a := TAU * k / 4.0 + 0.4
			_torch(Vector3(sin(a) * 9.0, 1.2, cos(a) * 9.0), p, true)

	_dust_motes()


func _column(base: Vector3, h: float, stone: Material, dark: Material, trim: Material, broken: bool) -> void:
	_mesh(MaterialLibrary.box(Vector3(2.2, 0.6, 2.2)), dark, base + Vector3(0, 0.3, 0))
	_mesh(MaterialLibrary.cylinder(0.85, 0.95, 0.5, 20), stone, base + Vector3(0, 0.85, 0))
	_mesh(MaterialLibrary.cylinder(0.7, 0.78, h, 20), stone, base + Vector3(0, 1.1 + h * 0.5, 0),
		Vector3(0, 0, _rng.randf_range(-2, 2) if broken else 0.0))
	if not broken:
		_mesh(MaterialLibrary.cylinder(1.0, 0.75, 0.6, 20), stone, base + Vector3(0, 1.4 + h, 0))
		_mesh(MaterialLibrary.box(Vector3(2.3, 0.5, 2.3)), dark, base + Vector3(0, 1.9 + h, 0))
		_mesh(MaterialLibrary.torus(0.72, 0.8), trim, base + Vector3(0, 1.25 + h, 0))
	else:
		for k in 2:
			_mesh(MaterialLibrary.cylinder(0.7, 0.7, _rng.randf_range(1.0, 2.0), 20), stone,
				base + Vector3(_rng.randf_range(-2.5, 2.5), 0.6, _rng.randf_range(-2.5, 2.5)),
				Vector3(90, _rng.randf_range(0, 180), 0))


func _banner(pos: Vector3, side: float, color: int) -> void:
	var banner := _mesh(MaterialLibrary.cloth_plane(1.7, 6.0), MaterialLibrary.cloth_material(color, color == 0, _rng.randf() * 6.0, 0.08),
		pos, Vector3(0, 90.0 * side, 0))
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_mesh(MaterialLibrary.quad(Vector2(1.25, 1.25)), MaterialLibrary.emblem_material(color, 0.4),
		pos + Vector3(-side * 0.03, -1.9, 0), Vector3(0, 90.0 * side, 0))
	_mesh(MaterialLibrary.cylinder(0.06, 0.06, 2.1, 8), MaterialLibrary.get_material("trim", color), pos + Vector3(0, 0.05, 0), Vector3(90, 0, 0))


func _torch(pos: Vector3, p: Dictionary, brazier: bool = false) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.13, 0.12)
	metal.metallic = 0.8
	metal.roughness = 0.5
	if brazier:
		_mesh(MaterialLibrary.cylinder(0.18, 0.28, 1.6, 10), metal, pos + Vector3(0, -0.9, 0))
		_mesh(MaterialLibrary.cylinder(0.55, 0.25, 0.4, 14), metal, pos)
	else:
		_mesh(MaterialLibrary.cylinder(0.08, 0.05, 0.7, 8), metal, pos + Vector3(0, -0.25, 0), Vector3(0, 0, 0))
		_mesh(MaterialLibrary.cylinder(0.16, 0.1, 0.22, 10), metal, pos + Vector3(0, 0.12, 0))
	var fire := _fire(p["fire"])
	fire.position = pos + Vector3(0, 0.3, 0)
	_content.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = p["fire"]
	light.light_energy = p["torch_energy"]
	light.omni_range = 10.0
	light.omni_attenuation = 1.4
	light.light_cull_mask = 1
	light.shadow_enabled = false
	light.position = pos + Vector3(0, 0.6, 0)
	_content.add_child(light)
	_torches.append(light)


func _fire(color: Color) -> GPUParticles3D:
	var fire := GPUParticles3D.new()
	fire.amount = 36
	fire.lifetime = 0.8
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 1.2, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.9, 0.6, 1))
	g.add_point(0.35, Color(color.r, color.g, color.b, 0.9))
	g.set_color(g.get_point_count() - 1, Color(color.r * 0.3, color.g * 0.1, color.b * 0.1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = CombatVFX._soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(2.4, 2.0, 1.7)
	quad.material = m
	fire.draw_pass_1 = quad
	return fire


func _chandelier(pos: Vector3, trim: Material, p: Dictionary) -> void:
	_mesh(MaterialLibrary.torus(1.6, 1.75), trim, pos)
	_mesh(MaterialLibrary.cylinder(0.03, 0.03, 6.0, 6), trim, pos + Vector3(0, 3.0, 0))
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.95, 0.9, 0.8)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(3.0, 2.0, 1.0)
	for i in 10:
		var a := TAU * i / 10.0
		var c := pos + Vector3(sin(a) * 1.67, 0.15, cos(a) * 1.67)
		_mesh(MaterialLibrary.cylinder(0.05, 0.05, 0.25, 8), wax, c)
		_mesh(MaterialLibrary.sphere(0.04, 0.12, 6), flame, c + Vector3(0, 0.18, 0))
	var light := OmniLight3D.new()
	light.light_color = p["fire"]
	light.light_energy = 2.0
	light.omni_range = 14.0
	light.light_cull_mask = 1
	light.position = pos
	_content.add_child(light)
	_torches.append(light)


func _dust_motes() -> void:
	var motes := GPUParticles3D.new()
	motes.amount = 120
	motes.lifetime = 12.0
	motes.preprocess = 12.0
	motes.visibility_aabb = AABB(Vector3(-10, -1, -10), Vector3(20, 10, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8, 3, 8)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0.01, 0.005, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.15
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.9, 0.8, 0.6) * 0.8
	quad.material = m
	motes.draw_pass_1 = quad
	motes.position = Vector3(0, 3.5, 0)
	_content.add_child(motes)


func _process(delta: float) -> void:
	_time += delta
	for i in _torches.size():
		var l := _torches[i]
		l.light_energy = _torch_energy * (0.88 + 0.08 * sin(_time * 9.0 + i * 2.1) + 0.05 * sin(_time * 21.0 + i))

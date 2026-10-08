class_name MaterialLibrary
extends RefCounted
## Shared, cached materials and meshes. All 32 pieces reuse the same
## resources, which keeps VRAM low and lets the renderer batch state changes.

const CLOTH_SHADER := preload("res://shaders/cloth.gdshader")
const EMBLEM_SHADER := preload("res://shaders/emblem.gdshader")
const ENERGY_SHADER := preload("res://shaders/energy.gdshader")

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _hammered_normal: NoiseTexture2D
static var _fabric_noise: NoiseTexture2D


static func _hammered() -> NoiseTexture2D:
	if _hammered_normal == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.045
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		_hammered_normal = NoiseTexture2D.new()
		_hammered_normal.width = 256
		_hammered_normal.height = 256
		_hammered_normal.seamless = true
		_hammered_normal.as_normal_map = true
		_hammered_normal.bump_strength = 2.0
		_hammered_normal.noise = noise
	return _hammered_normal


static func _fabric() -> NoiseTexture2D:
	if _fabric_noise == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		noise.fractal_octaves = 3
		_fabric_noise = NoiseTexture2D.new()
		_fabric_noise.width = 128
		_fabric_noise.height = 128
		_fabric_noise.seamless = true
		_fabric_noise.as_normal_map = true
		_fabric_noise.bump_strength = 1.2
		_fabric_noise.noise = noise
	return _fabric_noise


## Kinds: armor, trim, cloth, cloth_alt, leather, dark (visor/gaps), eyes,
## energy, horse, mask, wood, steel (neutral bright blade), gem.
static func get_material(kind: String, color: int) -> Material:
	var key := "%s:%d" % [kind, color]
	if _materials.has(key):
		return _materials[key]
	var style := FactionStyle.get_style(color)
	var m := StandardMaterial3D.new()
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	match kind:
		"armor":
			m.albedo_color = style["armor"]
			m.metallic = style["armor_metallic"]
			m.roughness = style["armor_roughness"]
			m.normal_enabled = true
			m.normal_texture = _hammered()
			m.normal_scale = 0.18
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3, 3, 3)
		"trim":
			m.albedo_color = style["trim"]
			m.metallic = 1.0
			m.roughness = 0.28
		"cloth", "cloth_alt":
			m.albedo_color = style[kind]
			m.roughness = 0.88
			m.normal_enabled = true
			m.normal_texture = _fabric()
			m.normal_scale = 0.5
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(6, 6, 6)
			m.rim = 0.45
		"leather":
			m.albedo_color = style["leather"]
			m.roughness = 0.7
			m.normal_enabled = true
			m.normal_texture = _fabric()
			m.normal_scale = 0.35
			m.uv1_triplanar = true
		"dark":
			m.albedo_color = Color(0.02, 0.02, 0.025)
			m.roughness = 0.9
			m.rim_enabled = false
		"eyes":
			m.albedo_color = style["eyes"]
			m.emission_enabled = true
			m.emission = style["eyes"]
			m.emission_energy_multiplier = style["eye_glow"]
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"energy":
			m.albedo_color = style["energy"]
			m.emission_enabled = true
			m.emission = style["energy"]
			m.emission_energy_multiplier = 3.0
			m.roughness = 0.2
		"horse":
			m.albedo_color = style["horse"]
			m.roughness = 0.6
			m.metallic = 0.0
			m.normal_enabled = true
			m.normal_texture = _fabric()
			m.normal_scale = 0.25
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(2, 2, 2)
		"mask":
			m.albedo_color = style["mask"]
			m.metallic = 0.85 if color == 0 else 0.1
			m.roughness = 0.25 if color == 0 else 0.35
		"wood":
			m.albedo_color = Color(0.33, 0.21, 0.12) if color == 0 else Color(0.14, 0.09, 0.08)
			m.roughness = 0.65
		"steel":
			m.albedo_color = Color(0.86, 0.87, 0.9) if color == 0 else Color(0.35, 0.33, 0.38)
			m.metallic = 1.0
			m.roughness = 0.14 if color == 0 else 0.22
		"plinth_glow":
			var glow: Color = style["trim"] if color == 0 else style["energy_alt"]
			m.albedo_color = glow
			m.metallic = 0.8
			m.roughness = 0.3
			m.emission_enabled = true
			m.emission = glow
			m.emission_energy_multiplier = 0.8 if color == 0 else 1.6
		"gem":
			m.albedo_color = style["energy_alt"]
			m.emission_enabled = true
			m.emission = style["energy_alt"]
			m.emission_energy_multiplier = 2.5
			m.metallic = 0.3
			m.roughness = 0.05
		_:
			m.albedo_color = Color.MAGENTA
	_materials[key] = m
	return m


static func cloth_material(color: int, alt: bool, phase: float = 0.0, strength: float = 0.06) -> ShaderMaterial:
	var key := "cloth_shader:%d:%s:%.2f:%.2f" % [color, alt, phase, strength]
	if _materials.has(key):
		return _materials[key]
	var style := FactionStyle.get_style(color)
	var m := ShaderMaterial.new()
	m.shader = CLOTH_SHADER
	m.set_shader_parameter("albedo", style["cloth_alt" if alt else "cloth"])
	m.set_shader_parameter("trim_color", style["trim"])
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("wind_strength", strength)
	_materials[key] = m
	return m


static func emblem_material(color: int, glow: float = 0.0) -> ShaderMaterial:
	var key := "emblem:%d:%.2f" % [color, glow]
	if _materials.has(key):
		return _materials[key]
	var style := FactionStyle.get_style(color)
	var m := ShaderMaterial.new()
	m.shader = EMBLEM_SHADER
	m.set_shader_parameter("emblem", style["emblem"])
	m.set_shader_parameter("field", style["cloth_alt"])
	m.set_shader_parameter("charge", style["trim"] if color == 0 else style["energy_alt"])
	m.set_shader_parameter("glow", glow if glow > 0.0 else (0.0 if color == 0 else 1.5))
	_materials[key] = m
	return m


## Unique (non-cached) energy material, because VFX animate its uniforms.
static func energy_material(color: Color, intensity: float = 2.0, ring: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENERGY_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("ring_mode", 1.0 if ring else 0.0)
	return m


# --------------------------------------------------------------------------
# Mesh cache
# --------------------------------------------------------------------------

static func capsule(radius: float, height: float) -> Mesh:
	var key := "capsule:%.3f:%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = 16
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


static func cylinder(top: float, bottom: float, height: float, segments: int = 18) -> Mesh:
	var key := "cyl:%.3f:%.3f:%.3f:%d" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func sphere(radius: float, height: float = -1.0, segments: int = 18) -> Mesh:
	var h := radius * 2.0 if height < 0.0 else height
	var key := "sph:%.3f:%.3f:%d" % [radius, h, segments]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = h
		m.radial_segments = segments
		m.rings = maxi(6, segments / 2)
		_meshes[key] = m
	return _meshes[key]


static func half_sphere(radius: float) -> Mesh:
	var key := "hsph:%.3f" % radius
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius
		m.is_hemisphere = true
		m.radial_segments = 18
		m.rings = 8
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> Mesh:
	var key := "box:%.3f:%.3f:%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func prism(size: Vector3, left_to_right: float = 0.5) -> Mesh:
	var key := "prism:%.3f:%.3f:%.3f:%.2f" % [size.x, size.y, size.z, left_to_right]
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		m.left_to_right = left_to_right
		_meshes[key] = m
	return _meshes[key]


static func torus(inner: float, outer: float) -> Mesh:
	var key := "torus:%.3f:%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]


static func cloth_plane(width: float, length: float) -> Mesh:
	var key := "cloth:%.3f:%.3f" % [width, length]
	if not _meshes.has(key):
		var m := PlaneMesh.new()
		m.size = Vector2(width, length)
		m.subdivide_width = 6
		m.subdivide_depth = 12
		m.orientation = PlaneMesh.FACE_Z
		# Shift so the top edge (UV.y = 0) is the pivot.
		m.center_offset = Vector3(0, -length * 0.5, 0)
		_meshes[key] = m
	return _meshes[key]


static func quad(size: Vector2) -> Mesh:
	var key := "quad:%.3f:%.3f" % [size.x, size.y]
	if not _meshes.has(key):
		var m := QuadMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


## Releases cached resources (called on shutdown so nothing leaks at exit).
static func clear_caches() -> void:
	_materials.clear()
	_meshes.clear()
	_hammered_normal = null
	_fabric_noise = null

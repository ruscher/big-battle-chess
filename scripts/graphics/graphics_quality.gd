class_name GraphicsQuality
extends RefCounted
## Graphics presets. Each preset only toggles features the Forward+ renderer
## of Godot 4.7 really provides; the art direction (palette, lighting) stays
## identical, only cost/fidelity changes.

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CINEMATIC }

const NAME_KEYS := ["GFX_LOW", "GFX_MEDIUM", "GFX_HIGH", "GFX_ULTRA", "GFX_CINEMATIC"]


static func apply(env: Environment, viewport: Viewport, preset: int, render_scale: float, use_fsr: bool) -> void:
	var p := clampi(preset, 0, Preset.CINEMATIC)
	env.ssao_enabled = p >= Preset.MEDIUM
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = p >= Preset.ULTRA
	env.ssr_enabled = p >= Preset.HIGH
	env.ssr_max_steps = 48 if p < Preset.ULTRA else 96
	env.sdfgi_enabled = p >= Preset.ULTRA
	env.volumetric_fog_enabled = p >= Preset.HIGH
	env.glow_enabled = true
	env.glow_bloom = 0.05 if p >= Preset.MEDIUM else 0.0
	env.fog_enabled = true

	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][p]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p <= Preset.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = p >= Preset.HIGH
	viewport.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0, 0.0][p]
	viewport.positional_shadow_atlas_size = [1024, 2048, 4096, 4096, 8192][p]

	var scale := clampf(render_scale, 0.5, 1.0)
	if p == Preset.LOW:
		scale = minf(scale, 0.75)
	viewport.scaling_3d_scale = scale
	if scale < 0.999:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if use_fsr else Viewport.SCALING_3D_MODE_FSR
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096, 8192][p], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][p])
	RenderingServer.positional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][p])


## Whether depth of field should be used by cinematic cameras.
static func allows_dof(preset: int) -> bool:
	return preset >= Preset.HIGH


static func particle_budget(preset: int) -> float:
	return [0.35, 0.6, 1.0, 1.0, 1.3][clampi(preset, 0, 4)]

class_name BoardTheme
extends RefCounted
## Board material presets. Each theme is a set of uniforms for
## shaders/board_square.gdshader plus frame materials.

const THEMES := [
	{
		"id": "marble", "name_key": "BOARD_MARBLE",
		"light": Color(0.9, 0.88, 0.84), "dark": Color(0.1, 0.1, 0.11), "vein": Color(0.55, 0.55, 0.58),
		"vein_strength": 0.55, "vein_scale": 2.6, "grain": 0.0,
		"light_roughness": 0.12, "dark_roughness": 0.16, "light_metallic": 0.0, "dark_metallic": 0.0,
		"clearcoat": 0.8, "groove": Color(0.25, 0.2, 0.12),
		"frame": Color(0.16, 0.15, 0.15), "frame_roughness": 0.25, "frame_metallic": 0.0,
		"inlay": Color(0.95, 0.75, 0.38), "label": Color(0.95, 0.82, 0.55),
	},
	{
		"id": "carved_wood", "name_key": "BOARD_WOOD",
		"light": Color(0.72, 0.53, 0.32), "dark": Color(0.27, 0.15, 0.08), "vein": Color(0.45, 0.28, 0.14),
		"vein_strength": 0.6, "vein_scale": 1.6, "grain": 1.0,
		"light_roughness": 0.45, "dark_roughness": 0.5, "light_metallic": 0.0, "dark_metallic": 0.0,
		"clearcoat": 0.35, "groove": Color(0.08, 0.04, 0.02),
		"frame": Color(0.2, 0.11, 0.06), "frame_roughness": 0.55, "frame_metallic": 0.0,
		"inlay": Color(0.85, 0.65, 0.35), "label": Color(0.95, 0.8, 0.55),
	},
	{
		"id": "ancient_stone", "name_key": "BOARD_STONE",
		"light": Color(0.62, 0.6, 0.55), "dark": Color(0.26, 0.26, 0.27), "vein": Color(0.4, 0.38, 0.34),
		"vein_strength": 0.35, "vein_scale": 5.0, "grain": 0.0,
		"light_roughness": 0.8, "dark_roughness": 0.85, "light_metallic": 0.0, "dark_metallic": 0.0,
		"clearcoat": 0.0, "groove": Color(0.08, 0.08, 0.07),
		"frame": Color(0.3, 0.29, 0.27), "frame_roughness": 0.9, "frame_metallic": 0.0,
		"inlay": Color(0.5, 0.55, 0.45), "label": Color(0.85, 0.85, 0.75),
	},
	{
		"id": "gold_obsidian", "name_key": "BOARD_GOLD",
		"light": Color(0.95, 0.72, 0.32), "dark": Color(0.03, 0.03, 0.04), "vein": Color(1.0, 0.85, 0.5),
		"vein_strength": 0.25, "vein_scale": 3.5, "grain": 0.0,
		"light_roughness": 0.25, "dark_roughness": 0.05, "light_metallic": 1.0, "dark_metallic": 0.2,
		"clearcoat": 0.5, "groove": Color(0.3, 0.2, 0.05),
		"frame": Color(0.05, 0.05, 0.06), "frame_roughness": 0.1, "frame_metallic": 0.3,
		"inlay": Color(1.0, 0.78, 0.35), "label": Color(1.0, 0.85, 0.5),
	},
	{
		"id": "gothic", "name_key": "BOARD_GOTHIC",
		"light": Color(0.55, 0.5, 0.58), "dark": Color(0.12, 0.04, 0.06), "vein": Color(0.6, 0.1, 0.15),
		"vein_strength": 0.5, "vein_scale": 3.0, "grain": 0.0,
		"light_roughness": 0.3, "dark_roughness": 0.25, "light_metallic": 0.0, "dark_metallic": 0.1,
		"clearcoat": 0.6, "groove": Color(0.05, 0.0, 0.02),
		"frame": Color(0.08, 0.06, 0.08), "frame_roughness": 0.35, "frame_metallic": 0.4,
		"inlay": Color(0.7, 0.1, 0.18), "label": Color(0.9, 0.5, 0.55),
	},
	{
		"id": "viking", "name_key": "BOARD_VIKING",
		"light": Color(0.62, 0.5, 0.36), "dark": Color(0.18, 0.2, 0.22), "vein": Color(0.3, 0.22, 0.14),
		"vein_strength": 0.5, "vein_scale": 1.2, "grain": 1.0,
		"light_roughness": 0.65, "dark_roughness": 0.4, "light_metallic": 0.0, "dark_metallic": 0.6,
		"clearcoat": 0.0, "groove": Color(0.05, 0.04, 0.03),
		"frame": Color(0.24, 0.16, 0.1), "frame_roughness": 0.7, "frame_metallic": 0.0,
		"inlay": Color(0.6, 0.62, 0.66), "label": Color(0.8, 0.85, 0.9),
	},
	{
		"id": "royal", "name_key": "BOARD_ROYAL",
		"light": Color(0.93, 0.9, 0.85), "dark": Color(0.08, 0.13, 0.32), "vein": Color(0.8, 0.7, 0.45),
		"vein_strength": 0.3, "vein_scale": 2.2, "grain": 0.0,
		"light_roughness": 0.15, "dark_roughness": 0.15, "light_metallic": 0.0, "dark_metallic": 0.3,
		"clearcoat": 0.9, "groove": Color(0.85, 0.65, 0.3),
		"frame": Color(0.95, 0.75, 0.38), "frame_roughness": 0.25, "frame_metallic": 1.0,
		"inlay": Color(0.1, 0.15, 0.35), "label": Color(0.1, 0.12, 0.25),
	},
]


static func count() -> int:
	return THEMES.size()


static func get_theme(index: int) -> Dictionary:
	return THEMES[clampi(index, 0, THEMES.size() - 1)]


static func index_of(id: String) -> int:
	for i in THEMES.size():
		if THEMES[i]["id"] == id:
			return i
	return 0

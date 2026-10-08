extends Node
## Autoload "Settings": persistent user preferences (user://settings.cfg).
## Other systems read values here and listen to `changed` to re-apply.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"general": {"language": ""},
	"graphics": {"preset": 2, "fullscreen": false, "vsync": true, "fps_limit": 0, "render_scale": 1.0, "fsr": false},
	"audio": {"master": 0.85, "music": 0.65, "sfx": 0.9, "ambience": 0.6, "voice": 0.9, "ui": 0.7},
	"gameplay": {
		"cinematic_mode": 1, "cinematic_speed": 1.0, "show_legal_moves": true, "show_last_move": true,
		"auto_rotate_camera": true, "board_theme": 0, "environment": 0, "ai_level": 2,
		"clock_minutes": 0.0, "clock_increment": 0.0, "human_color": 0, "assist_hints": true,
	},
	"accessibility": {
		"camera_shake": 1.0, "reduce_flashes": false, "reduce_motion": false, "particles": 1.0,
		"ui_scale": 1.0,
	},
}

var _config := ConfigFile.new()
var _save_pending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _config.load(PATH) != OK:
		_config = ConfigFile.new()
	apply_window()
	apply_language()
	apply_ui_scale()


func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = DEFAULTS.get(section, {}).get(key)
	var value: Variant = _config.get_value(section, key, fallback)
	# Guard against hand-edited files with the wrong type.
	if fallback != null and typeof(value) != typeof(fallback):
		if typeof(fallback) == TYPE_FLOAT and typeof(value) == TYPE_INT:
			return float(value)
		if typeof(fallback) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			return int(value)
		return fallback
	return value


func set_value(section: String, key: String, value: Variant) -> void:
	if _config.has_section_key(section, key) and _config.get_value(section, key) == value:
		return
	_config.set_value(section, key, value)
	match section:
		"graphics":
			if key in ["fullscreen", "vsync", "fps_limit"]:
				apply_window()
		"general":
			if key == "language":
				apply_language()
		"accessibility":
			if key == "ui_scale":
				apply_ui_scale()
	changed.emit(section, key)
	if not _save_pending:
		_save_pending = true
		_save_deferred.call_deferred()


func reset_section(section: String) -> void:
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])


func _save_deferred() -> void:
	_save_pending = false
	var err := _config.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fullscreen: bool = get_value("graphics", "fullscreen")
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("graphics", "fps_limit"))


func apply_language() -> void:
	var lang: String = get_value("general", "language")
	if lang.is_empty():
		lang = OS.get_locale_language()
		lang = "pt_BR" if lang == "pt" else "en"
	TranslationServer.set_locale(lang)


func apply_ui_scale() -> void:
	var tree := get_tree()
	if tree and tree.root:
		tree.root.content_scale_factor = float(get_value("accessibility", "ui_scale"))


## Multiplier applied to camera shake (0 when reduced motion is on).
func shake_scale() -> float:
	if get_value("accessibility", "reduce_motion"):
		return 0.0
	return float(get_value("accessibility", "camera_shake"))


func flash_scale() -> float:
	return 0.25 if get_value("accessibility", "reduce_flashes") else 1.0


func particle_scale() -> float:
	return float(get_value("accessibility", "particles"))

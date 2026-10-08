class_name SettingsPanel
extends PanelContainer
## Settings screen (graphics, audio, gameplay, accessibility, language,
## controls). Every control writes straight to the Settings autoload, which
## persists and re-applies the value.

signal closed

const LANGUAGES := [["en", "LANG_EN"], ["pt_BR", "LANG_PT_BR"]]


func _ready() -> void:
	custom_minimum_size = Vector2(860, 640)
	var v := UiKit.vbox(14)
	add_child(v)
	v.add_child(UiKit.title("MENU_SETTINGS", 40))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_graphics())
	tabs.add_child(_audio())
	tabs.add_child(_gameplay())
	tabs.add_child(_accessibility())
	tabs.add_child(_controls())
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, ["TAB_GRAPHICS", "TAB_AUDIO", "TAB_GAMEPLAY", "TAB_ACCESSIBILITY", "TAB_CONTROLS"][i])
	var back := UiKit.button("BTN_BACK", func() -> void: closed.emit(), 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)
	UiKit.focus_first(tabs)


func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _graphics() -> Control:
	var v := _page("Graphics")
	v.add_child(UiKit.option_row("SET_PRESET", GraphicsQuality.NAME_KEYS, Settings.get_value("graphics", "preset"),
		func(i: int) -> void: Settings.set_value("graphics", "preset", i)))
	v.add_child(UiKit.check_row("SET_FULLSCREEN", Settings.get_value("graphics", "fullscreen"),
		func(b: bool) -> void: Settings.set_value("graphics", "fullscreen", b)))
	v.add_child(UiKit.check_row("SET_VSYNC", Settings.get_value("graphics", "vsync"),
		func(b: bool) -> void: Settings.set_value("graphics", "vsync", b)))
	var fps := [0, 30, 60, 120, 144]
	v.add_child(UiKit.option_row("SET_FPS_LIMIT", ["SET_UNLIMITED", "30", "60", "120", "144"],
		fps.find(int(Settings.get_value("graphics", "fps_limit"))),
		func(i: int) -> void: Settings.set_value("graphics", "fps_limit", fps[i])))
	v.add_child(UiKit.slider_row("SET_RENDER_SCALE", Settings.get_value("graphics", "render_scale"), 0.5, 1.0, 0.05,
		func(x: float) -> void: Settings.set_value("graphics", "render_scale", x)))
	v.add_child(UiKit.check_row("SET_FSR2", Settings.get_value("graphics", "fsr"),
		func(b: bool) -> void: Settings.set_value("graphics", "fsr", b)))
	var note := UiKit.label("SET_GFX_NOTE", 17, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v.get_parent()


func _audio() -> Control:
	var v := _page("Audio")
	for key in ["master", "music", "sfx", "ambience", "voice", "ui"]:
		var k: String = key
		v.add_child(UiKit.slider_row("SET_VOL_" + k.to_upper(), Settings.get_value("audio", k), 0.0, 1.0, 0.05,
			func(x: float) -> void: Settings.set_value("audio", k, x)))
	return v.get_parent()


func _gameplay() -> Control:
	var v := _page("Gameplay")
	v.add_child(UiKit.option_row("SET_CINEMATIC_MODE", CinematicMode.NAME_KEYS, Settings.get_value("gameplay", "cinematic_mode"),
		func(i: int) -> void: Settings.set_value("gameplay", "cinematic_mode", i)))
	v.add_child(UiKit.slider_row("SET_CINEMATIC_SPEED", Settings.get_value("gameplay", "cinematic_speed"), 0.5, 2.0, 0.25,
		func(x: float) -> void: Settings.set_value("gameplay", "cinematic_speed", x), false))
	v.add_child(UiKit.check_row("SET_SHOW_LEGAL", Settings.get_value("gameplay", "show_legal_moves"),
		func(b: bool) -> void: Settings.set_value("gameplay", "show_legal_moves", b)))
	v.add_child(UiKit.check_row("SET_SHOW_LAST", Settings.get_value("gameplay", "show_last_move"),
		func(b: bool) -> void: Settings.set_value("gameplay", "show_last_move", b)))
	v.add_child(UiKit.check_row("SET_AUTO_ROTATE", Settings.get_value("gameplay", "auto_rotate_camera"),
		func(b: bool) -> void: Settings.set_value("gameplay", "auto_rotate_camera", b)))
	v.add_child(UiKit.check_row("SET_HINTS", Settings.get_value("gameplay", "assist_hints"),
		func(b: bool) -> void: Settings.set_value("gameplay", "assist_hints", b)))
	var langs := []
	var current := 0
	for i in LANGUAGES.size():
		langs.append(LANGUAGES[i][1])
		if TranslationServer.get_locale().begins_with(LANGUAGES[i][0].left(2)):
			current = i
	v.add_child(UiKit.option_row("SET_LANGUAGE", langs, current,
		func(i: int) -> void: Settings.set_value("general", "language", LANGUAGES[i][0])))
	return v.get_parent()


func _accessibility() -> Control:
	var v := _page("Accessibility")
	v.add_child(UiKit.slider_row("SET_SHAKE", Settings.get_value("accessibility", "camera_shake"), 0.0, 1.5, 0.1,
		func(x: float) -> void: Settings.set_value("accessibility", "camera_shake", x)))
	v.add_child(UiKit.check_row("SET_REDUCE_FLASHES", Settings.get_value("accessibility", "reduce_flashes"),
		func(b: bool) -> void: Settings.set_value("accessibility", "reduce_flashes", b)))
	v.add_child(UiKit.check_row("SET_REDUCE_MOTION", Settings.get_value("accessibility", "reduce_motion"),
		func(b: bool) -> void: Settings.set_value("accessibility", "reduce_motion", b)))
	v.add_child(UiKit.slider_row("SET_PARTICLES", Settings.get_value("accessibility", "particles"), 0.0, 1.0, 0.1,
		func(x: float) -> void: Settings.set_value("accessibility", "particles", x)))
	v.add_child(UiKit.slider_row("SET_UI_SCALE", Settings.get_value("accessibility", "ui_scale"), 0.75, 1.5, 0.05,
		func(x: float) -> void: Settings.set_value("accessibility", "ui_scale", x), false))
	var note := UiKit.label("SET_MOTION_BLUR_NOTE", 17, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v.get_parent()


func _controls() -> Control:
	var v := _page("Controls")
	var rows := [
		["CTRL_SELECT", "CTRL_SELECT_KEYS"], ["CTRL_CURSOR", "CTRL_CURSOR_KEYS"],
		["CTRL_CAMERA", "CTRL_CAMERA_KEYS"], ["CTRL_ZOOM", "CTRL_ZOOM_KEYS"],
		["CTRL_SKIP", "CTRL_SKIP_KEYS"], ["CTRL_SPEED", "CTRL_SPEED_KEYS"],
		["CTRL_UNDO", "CTRL_UNDO_KEYS"], ["CTRL_PAUSE", "CTRL_PAUSE_KEYS"],
	]
	for r in rows:
		var row := UiKit.hbox(16)
		var a := UiKit.label(r[0], 21)
		a.custom_minimum_size = Vector2(280, 0)
		row.add_child(a)
		var b := UiKit.label(r[1], 19, UiTheme.MUTED)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		v.add_child(row)
	return v.get_parent()

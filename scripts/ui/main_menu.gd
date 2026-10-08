class_name MainMenu
extends Control
## Title screen over the live 3D board. Left: title and main actions.
## Right: the active sub-panel (new game, load, settings, chronicle, credits).
## Only implemented features are offered.

signal start_requested(config: GameConfig)
signal continue_requested
signal load_requested(slot: String)
signal replay_requested(pgn_path: String)
signal quit_requested
signal preview_changed(board_theme: int, environment: int)

var _content: CenterContainer
var _menu: VBoxContainer
var _continue_btn: Button
var _current: Control
var _cfg := GameConfig.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.015, 0.03, 0.92))
	grad.set_color(1, Color(0.02, 0.015, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var left := UiKit.vbox(14)
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_left = 80
	left.offset_right = 600
	left.offset_top = 70
	left.offset_bottom = -40
	add_child(left)
	var big := UiKit.title("BIG BATTLE", 74)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(big)
	var chess := UiKit.title("CHESS", 104, Color(1.0, 0.85, 0.52))
	chess.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chess.add_theme_constant_override("line_spacing", -20)
	left.add_child(chess)
	var tagline := UiKit.caption("MENU_TAGLINE", 19)
	left.add_child(tagline)
	left.add_child(UiKit.separator())

	_menu = UiKit.vbox(12)
	_menu.custom_minimum_size = Vector2(380, 0)
	left.add_child(_menu)
	_continue_btn = UiKit.button("MENU_CONTINUE", func() -> void: continue_requested.emit(), 380)
	_menu.add_child(_continue_btn)
	_menu.add_child(UiKit.button("MENU_NEW_GAME", func() -> void: _show(_new_game_panel()), 380))
	_menu.add_child(UiKit.button("MENU_LOAD_GAME", func() -> void: _show(_load_panel()), 380))
	_menu.add_child(UiKit.button("MENU_CHRONICLE", func() -> void: _show(_history_panel()), 380))
	_menu.add_child(UiKit.button("MENU_SETTINGS", func() -> void:
		var s := SettingsPanel.new()
		s.closed.connect(_close_panel)
		_show(s), 380))
	_menu.add_child(UiKit.button("MENU_CREDITS", func() -> void: _show(_credits_panel()), 380))
	_menu.add_child(UiKit.button("MENU_QUIT", func() -> void: quit_requested.emit(), 380))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var version := UiKit.caption("v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]], 14)
	left.add_child(version)

	_content = CenterContainer.new()
	_content.anchor_left = 0.42
	_content.anchor_right = 1.0
	_content.anchor_bottom = 1.0
	_content.offset_right = -40
	add_child(_content)
	refresh()


func refresh() -> void:
	_continue_btn.visible = SaveSystem.has_save(SaveSystem.AUTOSAVE)
	UiKit.focus_first(_menu)


func _show(panel: Control) -> void:
	if _current:
		_current.queue_free()
	_current = panel
	_content.add_child(panel)
	Audio.ui("open")
	UiKit.focus_first(panel)


func _close_panel() -> void:
	if _current:
		_current.queue_free()
		_current = null
	Audio.ui("back")
	UiKit.focus_first(_menu)


func _unhandled_input(event: InputEvent) -> void:
	if visible and _current != null and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu")):
		_close_panel()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# New game
# --------------------------------------------------------------------------

func _new_game_panel() -> Control:
	_cfg = GameConfig.from_settings()
	var p := UiKit.panel(Vector2(820, 0))
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.title("MENU_NEW_GAME", 40))
	var ai_rows: Array[Control] = []
	v.add_child(UiKit.option_row("NG_OPPONENT", ["NG_VS_AI", "NG_LOCAL", "NG_WATCH_AI"], 0, func(i: int) -> void:
		_cfg.opponent = [GameConfig.Opponent.AI, GameConfig.Opponent.LOCAL_PLAYER, GameConfig.Opponent.AI_VS_AI][i]
		for r in ai_rows:
			r.visible = _cfg.opponent != GameConfig.Opponent.LOCAL_PLAYER
		ai_rows[0].visible = _cfg.opponent == GameConfig.Opponent.AI))
	var side_row := UiKit.option_row("NG_SIDE", ["NG_SIDE_WHITE", "NG_SIDE_BLACK", "NG_SIDE_RANDOM"], _cfg.human_color, func(i: int) -> void:
		_cfg.human_color = i if i < 2 else randi() % 2
		Settings.set_value("gameplay", "human_color", _cfg.human_color))
	v.add_child(side_row)
	ai_rows.append(side_row)
	var levels := []
	for l in ChessAIPlayer.LEVELS:
		levels.append(ChessAIPlayer.level_name_key(l))
	var level_row := UiKit.option_row("NG_DIFFICULTY", levels, _cfg.ai_level, func(i: int) -> void:
		_cfg.ai_level = i
		Settings.set_value("gameplay", "ai_level", i))
	v.add_child(level_row)
	ai_rows.append(level_row)
	var gm_note := UiKit.label("NG_GM_NOTE" if not ChessAIPlayer.grandmaster_available() else "NG_GM_FOUND", 16, UiTheme.MUTED)
	gm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(gm_note)
	ai_rows.append(gm_note)

	var desc := UiKit.label(CinematicMode.DESC_KEYS[_cfg.cinematic_mode], 17, UiTheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(UiKit.option_row("NG_CINEMATICS", CinematicMode.NAME_KEYS, _cfg.cinematic_mode, func(i: int) -> void:
		_cfg.cinematic_mode = i
		desc.text = CinematicMode.DESC_KEYS[i]
		Settings.set_value("gameplay", "cinematic_mode", i)))
	v.add_child(desc)
	var boards := []
	for t in BoardTheme.THEMES:
		boards.append(t["name_key"])
	v.add_child(UiKit.option_row("NG_BOARD", boards, _cfg.board_theme, func(i: int) -> void:
		_cfg.board_theme = i
		Settings.set_value("gameplay", "board_theme", i)
		preview_changed.emit(_cfg.board_theme, _cfg.environment)))
	var envs := []
	for e in HallEnvironment.PRESETS:
		envs.append(e["name_key"])
	v.add_child(UiKit.option_row("NG_ENVIRONMENT", envs, _cfg.environment, func(i: int) -> void:
		_cfg.environment = i
		Settings.set_value("gameplay", "environment", i)
		preview_changed.emit(_cfg.board_theme, _cfg.environment)))
	var clocks := [[0.0, 0.0], [3.0, 2.0], [5.0, 0.0], [10.0, 0.0], [15.0, 10.0], [30.0, 0.0]]
	var clock_names := ["NG_CLOCK_NONE", "3 + 2", "5 + 0", "10 + 0", "15 + 10", "30 + 0"]
	var current_clock := 0
	for i in clocks.size():
		if is_equal_approx(clocks[i][0], _cfg.clock_minutes) and is_equal_approx(clocks[i][1], _cfg.clock_increment):
			current_clock = i
	v.add_child(UiKit.option_row("NG_CLOCK", clock_names, current_clock, func(i: int) -> void:
		_cfg.clock_minutes = clocks[i][0]
		_cfg.clock_increment = clocks[i][1]
		Settings.set_value("gameplay", "clock_minutes", _cfg.clock_minutes)
		Settings.set_value("gameplay", "clock_increment", _cfg.clock_increment)))
	v.add_child(UiKit.separator())
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button("BTN_BACK", _close_panel, 180))
	var start := UiKit.button("NG_START", func() -> void: start_requested.emit(_cfg), 260)
	start.add_theme_color_override("font_color", UiTheme.GOLD)
	row.add_child(start)
	return p


# --------------------------------------------------------------------------
# Load / chronicle / credits
# --------------------------------------------------------------------------

func _load_panel() -> Control:
	var p := UiKit.panel(Vector2(720, 520))
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.title("MENU_LOAD_GAME", 40))
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 20)
	v.add_child(list)
	var saves := SaveSystem.list_saves()
	for s in saves:
		var label: String = tr("SAVE_AUTOSAVE") if s["slot"] == SaveSystem.AUTOSAVE else str(s["slot"])
		list.add_item("%s   ·   %s" % [label, str(s["saved_at"]).replace("T", " ")])
	if saves.is_empty():
		v.add_child(UiKit.label("LOAD_EMPTY", 19, UiTheme.MUTED))
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button("BTN_BACK", _close_panel, 160))
	var del := UiKit.button("BTN_DELETE", func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			SaveSystem.delete_save(saves[sel[0]]["slot"])
			_show(_load_panel())
			refresh(), 160)
	row.add_child(del)
	var load := UiKit.button("BTN_LOAD", func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			load_requested.emit(saves[sel[0]]["slot"]), 200)
	row.add_child(load)
	list.item_activated.connect(func(i: int) -> void: load_requested.emit(saves[i]["slot"]))
	if not saves.is_empty():
		list.select(0)
	return p


func _history_panel() -> Control:
	var p := UiKit.panel(Vector2(780, 560))
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.title("MENU_CHRONICLE", 40))
	v.add_child(UiKit.label("CHRONICLE_DESC", 18, UiTheme.MUTED))
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 20)
	v.add_child(list)
	var games := SaveSystem.list_history()
	for g in games:
		list.add_item("%s  ·  %s  vs  %s  ·  %s  ·  %d %s" % [g["date"], g["white"], g["black"], g["result"], g["moves"], tr("CHRONICLE_PLIES")])
	if games.is_empty():
		v.add_child(UiKit.label("CHRONICLE_EMPTY", 19, UiTheme.MUTED))
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button("BTN_BACK", _close_panel, 160))
	row.add_child(UiKit.button("BTN_COPY_PGN", func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			DisplayServer.clipboard_set(FileAccess.get_file_as_string(games[sel[0]]["path"])), 200))
	row.add_child(UiKit.button("BTN_REPLAY", func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			replay_requested.emit(games[sel[0]]["path"]), 200))
	if not games.is_empty():
		list.select(0)
	return p


func _credits_panel() -> Control:
	var p := UiKit.panel(Vector2(820, 600))
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.title("MENU_CREDITS", 40))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 19)
	text.add_theme_font_size_override("bold_font_size", 20)
	text.text = tr("CREDITS_TEXT")
	v.add_child(text)
	var back := UiKit.button("BTN_BACK", _close_panel, 180)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)
	return p

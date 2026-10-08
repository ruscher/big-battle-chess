class_name Hud
extends Control
## In-game HUD: player cards (name, clock, captures, material), turn/check
## banner, move chronicle, action bar and contextual help. Hidden during
## arena battles so the cinematic owns the screen.

signal pause_requested

var session: GameSession

var _cards: Array[PanelContainer] = []
var _names: Array[Label] = []
var _clocks: Array[Label] = []
var _captures: Array[Label] = []
var _thinking: Array[Label] = []
var _banner: Label
var _help: Label
var _moves_text: RichTextLabel
var _moves_panel: PanelContainer
var _undo_btn: Button
var _redo_btn: Button
var _draw_btn: Button
var _resign_btn: Button
var _mode_select: OptionButton
var _bar: HBoxContainer
var _replay_bar: HBoxContainer
var _replay_auto: Button
var _replay_progress: Label
var _confirm: Control
var _hidden_for_battle: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	for color in 2:
		_build_card(color)
	_banner = UiKit.title("", 34)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 22
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_moves_panel = UiKit.panel(Vector2(220, 0))
	_moves_panel.anchor_left = 1.0
	_moves_panel.anchor_right = 1.0
	_moves_panel.anchor_top = 0.0
	_moves_panel.anchor_bottom = 1.0
	_moves_panel.offset_left = -244
	_moves_panel.offset_right = -24
	_moves_panel.offset_top = 170
	_moves_panel.offset_bottom = -96
	add_child(_moves_panel)
	var mv := UiKit.vbox(6)
	_moves_panel.add_child(mv)
	var chron := UiKit.caption("HUD_CHRONICLE", 17)
	chron.add_theme_color_override("font_color", UiTheme.GOLD)
	mv.add_child(chron)
	_moves_text = RichTextLabel.new()
	_moves_text.bbcode_enabled = true
	_moves_text.scroll_following = true
	_moves_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_moves_text.add_theme_font_size_override("normal_font_size", 20)
	_moves_text.add_theme_font_size_override("bold_font_size", 20)
	_moves_text.focus_mode = Control.FOCUS_NONE
	mv.add_child(_moves_text)

	_bar = UiKit.hbox(8)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -14
	add_child(_bar)
	_undo_btn = UiKit.button("HUD_UNDO", func() -> void: session.undo())
	_redo_btn = UiKit.button("HUD_REDO", func() -> void: session.redo())
	_draw_btn = UiKit.button("HUD_OFFER_DRAW", _on_draw)
	_resign_btn = UiKit.button("HUD_RESIGN", _on_resign)
	var cam_btn := UiKit.button("HUD_CAMERA", func() -> void:
		session.board_camera.reset_view(Chess.WHITE if session.board_camera.is_white_view() else Chess.BLACK))
	cam_btn.tooltip_text = "HUD_CAMERA_TIP"
	_mode_select = OptionButton.new()
	_mode_select.add_theme_font_size_override("font_size", 19)
	for key in CinematicMode.NAME_KEYS:
		_mode_select.add_item(key)
	_mode_select.tooltip_text = "HUD_BATTLE_MODE_TIP"
	_mode_select.item_selected.connect(func(i: int) -> void:
		session.set_cinematic_mode(i)
		Audio.ui("click"))
	var pause_btn := UiKit.button("HUD_MENU", func() -> void: pause_requested.emit())
	for b in [_undo_btn, _redo_btn, _draw_btn, _resign_btn, cam_btn, _mode_select, pause_btn]:
		_bar.add_child(b)

	_replay_bar = UiKit.hbox(8)
	_replay_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_replay_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_replay_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_replay_bar.offset_bottom = -22
	add_child(_replay_bar)
	_replay_bar.add_child(UiKit.button("REPLAY_PREV", func() -> void: session.replay_previous(), 150))
	_replay_bar.add_child(UiKit.button("REPLAY_NEXT", func() -> void: session.replay_next(), 150))
	_replay_auto = UiKit.button("REPLAY_AUTO", func() -> void: session.set_replay_autoplay(not session.replay_autoplay), 190)
	_replay_bar.add_child(_replay_auto)
	_replay_progress = UiKit.label("", 22, UiTheme.MUTED)
	_replay_bar.add_child(_replay_progress)
	var replay_mode := OptionButton.new()
	for key in CinematicMode.NAME_KEYS:
		replay_mode.add_item(key)
	replay_mode.select(int(Settings.get_value("gameplay", "cinematic_mode")))
	replay_mode.item_selected.connect(func(i: int) -> void: session.set_cinematic_mode(i))
	_replay_bar.add_child(replay_mode)
	_replay_bar.add_child(UiKit.button("HUD_MENU", func() -> void: pause_requested.emit()))
	_replay_bar.visible = false

	_help = UiKit.label("", 19, UiTheme.MUTED)
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.offset_top = -108
	_help.offset_bottom = -80
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help)


func _build_card(color: int) -> void:
	var card := UiKit.panel(Vector2(390, 0))
	card.anchor_left = 0.0 if color == Chess.WHITE else 1.0
	card.anchor_right = card.anchor_left
	card.offset_left = 24 if color == Chess.WHITE else -414
	card.offset_right = 414 if color == Chess.WHITE else -24
	card.offset_top = 20
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var v := UiKit.vbox(4)
	card.add_child(v)
	var top := UiKit.hbox(10)
	v.add_child(top)
	var crest := Label.new()
	crest.text = UiKit.glyph(Chess.KING, color)
	crest.add_theme_font_size_override("font_size", 34)
	crest.add_theme_color_override("font_color", UiTheme.DAWN if color == Chess.WHITE else UiTheme.UMBRAL)
	top.add_child(crest)
	var names := UiKit.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var name := UiKit.label("", 21)
	name.add_theme_font_override("font", UiTheme.title_font())
	name.clip_text = true
	names.add_child(name)
	var faction := UiKit.caption(FactionStyle.get_style(color)["name_key"], 14)
	names.add_child(faction)
	var clock := UiKit.label("", 30, UiTheme.PARCHMENT)
	clock.add_theme_font_override("font", UiTheme.title_font())
	top.add_child(clock)
	var thinking := UiKit.caption("HUD_THINKING", 15)
	thinking.add_theme_color_override("font_color", UiTheme.GOLD)
	thinking.visible = false
	v.add_child(thinking)
	var captures := UiKit.label("", 24, UiTheme.PARCHMENT)
	captures.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(captures)
	_cards.append(card)
	_names.append(name)
	_clocks.append(clock)
	_captures.append(captures)
	_thinking.append(thinking)


func bind(game_session: GameSession) -> void:
	session = game_session
	session.refresh_requested.connect(refresh)
	session.state_changed.connect(func(_s: GameSession.State) -> void: refresh())


func set_battle_mode(active: bool) -> void:
	_hidden_for_battle = active
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0 if active else 1.0, 0.3)


func refresh() -> void:
	if session == null or session.match_data == null:
		return
	var m := session.match_data
	var pos := m.position
	_mode_select.select(session.config.cinematic_mode)
	for color in 2:
		_names[color].text = session.player_name(color)
		var active := not m.is_over() and pos.side == color
		var box := _cards[color].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		box.border_color = (UiTheme.GOLD if active else UiTheme.GOLD_DIM)
		box.set_border_width_all(2 if active else 1)
		_cards[color].add_theme_stylebox_override("panel", box)
		_clocks[color].visible = session.clock.enabled
		_clocks[color].text = ChessClock.format_ms(session.clock.remaining_ms[color])
		_clocks[color].add_theme_color_override("font_color",
			UiTheme.DANGER if session.clock.remaining_ms[color] < 20_000 and session.clock.enabled else UiTheme.PARCHMENT)
		_thinking[color].visible = active and session.state == GameSession.State.AWAIT_AI or (active and session.state == GameSession.State.PRESENTING and session.ai.is_thinking and session.config.is_ai_color(color))
		var taken := m.captured_types(color)
		taken.sort()
		taken.reverse()
		var text := ""
		for t in taken:
			text += UiKit.glyph(t, color ^ 1)
		var diff := pos.material_count(color) - pos.material_count(color ^ 1)
		if diff > 0:
			text += "  +%d" % roundi(diff / 100.0)
		_captures[color].text = text
	_update_banner()
	_update_moves()
	_bar.visible = not session.is_replay
	_replay_bar.visible = session.is_replay
	if session.is_replay:
		var progress := session.replay_progress()
		_replay_progress.text = "%d / %d" % [progress.x, progress.y]
		_replay_auto.text = "REPLAY_PAUSE" if session.replay_autoplay else "REPLAY_AUTO"
		return
	_undo_btn.disabled = not session.can_undo()
	_redo_btn.visible = session.config.opponent == GameConfig.Opponent.LOCAL_PLAYER
	_redo_btn.disabled = not session.can_redo()
	_draw_btn.text = "HUD_CLAIM_DRAW" if session.can_claim_draw() else "HUD_OFFER_DRAW"
	_draw_btn.disabled = m.is_over() or session.state == GameSession.State.PRESENTING or session.config.opponent == GameConfig.Opponent.AI_VS_AI
	_resign_btn.disabled = m.is_over() or session.config.opponent == GameConfig.Opponent.AI_VS_AI


func _update_banner() -> void:
	var m := session.match_data
	var help := ""
	if m.is_over():
		_banner.text = _result_text()
		_banner.add_theme_color_override("font_color", UiTheme.GOLD)
		help = tr("HELP_GAME_OVER")
	else:
		var side := m.position.side
		var who := tr("TURN_WHITE") if side == Chess.WHITE else tr("TURN_BLACK")
		if m.position.is_in_check():
			_banner.text = tr("BANNER_CHECK") % who
			_banner.add_theme_color_override("font_color", UiTheme.DANGER)
		else:
			_banner.text = tr("BANNER_TURN") % who
			_banner.add_theme_color_override("font_color", UiTheme.DAWN if side == Chess.WHITE else UiTheme.UMBRAL)
		match session.state:
			GameSession.State.AWAIT_HUMAN:
				help = tr("HELP_SELECTED") if session.selected_square >= 0 else tr("HELP_SELECT_PIECE")
			GameSession.State.AWAIT_AI:
				help = tr("HELP_AI_THINKING")
			GameSession.State.PRESENTING:
				help = tr("HINT_SKIP_CINEMATIC")
			GameSession.State.PROMOTION:
				help = tr("HELP_PROMOTION")
		if m.draw_offer_from != -1:
			help = tr("HELP_DRAW_PENDING")
	_help.text = help if Settings.get_value("gameplay", "assist_hints") or m.is_over() else ""


func _result_text() -> String:
	var m := session.match_data
	match m.result:
		ChessMatch.Result.WHITE_WINS:
			return tr("RESULT_WHITE_WINS")
		ChessMatch.Result.BLACK_WINS:
			return tr("RESULT_BLACK_WINS")
		ChessMatch.Result.DRAW:
			return tr("RESULT_DRAW")
	return ""


func _update_moves() -> void:
	var m := session.match_data
	var text := ""
	var start := ChessPosition.new(m.start_fen)
	var number := start.fullmove_number
	for i in m.records.size():
		var r := m.records[i]
		if r.color == Chess.WHITE:
			text += "[color=#8f846f]%d.[/color] " % number
		elif i == 0:
			text += "[color=#8f846f]%d…[/color] " % number
		var san := r.san
		if r.is_capture():
			san = "[color=#ffcf7a]%s[/color]" % san
		if i == m.records.size() - 1:
			san = "[b]%s[/b]" % san
		text += san + "   "
		if r.color == Chess.BLACK:
			text += "\n"
			number += 1
	if m.is_over():
		text += "\n[color=#f5c466]%s[/color]" % m.result_string()
	_moves_text.text = text


func _on_draw() -> void:
	if session.can_claim_draw():
		session.claim_draw()
	else:
		session.offer_draw()


func _on_resign() -> void:
	confirm("CONFIRM_RESIGN", func() -> void: session.resign())


## Shows a themed yes/no dialog.
func confirm(question_key: String, on_yes: Callable, on_no: Callable = Callable()) -> void:
	if _confirm:
		_confirm.queue_free()
	_confirm = UiKit.center_overlay(self, 0.5)
	var center: CenterContainer = _confirm.get_node("Center")
	var p := UiKit.panel(Vector2(520, 0))
	center.add_child(p)
	var v := UiKit.vbox(18)
	p.add_child(v)
	var q := UiKit.label(question_key, 24)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(q)
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var dialog := _confirm
	var yes := UiKit.button("BTN_YES", func() -> void:
		dialog.queue_free()
		on_yes.call(), 160)
	var no := UiKit.button("BTN_NO", func() -> void:
		dialog.queue_free()
		if on_no.is_valid():
			on_no.call(), 160)
	row.add_child(yes)
	row.add_child(no)
	no.grab_focus.call_deferred()

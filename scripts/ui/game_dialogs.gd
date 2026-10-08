class_name GameDialogs
extends Control
## In-game modal layer: pause menu, promotion choice, game over, draw offer
## (local multiplayer) and toast notifications. Works while the tree is
## paused (process mode ALWAYS).

signal resume_requested
signal main_menu_requested
signal rematch_requested
signal quit_requested
signal promotion_chosen(piece_type: int)
signal promotion_cancelled
signal draw_answered(accept: bool)
signal save_requested(slot: String)

var session: GameSession
var _modal: Control
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	_toast = UiKit.label("", 24, UiTheme.PARCHMENT)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 86
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


func is_open() -> bool:
	return _modal != null and is_instance_valid(_modal)


func close() -> void:
	if is_open():
		_modal.queue_free()
	_modal = null


func toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _open(min_size: Vector2) -> VBoxContainer:
	close()
	_modal = UiKit.center_overlay(self, 0.55)
	var p := UiKit.panel(min_size)
	(_modal.get_node("Center") as CenterContainer).add_child(p)
	var v := UiKit.vbox(14)
	p.add_child(v)
	Audio.ui("open")
	return v


# --------------------------------------------------------------------------
# Pause
# --------------------------------------------------------------------------

func show_pause() -> void:
	var v := _open(Vector2(460, 0))
	v.add_child(UiKit.title("PAUSE_TITLE", 44))
	v.add_child(UiKit.button("PAUSE_RESUME", func() -> void: resume_requested.emit(), 400))
	var can_save := session != null and session.match_data != null and not session.match_data.is_over() and session.state != GameSession.State.REPLAY
	var save := UiKit.button("PAUSE_SAVE", _show_save, 400)
	save.disabled = not can_save
	v.add_child(save)
	v.add_child(UiKit.button("MENU_SETTINGS", _show_settings, 400))
	v.add_child(UiKit.button("PAUSE_MAIN_MENU", func() -> void:
		_confirm("CONFIRM_MAIN_MENU", func() -> void: main_menu_requested.emit()), 400))
	v.add_child(UiKit.button("MENU_QUIT", func() -> void:
		_confirm("CONFIRM_QUIT", func() -> void: quit_requested.emit()), 400))
	UiKit.focus_first(v)


func _show_settings() -> void:
	close()
	_modal = UiKit.center_overlay(self, 0.55)
	var s := SettingsPanel.new()
	s.closed.connect(show_pause)
	(_modal.get_node("Center") as CenterContainer).add_child(s)


func _show_save() -> void:
	var v := _open(Vector2(560, 0))
	v.add_child(UiKit.title("PAUSE_SAVE", 40))
	var edit := LineEdit.new()
	edit.text = "game_" + Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	edit.add_theme_font_size_override("font_size", 22)
	edit.max_length = 48
	v.add_child(edit)
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button("BTN_BACK", show_pause, 160))
	var do_save := func() -> void:
		var slot := edit.text.strip_edges().validate_filename()
		if slot.is_empty() or slot == SaveSystem.AUTOSAVE:
			Audio.ui("error")
			return
		save_requested.emit(slot)
		show_pause()
	row.add_child(UiKit.button("BTN_SAVE", do_save, 200))
	edit.text_submitted.connect(func(_t: String) -> void: do_save.call())
	edit.grab_focus.call_deferred()


func _confirm(key: String, on_yes: Callable) -> void:
	var v := _open(Vector2(520, 0))
	var q := UiKit.label(key, 24)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(q)
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UiKit.button("BTN_YES", on_yes, 160))
	var no := UiKit.button("BTN_NO", show_pause, 160)
	row.add_child(no)
	no.grab_focus.call_deferred()


# --------------------------------------------------------------------------
# Promotion
# --------------------------------------------------------------------------

func show_promotion(color: int) -> void:
	var v := _open(Vector2(640, 0))
	v.add_child(UiKit.title("PROMO_TITLE", 40))
	var sub := UiKit.label("PROMO_DESC", 19, UiTheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for type in [Chess.QUEEN, Chess.ROOK, Chess.BISHOP, Chess.KNIGHT]:
		var t: int = type
		var b := UiKit.button("%s\n%s" % [UiKit.glyph(t, color), tr(FactionStyle.unit_key(color, t))], func() -> void:
			close()
			promotion_chosen.emit(t), 140)
		b.custom_minimum_size = Vector2(140, 120)
		b.add_theme_font_size_override("font_size", 22)
		row.add_child(b)
	var cancel := UiKit.button("BTN_CANCEL", func() -> void:
		close()
		promotion_cancelled.emit(), 180)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cancel)
	UiKit.focus_first(row)


# --------------------------------------------------------------------------
# Draw offer (local multiplayer)
# --------------------------------------------------------------------------

func show_draw_offer(from_color: int) -> void:
	var v := _open(Vector2(560, 0))
	var who := tr("TURN_WHITE") if from_color == Chess.WHITE else tr("TURN_BLACK")
	var q := UiKit.label(tr("DRAW_OFFER_QUESTION") % who, 24)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UiKit.button("DRAW_ACCEPT", func() -> void:
		close()
		draw_answered.emit(true), 200))
	var decline := UiKit.button("DRAW_DECLINE", func() -> void:
		close()
		draw_answered.emit(false), 200)
	row.add_child(decline)
	decline.grab_focus.call_deferred()


# --------------------------------------------------------------------------
# Game over
# --------------------------------------------------------------------------

func show_game_over(m: ChessMatch, config: GameConfig) -> void:
	var v := _open(Vector2(620, 0))
	var title_key := "RESULT_DRAW"
	var color := UiTheme.PARCHMENT
	if m.result != ChessMatch.Result.DRAW:
		var winner := m.winner()
		if config.opponent == GameConfig.Opponent.AI:
			title_key = "RESULT_VICTORY" if winner == config.human_color else "RESULT_DEFEAT"
			color = UiTheme.GOLD if winner == config.human_color else UiTheme.DANGER
		else:
			title_key = "RESULT_WHITE_WINS" if winner == Chess.WHITE else "RESULT_BLACK_WINS"
			color = UiTheme.DAWN if winner == Chess.WHITE else UiTheme.UMBRAL
	v.add_child(UiKit.title(title_key, 56, color))
	var reason := UiKit.label(ChessMatch.REASON_KEYS[m.reason], 24, UiTheme.MUTED)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(reason)
	var stats := UiKit.label(tr("GAMEOVER_STATS") % [m.records.size(), m.captured_types(Chess.WHITE).size() + m.captured_types(Chess.BLACK).size()], 19, UiTheme.MUTED)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	v.add_child(UiKit.separator())
	v.add_child(UiKit.button("GAMEOVER_REMATCH", func() -> void:
		close()
		rematch_requested.emit(), 520))
	v.add_child(UiKit.button("GAMEOVER_REVIEW", close, 520))
	v.add_child(UiKit.button("BTN_COPY_PGN", func() -> void:
		DisplayServer.clipboard_set(m.to_pgn())
		toast(tr("MSG_PGN_COPIED")), 520))
	v.add_child(UiKit.button("PAUSE_MAIN_MENU", func() -> void:
		close()
		main_menu_requested.emit(), 520))
	UiKit.focus_first(v)

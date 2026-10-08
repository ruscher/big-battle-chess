class_name GameSession
extends Node
## Match flow state machine. Connects the authoritative ChessMatch with
## input (BoardView), the AI, the clock, the MovePresenter and the HUD.
##
## Order of operations for every move:
##   1. validate + commit in ChessMatch (the result is now final)
##   2. start the AI thinking for its reply (it can think during cinematics)
##   3. present the move (animation / battle; skippable)
##   4. autosave, then start the next turn

signal state_changed(state: State)
signal refresh_requested
signal move_committed(record: ChessMoveRecord)
signal game_finished(result: ChessMatch.Result, reason: ChessMatch.Reason)
signal promotion_requested(color: int)
signal draw_offer_received(from_color: int)
signal notify(text: String)
signal battle_active(active: bool)

enum State { INACTIVE, AWAIT_HUMAN, AWAIT_AI, PROMOTION, PRESENTING, GAME_OVER, REPLAY }

var config: GameConfig
var match_data: ChessMatch
var clock := ChessClock.new()
var state: State = State.INACTIVE
var board: BoardView
var board_camera: BoardCamera
var presenter: MovePresenter
var ai: ChessAIPlayer

var selected_square: int = -1
var _selected_moves := PackedInt32Array()
var _pending_promotion: Array[int] = []   # [from, to]
var _pending_ai_move: int = Chess.NO_MOVE
var _ai_requested: bool = false

## Replay mode: the full move list of an archived game and the cursor in it.
var is_replay: bool = false
var replay_autoplay: bool = false
var _replay_moves: Array[int] = []
var _replay_index: int = 0


func _ready() -> void:
	clock.flagged.connect(_on_flag)


func wire(board_view: BoardView, camera: BoardCamera, move_presenter: MovePresenter, ai_player: ChessAIPlayer) -> void:
	board = board_view
	board_camera = camera
	presenter = move_presenter
	ai = ai_player
	board.square_clicked.connect(_on_square_clicked)
	board.square_hovered.connect(func(_sq: int) -> void: _refresh_marks())
	board.cancel_requested.connect(_deselect)
	ai.move_ready.connect(_on_ai_move)
	presenter.battle_started.connect(func() -> void: battle_active.emit(true))
	presenter.battle_finished.connect(func() -> void: battle_active.emit(false))


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

func start_new(new_config: GameConfig) -> void:
	var m := ChessMatch.new()
	if not m.reset(new_config.start_fen):
		m.reset()
	var c := ChessClock.new()
	c.configure(new_config.clock_minutes, new_config.clock_increment)
	_begin(new_config, m, c)
	Audio.play_sfx("game_start", -3.0)


func start_from_save(data: Dictionary) -> void:
	_begin(data["config"], data["match"], data["clock"])


func _begin(new_config: GameConfig, m: ChessMatch, c: ChessClock) -> void:
	_stop_ai()
	is_replay = false
	replay_autoplay = false
	config = new_config
	match_data = m
	clock.enabled = c.enabled
	clock.initial_ms = c.initial_ms
	clock.increment_ms = c.increment_ms
	clock.remaining_ms = c.remaining_ms.duplicate()
	clock.active_color = m.side_to_move()
	clock.running = false
	match_data.tags["White"] = player_name(Chess.WHITE)
	match_data.tags["Black"] = player_name(Chess.BLACK)
	match_data.tags["Event"] = "Big Battle Chess"
	selected_square = -1
	_selected_moves = PackedInt32Array()
	_pending_ai_move = Chess.NO_MOVE
	presenter.cinematic_mode = config.cinematic_mode
	presenter.board_theme = config.board_theme
	ai.level = config.ai_level as ChessAIPlayer.Level
	board.sync_to_position(match_data.position)
	board.flipped_view = config.opponent == GameConfig.Opponent.AI and config.human_color == Chess.BLACK
	board_camera.reset_view(_view_color())
	Audio.music("board")
	Audio.ambience(true)
	if match_data.is_over():
		_set_state(State.GAME_OVER)
	else:
		_start_turn()
	refresh_requested.emit()


func end_session() -> void:
	_stop_ai()
	is_replay = false
	replay_autoplay = false
	presenter.skip()
	clock.running = false
	_set_state(State.INACTIVE)
	board.input_enabled = false
	board.clear_marks()


func _set_state(new_state: State) -> void:
	state = new_state
	board.input_enabled = state == State.AWAIT_HUMAN
	clock.running = clock.enabled and state in [State.AWAIT_HUMAN, State.AWAIT_AI, State.PROMOTION]
	_refresh_marks()
	state_changed.emit(state)


func _process(delta: float) -> void:
	if state in [State.AWAIT_HUMAN, State.AWAIT_AI, State.PROMOTION]:
		clock.tick(delta)
		if clock.enabled:
			refresh_requested.emit()


# --------------------------------------------------------------------------
# Turns
# --------------------------------------------------------------------------

func is_human_turn() -> bool:
	return match_data != null and not config.is_ai_color(match_data.side_to_move())


func player_name(color: int) -> String:
	var custom := config.white_name if color == Chess.WHITE else config.black_name
	if not custom.is_empty():
		return custom
	if config.opponent != GameConfig.Opponent.LOCAL_PLAYER:
		if config.is_ai_color(color):
			return tr("PLAYER_AI") % tr(ChessAIPlayer.level_name_key(config.ai_level as ChessAIPlayer.Level))
		return tr("PLAYER_YOU")
	return tr("PLAYER_WHITE") if color == Chess.WHITE else tr("PLAYER_BLACK")


func _view_color() -> int:
	if config.opponent == GameConfig.Opponent.AI:
		return config.human_color
	if config.opponent == GameConfig.Opponent.AI_VS_AI:
		return Chess.WHITE
	return match_data.side_to_move() if Settings.get_value("gameplay", "auto_rotate_camera") else Chess.WHITE


func _start_turn() -> void:
	if match_data.is_over():
		_finish_game()
		return
	clock.set_active(match_data.side_to_move())
	if config.opponent == GameConfig.Opponent.LOCAL_PLAYER and Settings.get_value("gameplay", "auto_rotate_camera"):
		board_camera.face_side(match_data.side_to_move())
		board.flipped_view = match_data.side_to_move() == Chess.BLACK
		get_tree().create_timer(0.5).timeout.connect(func() -> void: board.refresh_facing())
	if is_human_turn():
		_set_state(State.AWAIT_HUMAN)
	else:
		_set_state(State.AWAIT_AI)
		if _pending_ai_move != Chess.NO_MOVE:
			var move := _pending_ai_move
			_pending_ai_move = Chess.NO_MOVE
			_commit(move)
		elif not _ai_requested:
			_request_ai()


func _request_ai() -> void:
	_ai_requested = true
	_pending_ai_move = Chess.NO_MOVE
	ai.request_move(match_data.position)


func _stop_ai() -> void:
	if ai:
		ai.cancel()
	_ai_requested = false
	_pending_ai_move = Chess.NO_MOVE


func _on_ai_move(move: int, info: Dictionary) -> void:
	_ai_requested = false
	if match_data == null or match_data.is_over() or not config.is_ai_color(match_data.side_to_move()):
		return
	if move == Chess.NO_MOVE or not match_data.is_legal(move):
		push_warning("AI returned an invalid move; requesting again")
		_request_ai()
		return
	if OS.is_debug_build():
		print("AI: %s depth %s score %s nodes %s pv %s" % [Chess.move_to_uci(move), info.get("depth"), info.get("score"), info.get("nodes"), info.get("pv")])
	# Respond to a pending human draw offer first.
	if match_data.draw_offer_from != -1 and match_data.draw_offer_from != match_data.side_to_move():
		if _ai_accepts_draw():
			match_data.accept_draw(match_data.side_to_move())
			notify.emit(tr("MSG_AI_ACCEPTS_DRAW"))
			_finish_game()
			return
		notify.emit(tr("MSG_AI_DECLINES_DRAW"))
		match_data.decline_draw()
	if state == State.AWAIT_AI:
		_commit(move)
	else:
		_pending_ai_move = move


func _ai_accepts_draw() -> bool:
	var score := ChessEvaluator.evaluate(match_data.position)
	return score <= -120 or match_data.position.is_insufficient_material()


# --------------------------------------------------------------------------
# Human input
# --------------------------------------------------------------------------

func _on_square_clicked(sq: int) -> void:
	if state != State.AWAIT_HUMAN:
		return
	var piece := match_data.position.squares[sq]
	var own := piece != Chess.EMPTY and Chess.piece_color(piece) == match_data.side_to_move()
	if selected_square >= 0:
		var candidates: Array[int] = []
		for move in _selected_moves:
			if Chess.move_to(move) == sq:
				candidates.append(move)
		if not candidates.is_empty():
			if candidates.size() > 1:
				_pending_promotion = [selected_square, sq]
				_set_state(State.PROMOTION)
				promotion_requested.emit(match_data.side_to_move())
				return
			_deselect()
			_commit(candidates[0])
			return
		if sq == selected_square:
			_deselect()
			return
	if own:
		selected_square = sq
		_selected_moves = match_data.legal_moves_from(sq)
		Audio.ui("hover")
		if _selected_moves.is_empty():
			notify.emit(tr("MSG_NO_MOVES_FOR_PIECE"))
	else:
		_deselect()
	_refresh_marks()


func _deselect() -> void:
	selected_square = -1
	_selected_moves = PackedInt32Array()
	_refresh_marks()


func choose_promotion(piece_type: int) -> void:
	if state != State.PROMOTION or _pending_promotion.is_empty():
		return
	var move := match_data.position.find_legal_move(_pending_promotion[0], _pending_promotion[1], piece_type)
	_pending_promotion.clear()
	_deselect()
	if move == Chess.NO_MOVE:
		_set_state(State.AWAIT_HUMAN)
		return
	_commit(move)


func cancel_promotion() -> void:
	if state == State.PROMOTION:
		_pending_promotion.clear()
		_set_state(State.AWAIT_HUMAN)


func _refresh_marks() -> void:
	if board == null or match_data == null:
		return
	var last := match_data.last_record()
	var show_last: bool = Settings.get_value("gameplay", "show_last_move")
	var check_sq := -1
	if match_data.position.is_in_check():
		check_sq = match_data.position.king_square[match_data.position.side]
	var moves := _selected_moves if Settings.get_value("gameplay", "show_legal_moves") else PackedInt32Array()
	board.show_state(selected_square, moves,
		last.from_square if last and show_last else -1,
		last.to_square if last and show_last else -1, check_sq)


# --------------------------------------------------------------------------
# Committing and presenting
# --------------------------------------------------------------------------

func _commit(move: int) -> void:
	var record := match_data.play_move(move)
	if record == null:
		push_warning("GameSession: rejected illegal move " + Chess.move_to_uci(move))
		_start_turn()
		return
	clock.on_move(record.color)
	move_committed.emit(record)
	_set_state(State.PRESENTING)
	# Let the AI think about its reply while the move is being shown.
	if not match_data.is_over() and config.is_ai_color(match_data.side_to_move()):
		_request_ai()
	refresh_requested.emit()
	await presenter.present(record, match_data.position)
	if state != State.PRESENTING or match_data.last_record() != record:
		return  # session ended or history changed during the presentation
	if not match_data.is_over():
		SaveSystem.save_game(SaveSystem.AUTOSAVE, config, match_data, clock)
	_start_turn()
	refresh_requested.emit()


func skip_presentation() -> void:
	if state == State.PRESENTING:
		presenter.skip()


func set_cinematic_mode(mode: int) -> void:
	config.cinematic_mode = mode
	presenter.cinematic_mode = mode
	Settings.set_value("gameplay", "cinematic_mode", mode)


# --------------------------------------------------------------------------
# Undo / redo, draws, resignation
# --------------------------------------------------------------------------

func can_undo() -> bool:
	return match_data != null and match_data.can_undo() and config.opponent != GameConfig.Opponent.AI_VS_AI \
		and state in [State.AWAIT_HUMAN, State.AWAIT_AI, State.GAME_OVER]


func undo() -> void:
	if not can_undo():
		return
	_stop_ai()
	var was_over := match_data.is_over()
	match_data.undo()
	# Versus the AI, take back until it is the human's turn again.
	if config.opponent == GameConfig.Opponent.AI:
		while match_data.can_undo() and config.is_ai_color(match_data.side_to_move()):
			match_data.undo()
	if was_over:
		Audio.music("board")
	selected_square = -1
	_selected_moves = PackedInt32Array()
	board.sync_to_position(match_data.position)
	Audio.ui("back")
	_start_turn()
	refresh_requested.emit()


func can_redo() -> bool:
	return match_data != null and match_data.can_redo() and state == State.AWAIT_HUMAN and config.opponent == GameConfig.Opponent.LOCAL_PLAYER


func redo() -> void:
	if not can_redo():
		return
	var record := match_data.redo()
	if record:
		clock.on_move(record.color)
		board.sync_to_position(match_data.position)
		_start_turn()
		refresh_requested.emit()


func resign() -> void:
	if match_data == null or match_data.is_over():
		return
	var color := match_data.side_to_move()
	if config.opponent == GameConfig.Opponent.AI:
		color = config.human_color
	_stop_ai()
	presenter.skip()
	match_data.resign(color)
	_finish_game()


func offer_draw() -> void:
	if match_data == null or match_data.is_over():
		return
	var color := match_data.side_to_move() if config.opponent == GameConfig.Opponent.LOCAL_PLAYER else config.human_color
	match_data.offer_draw(color)
	if config.opponent == GameConfig.Opponent.LOCAL_PLAYER:
		draw_offer_received.emit(color)
	else:
		notify.emit(tr("MSG_DRAW_OFFERED"))
		if state == State.AWAIT_HUMAN and _ai_accepts_draw():
			match_data.accept_draw(color ^ 1)
			notify.emit(tr("MSG_AI_ACCEPTS_DRAW"))
			_finish_game()
	refresh_requested.emit()


func answer_draw(accept: bool) -> void:
	if match_data == null or match_data.draw_offer_from == -1:
		return
	if accept:
		match_data.accept_draw(match_data.draw_offer_from ^ 1)
		_finish_game()
	else:
		match_data.decline_draw()
	refresh_requested.emit()


func can_claim_draw() -> bool:
	return match_data != null and state == State.AWAIT_HUMAN and match_data.claimable_draw_reason() != ChessMatch.Reason.NONE


func claim_draw() -> void:
	if can_claim_draw() and match_data.claim_draw():
		_finish_game()


func _on_flag(color: int) -> void:
	if match_data == null or match_data.is_over():
		return
	_stop_ai()
	match_data.flag_fall(color)
	_finish_game()


func _finish_game() -> void:
	if state == State.GAME_OVER:
		return
	clock.running = false
	_stop_ai()
	_set_state(State.GAME_OVER)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE)
	SaveSystem.archive_finished(match_data)
	var human_lost := config.opponent == GameConfig.Opponent.AI and match_data.winner() == (config.human_color ^ 1)
	if match_data.reason != ChessMatch.Reason.CHECKMATE:
		Audio.music("defeat" if human_lost or match_data.result == ChessMatch.Result.DRAW else "victory")
	game_finished.emit(match_data.result, match_data.reason)
	refresh_requested.emit()


func save_to_slot(slot: String) -> bool:
	if match_data == null:
		return false
	return SaveSystem.save_game(slot, config, match_data, clock)


# --------------------------------------------------------------------------
# Replay (cinematic review of archived games)
# --------------------------------------------------------------------------

func start_replay(full: ChessMatch) -> void:
	var c := GameConfig.from_settings()
	c.opponent = GameConfig.Opponent.LOCAL_PLAYER
	c.clock_minutes = 0.0
	c.start_fen = full.start_fen
	c.white_name = str(full.tags.get("White", ""))
	c.black_name = str(full.tags.get("Black", ""))
	_replay_moves.clear()
	for r in full.records:
		_replay_moves.append(r.move)
	_replay_index = 0
	var m := ChessMatch.new(full.start_fen)
	var clk := ChessClock.new()
	clk.configure(0.0, 0.0)
	_begin(c, m, clk)
	is_replay = true
	replay_autoplay = false
	_set_state(State.REPLAY)
	refresh_requested.emit()


func replay_progress() -> Vector2i:
	return Vector2i(_replay_index, _replay_moves.size())


func replay_next() -> void:
	if not is_replay or state != State.REPLAY or _replay_index >= _replay_moves.size():
		return
	var record := match_data.play_move(_replay_moves[_replay_index])
	if record == null:
		return
	_replay_index += 1
	_set_state(State.PRESENTING)
	refresh_requested.emit()
	await presenter.present(record, match_data.position)
	if not is_replay:
		return
	_set_state(State.REPLAY)
	refresh_requested.emit()
	if replay_autoplay and _replay_index < _replay_moves.size():
		await get_tree().create_timer(0.6).timeout
		if is_replay and replay_autoplay and state == State.REPLAY:
			replay_next()


func replay_previous() -> void:
	if not is_replay or state != State.REPLAY or _replay_index == 0:
		return
	match_data.undo()
	_replay_index -= 1
	board.sync_to_position(match_data.position)
	refresh_requested.emit()


func set_replay_autoplay(enabled: bool) -> void:
	replay_autoplay = enabled
	if enabled and state == State.REPLAY:
		replay_next()

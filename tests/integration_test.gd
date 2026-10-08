extends Node
## End-to-end test of the real game scene (headless):
##   godot --headless --path . res://tests/integration_test.tscn
## Plays moves through the same entry point as mouse clicks and verifies
## that the visual board always matches the authoritative position, that
## battles (including skip) return control correctly and that special
## rules, undo, save/load and game over work in the running game.

var main: Node
var session: GameSession
var failures: PackedStringArray = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		printerr("FAIL  " + msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_turn(timeout_s: float = 60.0) -> bool:
	var start := Time.get_ticks_msec()
	while session.state not in [GameSession.State.AWAIT_HUMAN, GameSession.State.GAME_OVER, GameSession.State.PROMOTION]:
		await get_tree().process_frame
		if Time.get_ticks_msec() - start > timeout_s * 1000.0:
			return false
	return true


func _click(square: String) -> void:
	session._on_square_clicked(Chess.parse_square(square))


func _move(from: String, to: String) -> bool:
	_click(from)
	_click(to)
	return await _wait_turn()


func _board_matches(label: String) -> void:
	await _frames(2)
	var pos := session.match_data.position
	var expected := 0
	for sq in 64:
		var piece := pos.squares[sq]
		if piece == Chess.EMPTY:
			continue
		expected += 1
		var rig := session.board.rig_at(sq)
		check(rig != null and int(rig.get_meta("piece")) == piece, "%s: square %s shows wrong piece" % [label, Chess.square_name(sq)])
	check(session.board.piece_count() == expected, "%s: %d visual pieces vs %d logical" % [label, session.board.piece_count(), expected])
	var stray := 0
	for c in session.board.get_children():
		if c is CharacterRig and not c.is_queued_for_deletion():
			stray += 1
	check(stray == expected, "%s: %d rig nodes alive vs %d pieces (duplicates?)" % [label, stray, expected])


func _start(mode: int, opponent: GameConfig.Opponent = GameConfig.Opponent.LOCAL_PLAYER, fen: String = Chess.START_FEN) -> void:
	var c := GameConfig.new()
	c.opponent = opponent
	c.cinematic_mode = mode
	c.ai_level = ChessAIPlayer.Level.BEGINNER
	c.start_fen = fen
	main._enter_game(0, 0)
	session.start_new(c)
	await _frames(3)


func _run() -> void:
	var settings := get_node_or_null("/root/Settings")
	check(settings != null, "Settings autoload present")
	if settings:
		settings.set_override("gameplay", "cinematic_speed", 2.0)  # session only
	main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(main)
	while not main.booted:
		await get_tree().process_frame
	session = main.session
	var started := Time.get_ticks_msec()

	# 1. Local game, instant captures: opening with castling and en passant.
	await _start(CinematicMode.Mode.SKIP)
	await _board_matches("start")
	for m in [["e2", "e4"], ["d7", "d5"], ["e4", "e5"], ["f7", "f5"], ["e5", "f6"], ["g8", "f6"],
			["g1", "f3"], ["e7", "e6"], ["f1", "e2"], ["f8", "e7"], ["e1", "g1"]]:
		check(await _move(m[0], m[1]), "move %s%s returned control" % [m[0], m[1]])
	check(session.match_data.records.size() == 11, "11 plies played (got %d)" % session.match_data.records.size())
	check(session.match_data.records[4].is_en_passant, "en passant played through the UI")
	check(session.match_data.records[10].is_castle, "castling played through the UI")
	await _board_matches("after castling/en passant")

	# Illegal clicks do nothing (Black to move now).
	_click("a2")
	_click("a3")
	check(session.match_data.records.size() == 11, "cannot move opponent's piece")
	_click("a7")
	_click("a4")
	check(session.match_data.records.size() == 11, "illegal destination ignored")

	# Undo / redo in local mode.
	session.undo()
	await _wait_turn()
	check(session.match_data.records.size() == 10, "undo one ply")
	await _board_matches("after undo")
	session.redo()
	await _wait_turn()
	check(session.match_data.records.size() == 11, "redo")
	await _board_matches("after redo")

	# Save / load round trip.
	check(session.save_to_slot("integration_test"), "save to slot")
	var data := SaveSystem.load_game("integration_test")
	check(not data.is_empty(), "load slot")
	if not data.is_empty():
		session.start_from_save(data)
		await _frames(3)
		check(session.match_data.position.get_fen() == (data["match"] as ChessMatch).position.get_fen(), "loaded position")
		await _board_matches("after load")
	SaveSystem.delete_save("integration_test")

	# 2. Quick arena battles with automatic skip midway, then classic strikes.
	for mode in [CinematicMode.Mode.QUICK, CinematicMode.Mode.CLASSIC]:
		await _start(mode)
		for m in [["e2", "e4"], ["d7", "d5"], ["e4", "d5"], ["d8", "d5"], ["b1", "c3"], ["d5", "a2"]]:
			_click(m[0])
			_click(m[1])
			if mode == CinematicMode.Mode.QUICK and m == ["d8", "d5"]:
				await _frames(20)
				session.skip_presentation()  # skip a battle mid-way
			check(await _wait_turn(90.0), "mode %d move %s%s finished" % [mode, m[0], m[1]])
		check(not main.director.playing, "mode %d: no battle left running" % mode)
		check(session.match_data.records.size() == 6, "mode %d: 6 plies" % mode)
		await _board_matches("mode %d captures" % mode)

	# 3. Promotion dialog flow.
	await _start(CinematicMode.Mode.SKIP, GameConfig.Opponent.LOCAL_PLAYER, "8/P6k/8/8/8/8/8/K7 w - - 0 1")
	_click("a7")
	_click("a8")
	check(session.state == GameSession.State.PROMOTION, "promotion asks for a piece")
	session.choose_promotion(Chess.KNIGHT)
	await _wait_turn()
	check(session.match_data.position.squares[56] == Chess.make_piece(Chess.KNIGHT, Chess.WHITE), "underpromotion to knight")
	await _board_matches("after promotion")

	# 4. Checkmate ends the game (with the checkmate scene).
	await _start(CinematicMode.Mode.QUICK)
	for m in [["f2", "f3"], ["e7", "e5"], ["g2", "g4"], ["d8", "h4"]]:
		check(await _move(m[0], m[1]), "fool's mate move %s%s" % [m[0], m[1]])
	check(session.state == GameSession.State.GAME_OVER, "game over after mate")
	check(session.match_data.reason == ChessMatch.Reason.CHECKMATE, "result is checkmate")
	await _board_matches("after mate")

	# 5. Versus AI: the AI replies and undo returns to the human's turn.
	await _start(CinematicMode.Mode.SKIP, GameConfig.Opponent.AI)
	check(await _move("e2", "e4"), "human move vs AI")
	check(session.match_data.records.size() == 2, "AI answered (plies=%d)" % session.match_data.records.size())
	session.undo()
	await _wait_turn()
	check(session.match_data.records.size() == 0 and session.is_human_turn(), "undo vs AI takes back both plies")

	main._show_menu(true)
	await _frames(3)
	print("integration: %d checks, %d failures, %.1f s" % [checks, failures.size(), (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if not failures.is_empty() else 0)

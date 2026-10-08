extends TestSuite
## Rules, results, draws, notation, history and serialization.


func _play(m: ChessMatch, sans: Array) -> bool:
	for san in sans:
		if m.play_san(san) == null:
			check(false, "move %s rejected in %s" % [san, m.position.get_fen()])
			return false
	return true


func test_fen_round_trip() -> void:
	for fen in [
		Chess.START_FEN,
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		"rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3",
	]:
		check_eq(ChessPosition.new(fen).get_fen(), fen, "FEN round trip")


func test_invalid_fen_rejected() -> void:
	var pos := ChessPosition.new()
	check(not pos.set_fen("8/8/8/8/8/8/8/8 w - - 0 1"), "no kings")
	check(not pos.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1"), "7 ranks")
	check(not pos.set_fen("4k3/8/8/8/8/8/8/4K2r b - - 0 1"), "side not to move in check")
	check(not pos.set_fen("P3k3/8/8/8/8/8/8/4K3 w - - 0 1"), "pawn on last rank")
	check_eq(pos.get_fen(), Chess.START_FEN, "position untouched after rejected FEN")


func test_illegal_moves_rejected() -> void:
	var m := ChessMatch.new()
	check(m.play_uci("e2e5") == null, "pawn cannot jump three squares")
	check(m.play_uci("e7e5") == null, "cannot move opponent's piece")
	check(m.play_uci("g1g3") == null, "knight geometry")
	check(m.play_uci("f1c4") == null, "bishop blocked")
	var pinned := ChessMatch.new("4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1")
	check(pinned.play_uci("e2d3") == null, "absolutely pinned bishop cannot leave the file")
	var in_check := ChessMatch.new("4k3/8/8/8/8/8/3P4/r3K3 w - - 0 1")
	check(in_check.play_uci("d2d3") == null, "must answer check")
	check(in_check.play_uci("e1e2") != null, "king steps out of check")


func test_castling() -> void:
	var m := ChessMatch.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var r := m.play_uci("e1g1")
	check(r != null and r.is_castle and r.san == "O-O", "white short castle")
	check_eq(m.position.squares[5], Chess.make_piece(Chess.ROOK, Chess.WHITE), "rook on f1")
	r = m.play_uci("e8c8")
	check(r != null and r.san == "O-O-O", "black long castle")
	check_eq(m.position.squares[59], Chess.make_piece(Chess.ROOK, Chess.BLACK), "rook on d8")
	# Through check / out of check / after king moved.
	check(ChessMatch.new("4k3/8/8/8/8/8/8/R3K2r w Q - 0 1").play_uci("e1c1") == null, "cannot castle out of check")
	check(ChessMatch.new("4k3/8/8/8/8/5r2/8/4K2R w K - 0 1").play_uci("e1g1") == null, "cannot castle through attacked square")
	check(ChessMatch.new("4k3/8/8/8/8/8/8/RN2K3 w Q - 0 1").play_uci("e1c1") == null, "cannot castle through pieces")
	var moved := ChessMatch.new("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
	_play(moved, ["Kf1", "Kd8", "Ke1", "Ke8"])
	check(moved.play_uci("e1g1") == null, "castling right lost after king moved")
	var rook_taken := ChessMatch.new("4k3/8/8/8/8/8/6b1/R3K2R b KQ - 0 1")
	rook_taken.play_uci("g2h1")
	check(rook_taken.position.castling & Chess.CASTLE_WK == 0, "right lost when rook is captured")


func test_en_passant() -> void:
	var m := ChessMatch.new()
	_play(m, ["e4", "a6", "e5", "d5"])
	var r := m.play_san("exd6")
	check(r != null and r.is_en_passant, "en passant capture")
	check_eq(r.captured_square, Chess.parse_square("d5"), "captured pawn square")
	check_eq(m.position.squares[Chess.parse_square("d5")], Chess.EMPTY, "d5 emptied")
	# Only immediately after the double push.
	var late := ChessMatch.new()
	_play(late, ["e4", "d5", "e5", "f5", "a3", "a6"])
	check(late.play_san("exf6") == null, "en passant expires")
	# Horizontal pin: en passant would expose the king.
	var pin := ChessMatch.new("8/8/8/KPp4r/8/8/8/7k w - c6 0 1")
	check(pin.play_uci("b5c6") == null, "en passant illegal when it exposes the king")


func test_promotion() -> void:
	var m := ChessMatch.new("8/P6k/8/8/8/8/8/K7 w - - 0 1")
	var r := m.play_uci("a7a8n")
	check(r != null and r.promotion_type == Chess.KNIGHT and r.san == "a8=N", "underpromotion")
	check_eq(m.position.squares[56], Chess.make_piece(Chess.KNIGHT, Chess.WHITE), "knight placed")
	m.undo()
	check_eq(m.position.squares[48], Chess.make_piece(Chess.PAWN, Chess.WHITE), "undo restores pawn")
	check(m.play_san("a8=Q+") != null, "promotion SAN with check")


func test_checkmate_and_stalemate() -> void:
	var fools := ChessMatch.new()
	_play(fools, ["f3", "e5", "g4", "Qh4#"])
	check_eq(fools.result, ChessMatch.Result.BLACK_WINS, "fool's mate result")
	check_eq(fools.reason, ChessMatch.Reason.CHECKMATE, "fool's mate reason")
	check(fools.last_record().is_checkmate, "record flags checkmate")
	check(fools.play_san("a3") == null, "no moves after mate")
	var stale := ChessMatch.new("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1")
	check(stale.play_san("Qf6") != null)
	check(stale.result == ChessMatch.Result.ONGOING, "not stalemate yet")
	stale = ChessMatch.new("7k/8/6K1/8/8/8/8/5Q2 w - - 0 1")
	stale.play_san("Qf7")
	check_eq(stale.reason, ChessMatch.Reason.STALEMATE, "stalemate detected")
	check_eq(stale.result, ChessMatch.Result.DRAW, "stalemate is a draw")


func test_insufficient_material() -> void:
	for fen in ["8/8/4k3/8/8/4K3/8/8 w - - 0 1", "8/8/4k3/8/8/4KB2/8/8 w - - 0 1",
			"8/8/4kn2/8/8/4K3/8/8 w - - 0 1", "8/8/2b1k3/8/8/4KB2/8/8 w - - 0 1"]:
		check(ChessPosition.new(fen).is_insufficient_material(), "insufficient: " + fen)
	for fen in ["8/8/3bk3/8/8/4KB2/8/8 w - - 0 1", "8/8/4k3/8/8/4KN2/5N2/8 w - - 0 1",
			"8/8/4k3/8/8/4K3/4P3/8 w - - 0 1"]:
		check(not ChessPosition.new(fen).is_insufficient_material(), "sufficient: " + fen)
	var m := ChessMatch.new("8/8/4k3/8/8/4K3/8/3r4 w - - 0 1")
	check(m.play_uci("e3f3") != null and not m.is_over(), "rook keeps the game alive")
	m = ChessMatch.new("8/8/4k3/8/8/3rK3/8/8 w - - 0 1")
	m.play_uci("e3d3")
	check_eq(m.reason, ChessMatch.Reason.INSUFFICIENT_MATERIAL, "automatic draw after last capture")


func test_repetition() -> void:
	var m := ChessMatch.new()
	var cycle := ["Nf3", "Nf6", "Ng1", "Ng8"]
	_play(m, cycle)
	check_eq(m.claimable_draw_reason(), ChessMatch.Reason.NONE, "2nd occurrence")
	_play(m, cycle)
	check_eq(m.claimable_draw_reason(), ChessMatch.Reason.THREEFOLD_REPETITION, "threefold claimable")
	check(not m.is_over(), "threefold is not automatic")
	_play(m, cycle)
	check(not m.is_over(), "fourfold not automatic")
	_play(m, cycle)
	check_eq(m.reason, ChessMatch.Reason.FIVEFOLD_REPETITION, "fivefold automatic")
	var claim := ChessMatch.new()
	_play(claim, cycle + cycle)
	check(claim.claim_draw(), "claim threefold")
	check_eq(claim.result, ChessMatch.Result.DRAW)


func test_fifty_and_seventy_five_move_rules() -> void:
	var m := ChessMatch.new("8/8/4k3/8/8/4K3/8/R7 w - - 99 80")
	check_eq(m.claimable_draw_reason(), ChessMatch.Reason.NONE)
	m.play_uci("a1a2")
	check_eq(m.claimable_draw_reason(), ChessMatch.Reason.FIFTY_MOVE_RULE, "50-move claim")
	var auto := ChessMatch.new("8/8/4k3/8/8/4K3/8/R7 w - - 149 120")
	auto.play_uci("a1a2")
	check_eq(auto.reason, ChessMatch.Reason.SEVENTY_FIVE_MOVE_RULE, "75-move automatic")
	var mate_wins := ChessMatch.new("7k/R7/6K1/8/8/8/8/8 w - - 149 120")
	mate_wins.play_uci("a7a8")
	check_eq(mate_wins.reason, ChessMatch.Reason.CHECKMATE, "mate takes precedence over 75-move rule")


func test_resign_draw_offer_timeout() -> void:
	var m := ChessMatch.new()
	m.resign(Chess.WHITE)
	check_eq(m.result, ChessMatch.Result.BLACK_WINS, "resignation")
	m = ChessMatch.new()
	m.offer_draw(Chess.WHITE)
	check(not m.accept_draw(Chess.WHITE), "cannot accept own offer")
	check(m.accept_draw(Chess.BLACK), "accept offer")
	check_eq(m.reason, ChessMatch.Reason.AGREEMENT)
	m = ChessMatch.new()
	m.offer_draw(Chess.WHITE)
	m.play_san("e4")
	check_eq(m.draw_offer_from, Chess.WHITE, "offer persists through offerer's own move")
	m.play_san("e5")
	check_eq(m.draw_offer_from, -1, "opponent moving declines the offer")
	var t := ChessMatch.new("8/8/4k3/8/8/4K3/8/R7 b - - 0 1")
	t.flag_fall(Chess.BLACK)
	check_eq(t.result, ChessMatch.Result.WHITE_WINS, "timeout with mating material")
	t = ChessMatch.new("8/8/4k3/8/8/4K3/8/R7 w - - 0 1")
	t.flag_fall(Chess.WHITE)
	check_eq(t.reason, ChessMatch.Reason.TIMEOUT_INSUFFICIENT_MATERIAL, "lone king cannot win on time")


func test_undo_redo() -> void:
	var m := ChessMatch.new()
	_play(m, ["e4", "e5", "Nf3", "Nc6", "Bb5"])
	var fen := m.position.get_fen()
	check(m.undo() and m.undo(), "undo twice")
	check_eq(m.records.size(), 3)
	check(m.redo() != null and m.redo() != null, "redo twice")
	check_eq(m.position.get_fen(), fen, "redo restores position")
	m.undo()
	m.play_san("Bc4")
	check(not m.can_redo(), "new move clears redo")
	var mate := ChessMatch.new()
	_play(mate, ["f3", "e5", "g4", "Qh4#"])
	mate.undo()
	check(not mate.is_over(), "undo reopens a finished game")


func test_san_generation() -> void:
	var m := ChessMatch.new("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
	var legal := m.position.generate_legal_moves()
	var sans := []
	for move in legal:
		sans.append(ChessNotation.move_to_san(m.position, move))
	check("O-O" in sans and "O-O-O" in sans, "castling SAN")
	check("Rad1" in sans or "Rd1" in sans, "rook move SAN present")
	var amb := ChessMatch.new("4k3/8/8/8/8/8/1N3N2/4K3 w - - 0 1")
	var found := false
	for move in amb.position.generate_legal_moves():
		if ChessNotation.move_to_san(amb.position, move) == "Nbd3":
			found = true
	check(found, "file disambiguation Nbd3")
	var rank_amb := ChessMatch.new("4k3/8/8/1N6/8/1N6/8/4K3 w - - 0 1")
	check(rank_amb.play_san("N5d4") != null, "rank disambiguation N5d4")


func test_pgn_round_trip() -> void:
	var m := ChessMatch.new()
	_play(m, ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Bxc6", "dxc6", "O-O", "f6", "d4", "exd4"])
	m.tags = {"White": "Ana", "Black": "Bruno"}
	var pgn := m.to_pgn()
	check(pgn.contains("[White \"Ana\"]"), "PGN tags")
	check(pgn.contains("4. Bxc6 dxc6 5. O-O"), "PGN movetext")
	var loaded := ChessMatch.from_pgn(pgn)
	check(loaded != null, "PGN parses")
	if loaded:
		check_eq(loaded.position.get_fen(), m.position.get_fen(), "PGN reproduces position")
	var messy := "[Event \"x\"]\n1.e4 {best by test} e5 (1...c5 2.Nf3) 2.Nf3 $1 Nc6 ; comment\n3.Bb5 *"
	var parsed := ChessMatch.from_pgn(messy)
	check(parsed != null and parsed.records.size() == 5, "PGN with comments, variations and NAGs")


func test_save_dict_round_trip() -> void:
	var m := ChessMatch.new()
	_play(m, ["d4", "d5", "c4", "e6"])
	m.offer_draw(Chess.WHITE)
	var data: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	var restored := ChessMatch.from_dict(data)
	check(restored != null)
	check_eq(restored.position.get_fen(), m.position.get_fen(), "position restored")
	check_eq(restored.draw_offer_from, Chess.WHITE, "draw offer restored")
	check(restored.can_undo(), "history restored (undo available)")
	data["moves"].append("e1e8")
	check(ChessMatch.from_dict(data) == null, "tampered save rejected")


func test_clock() -> void:
	var c := ChessClock.new()
	c.configure(1.0, 2.0)
	c.running = true
	c.tick(10.0)
	check_eq(c.remaining_ms[0], 50_000, "white time decreases")
	c.on_move(Chess.WHITE)
	check_eq(c.remaining_ms[0], 52_000, "increment applied")
	check_eq(c.active_color, Chess.BLACK, "clock switched")
	var flagged := [-1]
	c.flagged.connect(func(color: int) -> void: flagged[0] = color)
	c.tick(61.0)
	check_eq(flagged[0], Chess.BLACK, "black flagged")
	check_eq(ChessClock.format_ms(83_000), "1:23")

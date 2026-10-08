extends TestSuite
## AI sanity: finds mates and wins material, always returns legal moves.


func _best(fen: String, depth: int, time_ms: int = 4000) -> Dictionary:
	return ChessSearch.new().search(ChessPosition.new(fen), {"max_depth": depth, "time_ms": time_ms})


func test_finds_mate_in_one() -> void:
	var r := _best("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", 3)
	check_eq(Chess.move_to_uci(r["move"]), "d1d8", "back rank mate")
	check(int(r["score"]) >= ChessSearch.MATE_THRESHOLD, "mate score reported")


func test_finds_mate_in_two() -> void:
	# 1.Qh6+?? no: classic Q+R ladder. White: Ra1, Rb2, Kh1 vs Kg8.
	var r := _best("6k1/8/8/8/8/8/1R6/R6K w - - 0 1", 4)
	var pos := ChessPosition.new("6k1/8/8/8/8/8/1R6/R6K w - - 0 1")
	check(int(r["score"]) >= ChessSearch.MATE_THRESHOLD, "rook roller mate found, score %d" % r["score"])
	check(r["move"] in pos.generate_legal_moves(), "move is legal")


func test_wins_hanging_queen() -> void:
	var r := _best("rnb1kbnr/pppp1ppp/8/4p1q1/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1", 3)
	check_eq(Chess.move_to_uci(r["move"]), "c1g5", "bishop takes the queen")


func test_avoids_losing_queen() -> void:
	# Black queen attacked by a pawn: it must move away (any move but staying).
	var fen := "rnb1kbnr/pppp1ppp/8/4p3/3q4/4P3/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
	var r := _best(fen, 3)
	check_eq(Chess.move_from(r["move"]), Chess.parse_square("d4"), "queen escapes the attack")


func test_respects_time_limit() -> void:
	var started := Time.get_ticks_msec()
	var r := _best(Chess.START_FEN, 64, 700)
	var elapsed := Time.get_ticks_msec() - started
	check(elapsed < 2000, "search stops on time (took %d ms)" % elapsed)
	check(r["move"] in ChessPosition.new().generate_legal_moves(), "legal move from start")
	print("      start position: depth %d, %d nodes in %d ms (%d nps)" % [
		r["depth"], r["nodes"], elapsed, int(r["nodes"] * 1000.0 / maxi(1, elapsed))])


func test_handicapped_levels_return_legal_moves() -> void:
	var pos := ChessPosition.new("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")
	var scored := ChessSearch.new().score_root_moves(pos, 2, true)
	check_eq(scored.size(), pos.generate_legal_moves().size(), "every root move scored")

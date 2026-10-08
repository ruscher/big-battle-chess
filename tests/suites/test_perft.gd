extends TestSuite
## Perft (move path enumeration) against published reference counts from the
## Chess Programming Wiki. This is the strongest available check that move
## generation, make/unmake, castling, en passant and promotion are all exact.
## Run with `--deep` for the slower, deeper node counts.

const POSITIONS := [
	# [name, fen, [counts per depth...], deep counts]
	["start", Chess.START_FEN, [20, 400, 8902], [197281]],
	["kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039], [97862]],
	["position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812], [43238]],
	["position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467], []],
	["position4_mirror", "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", [6, 264, 9467], []],
	["position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486], [62379]],
	["position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079], [89890]],
]

var deep := false


func configure(args: PackedStringArray, _tree: SceneTree) -> void:
	deep = "--deep" in args


static func perft(pos: ChessPosition, depth: int) -> int:
	if depth == 0:
		return 1
	var nodes := 0
	for move in pos.generate_pseudo_moves():
		if pos.make_move(move):
			nodes += 1 if depth == 1 else perft(pos, depth - 1)
			pos.unmake_move()
	return nodes


func test_reference_positions() -> void:
	for entry in POSITIONS:
		var pos := ChessPosition.new(entry[1])
		var fen_before := pos.get_fen()
		var hash_before := pos.hash
		var counts: Array = entry[2].duplicate()
		if deep:
			counts.append_array(entry[3])
		for d in counts.size():
			check_eq(perft(pos, d + 1), counts[d], "%s depth %d" % [entry[0], d + 1])
		check_eq(pos.get_fen(), fen_before, "%s position restored after perft" % entry[0])
		check_eq(pos.hash, hash_before, "%s hash restored after perft" % entry[0])


func test_incremental_hash_matches_full_hash() -> void:
	var pos := ChessPosition.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
	for move in pos.generate_legal_moves():
		pos.make_move(move)
		for reply in pos.generate_legal_moves():
			pos.make_move(reply)
			if not check_eq(pos.hash, pos.compute_hash(), "hash after %s %s" % [Chess.move_to_uci(move), Chess.move_to_uci(reply)]):
				pos.unmake_move()
				pos.unmake_move()
				return
			pos.unmake_move()
		pos.unmake_move()

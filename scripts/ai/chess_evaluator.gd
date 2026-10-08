class_name ChessEvaluator
extends RefCounted
## Static position evaluation in centipawns from the side to move's view.
##
## Tapered between middlegame and endgame by remaining material. Terms:
## material, piece-square tables, bishop pair, pawn structure (doubled,
## isolated, passed), rooks on open files and a pawn shield for the king.
## Tables are written from White's point of view with a8 first, so they read
## like a board diagram.

const PHASE_WEIGHT: Array[int] = [0, 0, 1, 1, 2, 4, 0]
const PHASE_TOTAL := 24

const MG_VALUE: Array[int] = [0, 100, 320, 335, 480, 950, 0]
const EG_VALUE: Array[int] = [0, 125, 290, 310, 530, 980, 0]

const PAWN_MG: Array[int] = [
	  0,   0,   0,   0,   0,   0,   0,   0,
	 60,  70,  60,  70,  70,  60,  70,  60,
	 15,  20,  30,  40,  40,  30,  20,  15,
	  5,  10,  15,  30,  30,  15,  10,   5,
	  0,   0,  10,  25,  25,  10,   0,   0,
	  5,  -5,  -5,   5,   5, -10,  -5,   5,
	  5,  10,  10, -20, -20,  10,  10,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const PAWN_EG: Array[int] = [
	  0,   0,   0,   0,   0,   0,   0,   0,
	120, 110, 100,  90,  90, 100, 110, 120,
	 70,  65,  55,  45,  45,  55,  65,  70,
	 35,  30,  25,  20,  20,  25,  30,  35,
	 15,  12,  10,   5,   5,  10,  12,  15,
	  5,   5,   0,   0,   0,   0,   5,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const KNIGHT_MG: Array[int] = [
	-60, -40, -30, -30, -30, -30, -40, -60,
	-40, -20,   0,   5,   5,   0, -20, -40,
	-30,   5,  15,  20,  20,  15,   5, -30,
	-30,   5,  20,  25,  25,  20,   5, -30,
	-30,   0,  15,  20,  20,  15,   0, -30,
	-30,   5,  12,  15,  15,  12,   5, -30,
	-40, -20,   0,   5,   5,   0, -20, -40,
	-55, -35, -30, -30, -30, -30, -35, -55,
]
const KNIGHT_EG: Array[int] = [
	-50, -35, -25, -20, -20, -25, -35, -50,
	-35, -15,  -5,   0,   0,  -5, -15, -35,
	-25,  -5,  10,  15,  15,  10,  -5, -25,
	-20,   0,  15,  20,  20,  15,   0, -20,
	-20,   0,  15,  20,  20,  15,   0, -20,
	-25,  -5,  10,  15,  15,  10,  -5, -25,
	-35, -15,  -5,   0,   0,  -5, -15, -35,
	-50, -35, -25, -20, -20, -25, -35, -50,
]
const BISHOP_MG: Array[int] = [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,  10,  10,   5,   0, -10,
	-10,   5,   5,  10,  10,   5,   5, -10,
	-10,   0,  12,  10,  10,  12,   0, -10,
	-10,  10,  10,  10,  10,  10,  10, -10,
	-10,  15,   0,   0,   0,   0,  15, -10,
	-20, -10, -12, -10, -10, -12, -10, -20,
]
const BISHOP_EG: Array[int] = [
	-15, -10,  -8,  -5,  -5,  -8, -10, -15,
	-10,  -5,   0,   0,   0,   0,  -5, -10,
	 -8,   0,   5,   5,   5,   5,   0,  -8,
	 -5,   0,   5,  10,  10,   5,   0,  -5,
	 -5,   0,   5,  10,  10,   5,   0,  -5,
	 -8,   0,   5,   5,   5,   5,   0,  -8,
	-10,  -5,   0,   0,   0,   0,  -5, -10,
	-15, -10,  -8,  -5,  -5,  -8, -10, -15,
]
const ROOK_MG: Array[int] = [
	  5,  10,  10,  10,  10,  10,  10,   5,
	 15,  20,  20,  20,  20,  20,  20,  15,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	-10,  -5,   0,   0,   0,   0,  -5, -10,
	 -5,  -5,   0,  10,  10,   5,  -5,  -5,
]
const ROOK_EG: Array[int] = [
	 10,  10,  10,  10,  10,  10,  10,  10,
	 10,  10,  10,  10,  10,  10,  10,  10,
	  5,   5,   5,   5,   5,   5,   5,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,
	 -5,  -5,  -5,  -5,  -5,  -5,  -5,  -5,
	 -5,  -5,  -5,  -5,  -5,  -5,  -5,  -5,
	-10,  -5,   0,   0,   0,   0,  -5, -10,
]
const QUEEN_MG: Array[int] = [
	-20, -10, -10,  -5,  -5, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,   5,   5,   5,   0, -10,
	 -5,   0,   5,   5,   5,   5,   0,  -5,
	 -5,   0,   5,   5,   5,   5,   0,  -5,
	-10,   5,   5,   5,   5,   5,   0, -10,
	-10,   0,   5,   0,   0,   0,   0, -10,
	-20, -10, -10,   0,  -5, -10, -10, -20,
]
const QUEEN_EG: Array[int] = [
	-15, -10,  -5,   0,   0,  -5, -10, -15,
	-10,   0,   5,  10,  10,   5,   0, -10,
	 -5,   5,  15,  20,  20,  15,   5,  -5,
	  0,  10,  20,  25,  25,  20,  10,   0,
	  0,  10,  20,  25,  25,  20,  10,   0,
	 -5,   5,  15,  20,  20,  15,   5,  -5,
	-10,   0,   5,  10,  10,   5,   0, -10,
	-15, -10,  -5,   0,   0,  -5, -10, -15,
]
const KING_MG: Array[int] = [
	-40, -50, -50, -60, -60, -50, -50, -40,
	-40, -50, -50, -60, -60, -50, -50, -40,
	-40, -50, -50, -60, -60, -50, -50, -40,
	-40, -50, -50, -60, -60, -50, -50, -40,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-20, -30, -30, -40, -40, -30, -30, -20,
	 10,  10, -10, -20, -20, -10,  10,  10,
	 20,  35,  10, -10,   0,  10,  35,  20,
]
const KING_EG: Array[int] = [
	-50, -35, -25, -20, -20, -25, -35, -50,
	-30, -15,  -5,   0,   0,  -5, -15, -30,
	-25,  -5,  15,  25,  25,  15,  -5, -25,
	-20,  -5,  25,  35,  35,  25,  -5, -20,
	-20,  -5,  25,  35,  35,  25,  -5, -20,
	-25,  -5,  15,  25,  25,  15,  -5, -25,
	-30, -20,   0,   0,   0,   0, -20, -30,
	-50, -35, -25, -20, -20, -25, -35, -50,
]

const PASSED_MG: Array[int] = [0, 5, 10, 15, 25, 40, 60, 0]
const PASSED_EG: Array[int] = [0, 10, 20, 35, 55, 85, 130, 0]

static var _mg_tables: Array = [[], PAWN_MG, KNIGHT_MG, BISHOP_MG, ROOK_MG, QUEEN_MG, KING_MG]
static var _eg_tables: Array = [[], PAWN_EG, KNIGHT_EG, BISHOP_EG, ROOK_EG, QUEEN_EG, KING_EG]


static func evaluate(pos: ChessPosition) -> int:
	var sq_list := pos.squares
	var mg := [0, 0]
	var eg := [0, 0]
	var phase := 0
	var bishops := [0, 0]
	var pawn_files := [PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])]
	var rooks: Array[int] = []
	for sq in 64:
		var piece := sq_list[sq]
		if piece == 0:
			continue
		var type := piece & 7
		var color := piece >> 3
		var file := sq & 7
		var rank := sq >> 3
		var idx := ((7 - rank) << 3) + file if color == 0 else (rank << 3) + file
		mg[color] += MG_VALUE[type] + _mg_tables[type][idx]
		eg[color] += EG_VALUE[type] + _eg_tables[type][idx]
		phase += PHASE_WEIGHT[type]
		if type == Chess.PAWN:
			pawn_files[color][file] += 1
		elif type == Chess.BISHOP:
			bishops[color] += 1
		elif type == Chess.ROOK:
			rooks.append(sq)

	for color in 2:
		if bishops[color] >= 2:
			mg[color] += 30
			eg[color] += 45
		var own: PackedInt32Array = pawn_files[color]
		var enemy: PackedInt32Array = pawn_files[color ^ 1]
		for f in 8:
			var n := own[f]
			if n == 0:
				continue
			if n > 1:
				mg[color] -= 12 * (n - 1)
				eg[color] -= 20 * (n - 1)
			var left := own[f - 1] if f > 0 else 0
			var right := own[f + 1] if f < 7 else 0
			if left == 0 and right == 0:
				mg[color] -= 12 * n
				eg[color] -= 15 * n

	# Passed pawns need square-level information.
	for sq in 64:
		var piece := sq_list[sq]
		if (piece & 7) != Chess.PAWN:
			continue
		var color := piece >> 3
		if _is_passed(sq_list, sq, color):
			var rel_rank := (sq >> 3) if color == 0 else 7 - (sq >> 3)
			mg[color] += PASSED_MG[rel_rank]
			eg[color] += PASSED_EG[rel_rank]

	for sq in rooks:
		var color := sq_list[sq] >> 3
		var file := sq & 7
		if pawn_files[color][file] == 0:
			if pawn_files[color ^ 1][file] == 0:
				mg[color] += 25
				eg[color] += 10
			else:
				mg[color] += 12

	# King shelter (middlegame only): own pawns in front of the king.
	for color in 2:
		var k := pos.king_square[color]
		var kf := k & 7
		var kr := k >> 3
		var forward := 1 if color == 0 else -1
		var shield := 0
		for df in [-1, 0, 1]:
			var f: int = kf + df
			if f < 0 or f > 7:
				continue
			for dr in [1, 2]:
				var r: int = kr + forward * dr
				if r < 0 or r > 7:
					continue
				if sq_list[r * 8 + f] == Chess.make_piece(Chess.PAWN, color):
					shield += 2 if dr == 1 else 1
		mg[color] += shield * 6

	var phase_c := mini(phase, PHASE_TOTAL)
	var mg_score: int = mg[0] - mg[1]
	var eg_score: int = eg[0] - eg[1]
	var score := (mg_score * phase_c + eg_score * (PHASE_TOTAL - phase_c)) / PHASE_TOTAL
	score += 12 if pos.side == Chess.WHITE else -12  # tempo
	return score if pos.side == Chess.WHITE else -score


static func _is_passed(sq_list: PackedInt32Array, sq: int, color: int) -> bool:
	var file := sq & 7
	var rank := sq >> 3
	var enemy_pawn := Chess.make_piece(Chess.PAWN, color ^ 1)
	var step := 1 if color == 0 else -1
	var r := rank + step
	while r >= 0 and r <= 7:
		for f in [file - 1, file, file + 1]:
			if f >= 0 and f <= 7 and sq_list[r * 8 + f] == enemy_pawn:
				return false
		r += step
	return true

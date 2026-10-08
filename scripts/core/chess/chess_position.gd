class_name ChessPosition
extends RefCounted
## Complete chess position with fast make/unmake, legal move generation,
## attack detection, Zobrist hashing and FEN import/export.
##
## Move generation uses the classic 10x12 mailbox so off-board detection is a
## single table lookup. All state is integers and packed arrays, which keeps
## the class cheap to clone for the AI thread.

const MAILBOX: Array[int] = [
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1,  0,  1,  2,  3,  4,  5,  6,  7, -1,
	-1,  8,  9, 10, 11, 12, 13, 14, 15, -1,
	-1, 16, 17, 18, 19, 20, 21, 22, 23, -1,
	-1, 24, 25, 26, 27, 28, 29, 30, 31, -1,
	-1, 32, 33, 34, 35, 36, 37, 38, 39, -1,
	-1, 40, 41, 42, 43, 44, 45, 46, 47, -1,
	-1, 48, 49, 50, 51, 52, 53, 54, 55, -1,
	-1, 56, 57, 58, 59, 60, 61, 62, 63, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
]

const MAILBOX64: Array[int] = [
	21, 22, 23, 24, 25, 26, 27, 28,
	31, 32, 33, 34, 35, 36, 37, 38,
	41, 42, 43, 44, 45, 46, 47, 48,
	51, 52, 53, 54, 55, 56, 57, 58,
	61, 62, 63, 64, 65, 66, 67, 68,
	71, 72, 73, 74, 75, 76, 77, 78,
	81, 82, 83, 84, 85, 86, 87, 88,
	91, 92, 93, 94, 95, 96, 97, 98,
]

const KNIGHT_OFFSETS: Array[int] = [-21, -19, -12, -8, 8, 12, 19, 21]
const BISHOP_OFFSETS: Array[int] = [-11, -9, 9, 11]
const ROOK_OFFSETS: Array[int] = [-10, -1, 1, 10]
const KING_OFFSETS: Array[int] = [-11, -10, -9, -1, 1, 9, 10, 11]
const PROMO_TYPES: Array[int] = [Chess.QUEEN, Chess.ROOK, Chess.BISHOP, Chess.KNIGHT]

## Castling rights that survive a move touching a square (from or to).
const CASTLE_MASK: Array[int] = [
	13, 15, 15, 15, 12, 15, 15, 14,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	15, 15, 15, 15, 15, 15, 15, 15,
	 7, 15, 15, 15,  3, 15, 15, 11,
]

const UNDO_STRIDE := 6

static var _zobrist_pieces := PackedInt64Array()
static var _zobrist_castling := PackedInt64Array()
static var _zobrist_ep := PackedInt64Array()
static var _zobrist_side: int = 0

var squares := PackedInt32Array()
var side: int = Chess.WHITE
var castling: int = 0
var ep_square: int = Chess.NO_SQUARE
var halfmove_clock: int = 0
var fullmove_number: int = 1
var hash: int = 0
var king_square := PackedInt32Array([4, 60])
## Hashes of every position reached so far (including the current one) for
## repetition detection. Truncated on unmake.
var hash_history := PackedInt64Array()

var _undo := PackedInt64Array()


static func _static_init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED_C4E55
	_zobrist_pieces.resize(16 * 64)
	for i in _zobrist_pieces.size():
		_zobrist_pieces[i] = _rand64(rng)
	_zobrist_castling.resize(16)
	for i in 16:
		_zobrist_castling[i] = _rand64(rng)
	_zobrist_ep.resize(8)
	for i in 8:
		_zobrist_ep[i] = _rand64(rng)
	_zobrist_side = _rand64(rng)


static func _rand64(rng: RandomNumberGenerator) -> int:
	return (rng.randi() << 32) ^ rng.randi()


func _init(fen: String = Chess.START_FEN) -> void:
	squares.resize(64)
	if not set_fen(fen):
		push_error("ChessPosition: invalid FEN '%s', falling back to start position" % fen)
		set_fen(Chess.START_FEN)


# --------------------------------------------------------------------------
# FEN
# --------------------------------------------------------------------------

## Loads a FEN string. Returns false (and leaves the position untouched) when
## the FEN is malformed or describes an impossible position.
func set_fen(fen: String) -> bool:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 4:
		return false
	var new_squares := PackedInt32Array()
	new_squares.resize(64)
	var rows := parts[0].split("/")
	if rows.size() != 8:
		return false
	var kings := [0, 0]
	var new_king_sq := PackedInt32Array([-1, -1])
	for r in 8:
		var rank := 7 - r
		var file := 0
		for c in rows[r]:
			if c >= "1" and c <= "8":
				file += c.to_int()
			else:
				var piece := Chess.char_to_piece(c)
				if piece == Chess.EMPTY or file > 7:
					return false
				var sq := rank * 8 + file
				new_squares[sq] = piece
				if (piece & 7) == Chess.KING:
					kings[piece >> 3] += 1
					new_king_sq[piece >> 3] = sq
				if (piece & 7) == Chess.PAWN and (rank == 0 or rank == 7):
					return false
				file += 1
		if file != 8:
			return false
	if kings[0] != 1 or kings[1] != 1:
		return false
	var new_side: int
	match parts[1]:
		"w": new_side = Chess.WHITE
		"b": new_side = Chess.BLACK
		_: return false
	var new_castling := 0
	if parts[2] != "-":
		for c in parts[2]:
			match c:
				"K": new_castling |= Chess.CASTLE_WK
				"Q": new_castling |= Chess.CASTLE_WQ
				"k": new_castling |= Chess.CASTLE_BK
				"q": new_castling |= Chess.CASTLE_BQ
				_: return false
	# Drop castling rights that the piece placement cannot support.
	if new_squares[4] != Chess.make_piece(Chess.KING, Chess.WHITE):
		new_castling &= ~(Chess.CASTLE_WK | Chess.CASTLE_WQ)
	if new_squares[7] != Chess.make_piece(Chess.ROOK, Chess.WHITE):
		new_castling &= ~Chess.CASTLE_WK
	if new_squares[0] != Chess.make_piece(Chess.ROOK, Chess.WHITE):
		new_castling &= ~Chess.CASTLE_WQ
	if new_squares[60] != Chess.make_piece(Chess.KING, Chess.BLACK):
		new_castling &= ~(Chess.CASTLE_BK | Chess.CASTLE_BQ)
	if new_squares[63] != Chess.make_piece(Chess.ROOK, Chess.BLACK):
		new_castling &= ~Chess.CASTLE_BK
	if new_squares[56] != Chess.make_piece(Chess.ROOK, Chess.BLACK):
		new_castling &= ~Chess.CASTLE_BQ
	var new_ep := Chess.NO_SQUARE
	if parts[3] != "-":
		new_ep = Chess.parse_square(parts[3])
		if new_ep == Chess.NO_SQUARE:
			return false
	squares = new_squares
	side = new_side
	castling = new_castling
	ep_square = new_ep
	king_square = new_king_sq
	halfmove_clock = parts[4].to_int() if parts.size() > 4 else 0
	fullmove_number = maxi(1, parts[5].to_int()) if parts.size() > 5 else 1
	# The side not to move must not be in check.
	if is_square_attacked(king_square[side ^ 1], side):
		set_fen(Chess.START_FEN)
		return false
	_undo.clear()
	hash = compute_hash()
	hash_history = PackedInt64Array([hash])
	return true


func get_fen() -> String:
	var rows := PackedStringArray()
	for r in 8:
		var rank := 7 - r
		var row := ""
		var empty := 0
		for file in 8:
			var piece := squares[rank * 8 + file]
			if piece == Chess.EMPTY:
				empty += 1
			else:
				if empty > 0:
					row += str(empty)
					empty = 0
				row += Chess.piece_to_char(piece)
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var rights := ""
	if castling & Chess.CASTLE_WK: rights += "K"
	if castling & Chess.CASTLE_WQ: rights += "Q"
	if castling & Chess.CASTLE_BK: rights += "k"
	if castling & Chess.CASTLE_BQ: rights += "q"
	if rights.is_empty():
		rights = "-"
	return "%s %s %s %s %d %d" % [
		"/".join(rows), "w" if side == Chess.WHITE else "b", rights,
		Chess.square_name(ep_square) if ep_square >= 0 else "-",
		halfmove_clock, fullmove_number]


func clone() -> ChessPosition:
	var copy := ChessPosition.new()
	copy.squares = squares.duplicate()
	copy.side = side
	copy.castling = castling
	copy.ep_square = ep_square
	copy.halfmove_clock = halfmove_clock
	copy.fullmove_number = fullmove_number
	copy.hash = hash
	copy.king_square = king_square.duplicate()
	copy.hash_history = hash_history.duplicate()
	return copy


func piece_at(sq: int) -> int:
	return squares[sq]


# --------------------------------------------------------------------------
# Hashing
# --------------------------------------------------------------------------

func compute_hash() -> int:
	var h := 0
	for sq in 64:
		var piece := squares[sq]
		if piece != Chess.EMPTY:
			h ^= _zobrist_pieces[piece * 64 + sq]
	h ^= _zobrist_castling[castling]
	if _ep_is_capturable():
		h ^= _zobrist_ep[ep_square & 7]
	if side == Chess.BLACK:
		h ^= _zobrist_side
	return h


## The en passant square only distinguishes positions (FIDE repetition rule)
## when a pawn of the side to move can actually capture there.
func _ep_is_capturable() -> bool:
	if ep_square == Chess.NO_SQUARE:
		return false
	var pawn := Chess.make_piece(Chess.PAWN, side)
	var from_rank_offset := -10 if side == Chess.WHITE else 10
	var e120 := MAILBOX64[ep_square]
	for o in [from_rank_offset - 1, from_rank_offset + 1]:
		var sq := MAILBOX[e120 + o]
		if sq != -1 and squares[sq] == pawn:
			return true
	return false


# --------------------------------------------------------------------------
# Attacks
# --------------------------------------------------------------------------

func is_square_attacked(sq: int, by: int) -> bool:
	var s120 := MAILBOX64[sq]
	var t: int
	# Pawns of `by` attack diagonally forward, so they sit one rank "behind".
	var pawn := Chess.PAWN | (by << 3)
	var back := -10 if by == Chess.WHITE else 10
	t = MAILBOX[s120 + back - 1]
	if t != -1 and squares[t] == pawn:
		return true
	t = MAILBOX[s120 + back + 1]
	if t != -1 and squares[t] == pawn:
		return true
	var knight := Chess.KNIGHT | (by << 3)
	for o in KNIGHT_OFFSETS:
		t = MAILBOX[s120 + o]
		if t != -1 and squares[t] == knight:
			return true
	var king := Chess.KING | (by << 3)
	for o in KING_OFFSETS:
		t = MAILBOX[s120 + o]
		if t != -1 and squares[t] == king:
			return true
	var bishop := Chess.BISHOP | (by << 3)
	var rook := Chess.ROOK | (by << 3)
	var queen := Chess.QUEEN | (by << 3)
	for o in BISHOP_OFFSETS:
		var n := s120 + o
		t = MAILBOX[n]
		while t != -1:
			var p := squares[t]
			if p != Chess.EMPTY:
				if p == bishop or p == queen:
					return true
				break
			n += o
			t = MAILBOX[n]
	for o in ROOK_OFFSETS:
		var n := s120 + o
		t = MAILBOX[n]
		while t != -1:
			var p := squares[t]
			if p != Chess.EMPTY:
				if p == rook or p == queen:
					return true
				break
			n += o
			t = MAILBOX[n]
	return false


func is_in_check(color: int = -1) -> bool:
	var c := side if color < 0 else color
	return is_square_attacked(king_square[c], c ^ 1)


## Squares of `by` pieces that attack `sq`; used by the UI and AI.
func attackers_of(sq: int, by: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var saved := squares[sq]
	for from in 64:
		var piece := squares[from]
		if piece == Chess.EMPTY or (piece >> 3) != by:
			continue
		# Pretend an enemy stands on `sq` so pawn captures are generated.
		squares[sq] = Chess.make_piece(Chess.PAWN, by ^ 1) if saved == Chess.EMPTY else saved
		var hits := _piece_targets(from)
		squares[sq] = saved
		if sq in hits:
			result.append(from)
	return result


func _piece_targets(from: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var piece := squares[from]
	var type := piece & 7
	var color := piece >> 3
	var f120 := MAILBOX64[from]
	if type == Chess.PAWN:
		var fwd := 10 if color == Chess.WHITE else -10
		for o in [fwd - 1, fwd + 1]:
			var t := MAILBOX[f120 + o]
			if t != -1:
				result.append(t)
		return result
	var offsets: Array[int]
	var slide := false
	match type:
		Chess.KNIGHT: offsets = KNIGHT_OFFSETS
		Chess.BISHOP: offsets = BISHOP_OFFSETS; slide = true
		Chess.ROOK: offsets = ROOK_OFFSETS; slide = true
		Chess.QUEEN: offsets = KING_OFFSETS; slide = true
		Chess.KING: offsets = KING_OFFSETS
	for o in offsets:
		var n := f120 + o
		var t := MAILBOX[n]
		while t != -1:
			result.append(t)
			if not slide or squares[t] != Chess.EMPTY:
				break
			n += o
			t = MAILBOX[n]
	return result


# --------------------------------------------------------------------------
# Move generation
# --------------------------------------------------------------------------

## Pseudo-legal moves (may leave the own king in check). With
## `tactical_only`, only captures and promotions are generated (quiescence).
func generate_pseudo_moves(tactical_only: bool = false) -> PackedInt32Array:
	var moves := PackedInt32Array()
	var us := side
	var them := us ^ 1
	for from in 64:
		var piece := squares[from]
		if piece == Chess.EMPTY or (piece >> 3) != us:
			continue
		var type := piece & 7
		var f120 := MAILBOX64[from]
		if type == Chess.PAWN:
			var fwd := 10 if us == Chess.WHITE else -10
			var rank := from >> 3
			var promo_next := (rank == 6) if us == Chess.WHITE else (rank == 1)
			for o in [fwd - 1, fwd + 1]:
				var to := MAILBOX[f120 + o]
				if to == -1:
					continue
				var target := squares[to]
				if target != Chess.EMPTY and (target >> 3) == them:
					if promo_next:
						for promo in PROMO_TYPES:
							moves.append(from | (to << 6) | (promo << 12) | ((Chess.FLAG_CAPTURE | Chess.FLAG_PROMOTION) << 15))
					else:
						moves.append(from | (to << 6) | (Chess.FLAG_CAPTURE << 15))
				elif to == ep_square:
					moves.append(from | (to << 6) | (Chess.FLAG_EN_PASSANT << 15))
			var one := MAILBOX[f120 + fwd]
			if one != -1 and squares[one] == Chess.EMPTY:
				if promo_next:
					for promo in PROMO_TYPES:
						moves.append(from | (one << 6) | (promo << 12) | (Chess.FLAG_PROMOTION << 15))
				elif not tactical_only:
					moves.append(from | (one << 6))
					var start := (rank == 1) if us == Chess.WHITE else (rank == 6)
					if start:
						var two := MAILBOX[f120 + fwd * 2]
						if squares[two] == Chess.EMPTY:
							moves.append(from | (two << 6) | (Chess.FLAG_DOUBLE_PUSH << 15))
			continue
		var offsets: Array[int]
		var slide := false
		match type:
			Chess.KNIGHT: offsets = KNIGHT_OFFSETS
			Chess.BISHOP: offsets = BISHOP_OFFSETS; slide = true
			Chess.ROOK: offsets = ROOK_OFFSETS; slide = true
			Chess.QUEEN: offsets = KING_OFFSETS; slide = true
			Chess.KING: offsets = KING_OFFSETS
		for o in offsets:
			var n := f120 + o
			var to := MAILBOX[n]
			while to != -1:
				var target := squares[to]
				if target == Chess.EMPTY:
					if not tactical_only:
						moves.append(from | (to << 6))
				else:
					if (target >> 3) == them:
						moves.append(from | (to << 6) | (Chess.FLAG_CAPTURE << 15))
					break
				if not slide:
					break
				n += o
				to = MAILBOX[n]
	if not tactical_only:
		_generate_castling(moves, us)
	return moves


func _generate_castling(moves: PackedInt32Array, us: int) -> void:
	var them := us ^ 1
	if us == Chess.WHITE:
		if castling & (Chess.CASTLE_WK | Chess.CASTLE_WQ) == 0 or is_square_attacked(4, them):
			return
		if castling & Chess.CASTLE_WK and squares[5] == 0 and squares[6] == 0 \
				and not is_square_attacked(5, them) and not is_square_attacked(6, them):
			moves.append(4 | (6 << 6) | (Chess.FLAG_CASTLE << 15))
		if castling & Chess.CASTLE_WQ and squares[3] == 0 and squares[2] == 0 and squares[1] == 0 \
				and not is_square_attacked(3, them) and not is_square_attacked(2, them):
			moves.append(4 | (2 << 6) | (Chess.FLAG_CASTLE << 15))
	else:
		if castling & (Chess.CASTLE_BK | Chess.CASTLE_BQ) == 0 or is_square_attacked(60, them):
			return
		if castling & Chess.CASTLE_BK and squares[61] == 0 and squares[62] == 0 \
				and not is_square_attacked(61, them) and not is_square_attacked(62, them):
			moves.append(60 | (62 << 6) | (Chess.FLAG_CASTLE << 15))
		if castling & Chess.CASTLE_BQ and squares[59] == 0 and squares[58] == 0 and squares[57] == 0 \
				and not is_square_attacked(59, them) and not is_square_attacked(58, them):
			moves.append(60 | (58 << 6) | (Chess.FLAG_CASTLE << 15))


func generate_legal_moves() -> PackedInt32Array:
	var legal := PackedInt32Array()
	for move in generate_pseudo_moves():
		if make_move(move):
			legal.append(move)
			unmake_move()
	return legal


func legal_moves_from(sq: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for move in generate_legal_moves():
		if (move & 63) == sq:
			result.append(move)
	return result


## Finds the legal move matching from/to (and promotion type when relevant).
func find_legal_move(from: int, to: int, promo: int = 0) -> int:
	for move in generate_legal_moves():
		if (move & 63) == from and ((move >> 6) & 63) == to:
			var p := (move >> 12) & 7
			if p == promo or (p != 0 and promo == 0 and p == Chess.QUEEN):
				return move
	return Chess.NO_MOVE


func has_legal_move() -> bool:
	for move in generate_pseudo_moves():
		if make_move(move):
			unmake_move()
			return true
	return false


# --------------------------------------------------------------------------
# Make / unmake
# --------------------------------------------------------------------------

## Applies a pseudo-legal move. Returns false (and restores the position) if
## the move would leave the mover's king in check.
func make_move(move: int) -> bool:
	var from := move & 63
	var to := (move >> 6) & 63
	var promo := (move >> 12) & 7
	var flags := (move >> 15) & 31
	var piece := squares[from]
	var captured := squares[to]
	var us := side
	_undo.append(move)
	_undo.append(captured)
	_undo.append(castling)
	_undo.append(ep_square)
	_undo.append(halfmove_clock)
	_undo.append(hash)

	var h := hash
	if _ep_is_capturable():
		h ^= _zobrist_ep[ep_square & 7]
	h ^= _zobrist_castling[castling]

	if flags & Chess.FLAG_EN_PASSANT:
		var cap_sq := to - 8 if us == Chess.WHITE else to + 8
		captured = squares[cap_sq]
		squares[cap_sq] = Chess.EMPTY
		h ^= _zobrist_pieces[captured * 64 + cap_sq]
		_undo[_undo.size() - 5] = captured
	elif captured != Chess.EMPTY:
		h ^= _zobrist_pieces[captured * 64 + to]

	squares[from] = Chess.EMPTY
	h ^= _zobrist_pieces[piece * 64 + from]
	var placed := piece
	if promo != 0:
		placed = promo | (us << 3)
	squares[to] = placed
	h ^= _zobrist_pieces[placed * 64 + to]

	if (piece & 7) == Chess.KING:
		king_square[us] = to
		if flags & Chess.FLAG_CASTLE:
			var rook_from: int
			var rook_to: int
			if to > from:
				rook_from = from + 3
				rook_to = from + 1
			else:
				rook_from = from - 4
				rook_to = from - 1
			var rook := squares[rook_from]
			squares[rook_from] = Chess.EMPTY
			squares[rook_to] = rook
			h ^= _zobrist_pieces[rook * 64 + rook_from]
			h ^= _zobrist_pieces[rook * 64 + rook_to]

	castling &= CASTLE_MASK[from] & CASTLE_MASK[to]
	h ^= _zobrist_castling[castling]

	if (piece & 7) == Chess.PAWN or captured != Chess.EMPTY:
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	if us == Chess.BLACK:
		fullmove_number += 1

	side = us ^ 1
	h ^= _zobrist_side
	ep_square = ((from + to) >> 1) if flags & Chess.FLAG_DOUBLE_PUSH else Chess.NO_SQUARE
	if _ep_is_capturable():
		h ^= _zobrist_ep[ep_square & 7]
	hash = h
	hash_history.append(h)

	if is_square_attacked(king_square[us], side):
		unmake_move()
		return false
	return true


func unmake_move() -> void:
	var base := _undo.size() - UNDO_STRIDE
	if base < 0:
		push_error("ChessPosition.unmake_move: nothing to undo")
		return
	var move := _undo[base]
	var captured := _undo[base + 1]
	castling = _undo[base + 2]
	ep_square = _undo[base + 3]
	halfmove_clock = _undo[base + 4]
	hash = _undo[base + 5]
	_undo.resize(base)
	hash_history.resize(hash_history.size() - 1)

	var from := move & 63
	var to := (move >> 6) & 63
	var promo := (move >> 12) & 7
	var flags := (move >> 15) & 31
	side ^= 1
	var us := side
	if us == Chess.BLACK:
		fullmove_number -= 1
	var piece := squares[to]
	if promo != 0:
		piece = Chess.PAWN | (us << 3)
	squares[from] = piece
	if flags & Chess.FLAG_EN_PASSANT:
		squares[to] = Chess.EMPTY
		squares[to - 8 if us == Chess.WHITE else to + 8] = captured
	else:
		squares[to] = captured
	if (piece & 7) == Chess.KING:
		king_square[us] = from
		if flags & Chess.FLAG_CASTLE:
			var rook_from: int
			var rook_to: int
			if to > from:
				rook_from = from + 3
				rook_to = from + 1
			else:
				rook_from = from - 4
				rook_to = from - 1
			squares[rook_from] = squares[rook_to]
			squares[rook_to] = Chess.EMPTY


## "Null move" for the AI's null-move pruning: passes the turn.
func make_null_move() -> void:
	_undo.append(0)
	_undo.append(0)
	_undo.append(castling)
	_undo.append(ep_square)
	_undo.append(halfmove_clock)
	_undo.append(hash)
	var h := hash
	if _ep_is_capturable():
		h ^= _zobrist_ep[ep_square & 7]
	ep_square = Chess.NO_SQUARE
	side ^= 1
	h ^= _zobrist_side
	hash = h
	hash_history.append(h)


func unmake_null_move() -> void:
	var base := _undo.size() - UNDO_STRIDE
	castling = _undo[base + 2]
	ep_square = _undo[base + 3]
	halfmove_clock = _undo[base + 4]
	hash = _undo[base + 5]
	_undo.resize(base)
	hash_history.resize(hash_history.size() - 1)
	side ^= 1


func undo_depth() -> int:
	return _undo.size() / UNDO_STRIDE


# --------------------------------------------------------------------------
# Draw helpers
# --------------------------------------------------------------------------

## Number of times the current position occurred (current one included),
## only looking back to the last irreversible move.
func repetition_count() -> int:
	var count := 1
	var n := hash_history.size()
	var limit := mini(halfmove_clock, n - 1)
	var i := 2
	while i <= limit:
		if hash_history[n - 1 - i] == hash:
			count += 1
		i += 2
	return count


func is_insufficient_material() -> bool:
	var minors := [0, 0]
	var bishop_colors := []
	for sq in 64:
		var piece := squares[sq]
		if piece == Chess.EMPTY:
			continue
		match piece & 7:
			Chess.KING:
				continue
			Chess.PAWN, Chess.ROOK, Chess.QUEEN:
				return false
			Chess.KNIGHT:
				minors[piece >> 3] += 1
			Chess.BISHOP:
				minors[piece >> 3] += 1
				bishop_colors.append(((sq >> 3) + (sq & 7)) & 1)
	var total: int = minors[0] + minors[1]
	if total <= 1:
		return true
	# Only bishops, all on the same square colour: no mate is possible.
	if bishop_colors.size() == total:
		var first: int = bishop_colors[0]
		for c in bishop_colors:
			if c != first:
				return false
		return true
	return false


## True when `color` has any piece that could ever deliver mate (used for
## the "flag fall vs insufficient material" rule).
func has_mating_material(color: int) -> bool:
	var minors := 0
	for sq in 64:
		var piece := squares[sq]
		if piece == Chess.EMPTY or (piece >> 3) != color:
			continue
		match piece & 7:
			Chess.PAWN, Chess.ROOK, Chess.QUEEN:
				return true
			Chess.KNIGHT, Chess.BISHOP:
				minors += 1
	return minors >= 2


func material_count(color: int) -> int:
	var total := 0
	for sq in 64:
		var piece := squares[sq]
		if piece != Chess.EMPTY and (piece >> 3) == color:
			total += Chess.PIECE_VALUES[piece & 7]
	return total


func to_ascii() -> String:
	var lines := PackedStringArray()
	for r in 8:
		var rank := 7 - r
		var line := str(rank + 1) + " "
		for file in 8:
			line += Chess.piece_to_char(squares[rank * 8 + file]) + " "
		lines.append(line)
	lines.append("  a b c d e f g h")
	return "\n".join(lines)

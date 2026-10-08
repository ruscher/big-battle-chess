class_name Chess
extends RefCounted
## Shared constants and helpers of the chess core.
##
## The core is completely independent from scenes, animation and UI. Pieces,
## squares and moves are plain integers so search and validation stay fast in
## GDScript:
##   piece  = type | (color << 3)          (0 = empty)
##   square = rank * 8 + file              (a1 = 0, h8 = 63)
##   move   = from | to << 6 | promo << 12 | flags << 15

const WHITE := 0
const BLACK := 1

const EMPTY := 0
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const FLAG_CAPTURE := 1
const FLAG_DOUBLE_PUSH := 2
const FLAG_EN_PASSANT := 4
const FLAG_CASTLE := 8
const FLAG_PROMOTION := 16

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

const NO_SQUARE := -1
const NO_MOVE := 0

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

const TYPE_NAMES: Array[StringName] = [&"none", &"pawn", &"knight", &"bishop", &"rook", &"queen", &"king"]
const PIECE_CHARS := ".PNBRQK"
const FILES := "abcdefgh"

## Conventional material values in centipawns, used by UI (material balance)
## and as the base of the AI evaluation.
const PIECE_VALUES: Array[int] = [0, 100, 320, 330, 500, 900, 0]


static func make_piece(type: int, color: int) -> int:
	return type | (color << 3)


static func piece_type(piece: int) -> int:
	return piece & 7


static func piece_color(piece: int) -> int:
	return piece >> 3


static func square(file: int, rank: int) -> int:
	return rank * 8 + file


static func file_of(sq: int) -> int:
	return sq & 7


static func rank_of(sq: int) -> int:
	return sq >> 3


static func square_name(sq: int) -> String:
	if sq < 0 or sq > 63:
		return "-"
	return FILES[sq & 7] + str((sq >> 3) + 1)


static func parse_square(text: String) -> int:
	if text.length() != 2:
		return NO_SQUARE
	var file := FILES.find(text[0])
	var rank := text.unicode_at(1) - 49  # '1' == 49
	if file < 0 or rank < 0 or rank > 7:
		return NO_SQUARE
	return rank * 8 + file


static func encode_move(from: int, to: int, promo: int = 0, flags: int = 0) -> int:
	return from | (to << 6) | (promo << 12) | (flags << 15)


static func move_from(move: int) -> int:
	return move & 63


static func move_to(move: int) -> int:
	return (move >> 6) & 63


static func move_promo(move: int) -> int:
	return (move >> 12) & 7


static func move_flags(move: int) -> int:
	return (move >> 15) & 31


static func is_capture(move: int) -> bool:
	return ((move >> 15) & (FLAG_CAPTURE | FLAG_EN_PASSANT)) != 0


static func piece_to_char(piece: int) -> String:
	if piece == EMPTY:
		return "."
	var c := PIECE_CHARS[piece & 7]
	return c if (piece >> 3) == WHITE else c.to_lower()


static func char_to_piece(c: String) -> int:
	var type := PIECE_CHARS.find(c.to_upper())
	if type <= 0:
		return EMPTY
	return make_piece(type, WHITE if c == c.to_upper() else BLACK)


static func type_name(type: int) -> StringName:
	return TYPE_NAMES[clampi(type, 0, 6)]


static func color_name(color: int) -> StringName:
	return &"white" if color == WHITE else &"black"


## Long algebraic (UCI) form, e.g. "e2e4", "e7e8q".
static func move_to_uci(move: int) -> String:
	if move == NO_MOVE:
		return "0000"
	var text := square_name(move_from(move)) + square_name(move_to(move))
	var promo := move_promo(move)
	if promo != 0:
		text += PIECE_CHARS[promo].to_lower()
	return text

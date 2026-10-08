class_name ChessMoveRecord
extends RefCounted
## Immutable description of a committed move. It is the only data the
## presentation layer (board view, battle director, audio, HUD) needs to show
## the move, so visuals never have to query the rules engine.

var move: int = Chess.NO_MOVE
var ply: int = 0
var color: int = Chess.WHITE
var piece_type: int = Chess.EMPTY
var from_square: int = 0
var to_square: int = 0
var san: String = ""
var uci: String = ""
var captured_type: int = Chess.EMPTY
var captured_square: int = Chess.NO_SQUARE
var promotion_type: int = Chess.EMPTY
var is_castle: bool = false
var rook_from: int = Chess.NO_SQUARE
var rook_to: int = Chess.NO_SQUARE
var is_en_passant: bool = false
var gives_check: bool = false
var is_checkmate: bool = false
var fen_before: String = ""
var fen_after: String = ""


func is_capture() -> bool:
	return captured_type != Chess.EMPTY


## Deterministic seed for presentation variety (same move => same cinematic),
## so replays and both players in a future online match see the same battle.
func presentation_seed() -> int:
	return hash(fen_before + uci)


static func create(pos: ChessPosition, move: int, ply_index: int) -> ChessMoveRecord:
	var r := ChessMoveRecord.new()
	r.move = move
	r.ply = ply_index
	r.from_square = Chess.move_from(move)
	r.to_square = Chess.move_to(move)
	var piece := pos.squares[r.from_square]
	r.color = piece >> 3
	r.piece_type = piece & 7
	r.uci = Chess.move_to_uci(move)
	r.san = ChessNotation.move_to_san(pos, move)
	r.fen_before = pos.get_fen()
	r.promotion_type = Chess.move_promo(move)
	var flags := Chess.move_flags(move)
	if flags & Chess.FLAG_EN_PASSANT:
		r.is_en_passant = true
		r.captured_square = r.to_square - 8 if r.color == Chess.WHITE else r.to_square + 8
		r.captured_type = Chess.PAWN
	elif flags & Chess.FLAG_CAPTURE:
		r.captured_square = r.to_square
		r.captured_type = pos.squares[r.to_square] & 7
	if flags & Chess.FLAG_CASTLE:
		r.is_castle = true
		if r.to_square > r.from_square:
			r.rook_from = r.from_square + 3
			r.rook_to = r.from_square + 1
		else:
			r.rook_from = r.from_square - 4
			r.rook_to = r.from_square - 1
	r.gives_check = r.san.ends_with("+") or r.san.ends_with("#")
	r.is_checkmate = r.san.ends_with("#")
	return r

class_name ChessMatch
extends RefCounted
## Authoritative match controller: owns the position, validates and commits
## moves, tracks history (undo/redo), results, draw offers and serialization.
##
## The result of every move is decided here, before any animation runs. The
## presentation layer only replays ChessMoveRecords.

signal move_committed(record: ChessMoveRecord)
signal history_changed
signal game_ended(result: Result, reason: Reason)

enum Result { ONGOING, WHITE_WINS, BLACK_WINS, DRAW }
enum Reason {
	NONE,
	CHECKMATE,
	STALEMATE,
	INSUFFICIENT_MATERIAL,
	FIFTY_MOVE_RULE,
	SEVENTY_FIVE_MOVE_RULE,
	THREEFOLD_REPETITION,
	FIVEFOLD_REPETITION,
	RESIGNATION,
	AGREEMENT,
	TIMEOUT,
	TIMEOUT_INSUFFICIENT_MATERIAL,
}

const REASON_KEYS := {
	Reason.NONE: "",
	Reason.CHECKMATE: "REASON_CHECKMATE",
	Reason.STALEMATE: "REASON_STALEMATE",
	Reason.INSUFFICIENT_MATERIAL: "REASON_INSUFFICIENT",
	Reason.FIFTY_MOVE_RULE: "REASON_FIFTY",
	Reason.SEVENTY_FIVE_MOVE_RULE: "REASON_SEVENTY_FIVE",
	Reason.THREEFOLD_REPETITION: "REASON_THREEFOLD",
	Reason.FIVEFOLD_REPETITION: "REASON_FIVEFOLD",
	Reason.RESIGNATION: "REASON_RESIGNATION",
	Reason.AGREEMENT: "REASON_AGREEMENT",
	Reason.TIMEOUT: "REASON_TIMEOUT",
	Reason.TIMEOUT_INSUFFICIENT_MATERIAL: "REASON_TIMEOUT_INSUFFICIENT",
}

var position: ChessPosition
var start_fen: String = Chess.START_FEN
var records: Array[ChessMoveRecord] = []
var result: Result = Result.ONGOING
var reason: Reason = Reason.NONE
## Side currently offering a draw, or -1.
var draw_offer_from: int = -1
var tags: Dictionary = {}

var _redo: Array[int] = []


func _init(fen: String = Chess.START_FEN) -> void:
	reset(fen)


func reset(fen: String = Chess.START_FEN) -> bool:
	var pos := ChessPosition.new()
	if not pos.set_fen(fen):
		return false
	position = pos
	start_fen = pos.get_fen()
	records.clear()
	_redo.clear()
	result = Result.ONGOING
	reason = Reason.NONE
	draw_offer_from = -1
	_update_status(false)
	history_changed.emit()
	return true


func side_to_move() -> int:
	return position.side


func is_over() -> bool:
	return result != Result.ONGOING


func legal_moves() -> PackedInt32Array:
	if is_over():
		return PackedInt32Array()
	return position.generate_legal_moves()


func legal_moves_from(sq: int) -> PackedInt32Array:
	if is_over():
		return PackedInt32Array()
	return position.legal_moves_from(sq)


func is_legal(move: int) -> bool:
	return not is_over() and move in position.generate_legal_moves()


## Validates and commits a move. Returns null if it is illegal.
func play_move(move: int) -> ChessMoveRecord:
	return _play(move, true)


func play_uci(text: String) -> ChessMoveRecord:
	var from := Chess.parse_square(text.substr(0, 2))
	var to := Chess.parse_square(text.substr(2, 2))
	var promo := 0
	if text.length() > 4:
		promo = Chess.PIECE_CHARS.find(text[4].to_upper())
	if from < 0 or to < 0:
		return null
	var move := position.find_legal_move(from, to, promo)
	return null if move == Chess.NO_MOVE else play_move(move)


func play_san(text: String) -> ChessMoveRecord:
	var move := ChessNotation.san_to_move(position, text)
	return null if move == Chess.NO_MOVE else play_move(move)


func _play(move: int, clear_redo: bool) -> ChessMoveRecord:
	if not is_legal(move):
		return null
	var record := ChessMoveRecord.create(position, move, records.size())
	position.make_move(move)
	record.fen_after = position.get_fen()
	records.append(record)
	if clear_redo:
		_redo.clear()
	# A pending draw offer is declined implicitly by the opponent moving.
	if draw_offer_from != -1 and draw_offer_from != record.color:
		draw_offer_from = -1
	move_committed.emit(record)
	_update_status(true)
	history_changed.emit()
	return record


func can_undo() -> bool:
	return not records.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty() and not is_over()


## Takes back the last ply. Reopens a finished game (e.g. after checkmate).
func undo() -> bool:
	if records.is_empty():
		return false
	var record: ChessMoveRecord = records.pop_back()
	position.unmake_move()
	_redo.append(record.move)
	result = Result.ONGOING
	reason = Reason.NONE
	draw_offer_from = -1
	_update_status(false)
	history_changed.emit()
	return true


func redo() -> ChessMoveRecord:
	if _redo.is_empty():
		return null
	var move: int = _redo.pop_back()
	var record := _play(move, false)
	if record == null:
		_redo.clear()
	return record


# --------------------------------------------------------------------------
# Results
# --------------------------------------------------------------------------

func _update_status(emit: bool) -> void:
	if is_over():
		return
	var new_result := Result.ONGOING
	var new_reason := Reason.NONE
	if not position.has_legal_move():
		if position.is_in_check():
			new_result = Result.BLACK_WINS if position.side == Chess.WHITE else Result.WHITE_WINS
			new_reason = Reason.CHECKMATE
		else:
			new_result = Result.DRAW
			new_reason = Reason.STALEMATE
	elif position.is_insufficient_material():
		new_result = Result.DRAW
		new_reason = Reason.INSUFFICIENT_MATERIAL
	elif position.repetition_count() >= 5:
		new_result = Result.DRAW
		new_reason = Reason.FIVEFOLD_REPETITION
	elif position.halfmove_clock >= 150:
		new_result = Result.DRAW
		new_reason = Reason.SEVENTY_FIVE_MOVE_RULE
	if new_result != Result.ONGOING:
		_finish(new_result, new_reason, emit)


func _finish(new_result: Result, new_reason: Reason, emit: bool = true) -> void:
	result = new_result
	reason = new_reason
	draw_offer_from = -1
	if emit:
		game_ended.emit(result, reason)


## Draw that a player may claim but that is not automatic (FIDE 9.2 / 9.3).
func claimable_draw_reason() -> Reason:
	if is_over():
		return Reason.NONE
	if position.repetition_count() >= 3:
		return Reason.THREEFOLD_REPETITION
	if position.halfmove_clock >= 100:
		return Reason.FIFTY_MOVE_RULE
	return Reason.NONE


func claim_draw() -> bool:
	var claim := claimable_draw_reason()
	if claim == Reason.NONE:
		return false
	_finish(Result.DRAW, claim)
	history_changed.emit()
	return true


func resign(color: int) -> void:
	if is_over():
		return
	_finish(Result.BLACK_WINS if color == Chess.WHITE else Result.WHITE_WINS, Reason.RESIGNATION)
	history_changed.emit()


func offer_draw(color: int) -> void:
	if not is_over():
		draw_offer_from = color
		history_changed.emit()


func accept_draw(color: int) -> bool:
	if is_over() or draw_offer_from == -1 or draw_offer_from == color:
		return false
	_finish(Result.DRAW, Reason.AGREEMENT)
	history_changed.emit()
	return true


func decline_draw() -> void:
	draw_offer_from = -1
	history_changed.emit()


## Flag fall: loss, unless the opponent cannot possibly mate (FIDE 6.9).
func flag_fall(color: int) -> void:
	if is_over():
		return
	if position.has_mating_material(color ^ 1):
		_finish(Result.BLACK_WINS if color == Chess.WHITE else Result.WHITE_WINS, Reason.TIMEOUT)
	else:
		_finish(Result.DRAW, Reason.TIMEOUT_INSUFFICIENT_MATERIAL)
	history_changed.emit()


func winner() -> int:
	match result:
		Result.WHITE_WINS: return Chess.WHITE
		Result.BLACK_WINS: return Chess.BLACK
	return -1


func result_string() -> String:
	match result:
		Result.WHITE_WINS: return "1-0"
		Result.BLACK_WINS: return "0-1"
		Result.DRAW: return "1/2-1/2"
	return "*"


func last_record() -> ChessMoveRecord:
	return null if records.is_empty() else records[-1]


func captured_types(by_color: int) -> Array[int]:
	var list: Array[int] = []
	for r in records:
		if r.color == by_color and r.captured_type != Chess.EMPTY:
			list.append(r.captured_type)
	return list


# --------------------------------------------------------------------------
# Serialization
# --------------------------------------------------------------------------

func uci_moves() -> PackedStringArray:
	var list := PackedStringArray()
	for r in records:
		list.append(r.uci)
	return list


func to_dict() -> Dictionary:
	return {
		"start_fen": start_fen,
		"moves": Array(uci_moves()),
		"result": int(result),
		"reason": int(reason),
		"draw_offer_from": draw_offer_from,
		"tags": tags.duplicate(),
	}


## Rebuilds a match by replaying the stored moves, so a tampered save file
## can never produce an illegal position.
static func from_dict(data: Dictionary) -> ChessMatch:
	var m := ChessMatch.new()
	if not m.reset(str(data.get("start_fen", Chess.START_FEN))):
		return null
	for uci in data.get("moves", []):
		if m.play_uci(str(uci)) == null:
			push_warning("ChessMatch.from_dict: illegal move '%s' in save" % uci)
			return null
	m.tags = data.get("tags", {})
	var saved_result := int(data.get("result", Result.ONGOING))
	if not m.is_over() and saved_result != Result.ONGOING:
		m.result = saved_result as Result
		m.reason = int(data.get("reason", Reason.NONE)) as Reason
	if not m.is_over():
		m.draw_offer_from = int(data.get("draw_offer_from", -1))
	return m


func to_pgn() -> String:
	var header := {
		"Event": tags.get("Event", "Big Battle Chess"),
		"Site": tags.get("Site", "Big Battle Chess"),
		"Date": tags.get("Date", Time.get_date_string_from_system().replace("-", ".")),
		"Round": tags.get("Round", "-"),
		"White": tags.get("White", "White"),
		"Black": tags.get("Black", "Black"),
		"Result": result_string(),
	}
	if start_fen != Chess.START_FEN:
		header["SetUp"] = "1"
		header["FEN"] = start_fen
	if reason != Reason.NONE:
		header["Termination"] = REASON_KEYS[reason].trim_prefix("REASON_").to_lower()
	var lines := PackedStringArray()
	for key in header:
		lines.append("[%s \"%s\"]" % [key, header[key]])
	lines.append("")
	var text := ""
	var start_pos := ChessPosition.new(start_fen)
	var number := start_pos.fullmove_number
	var black_first := start_pos.side == Chess.BLACK
	for i in records.size():
		var r := records[i]
		if r.color == Chess.WHITE:
			text += "%d. " % number
		elif i == 0 and black_first:
			text += "%d... " % number
		text += r.san + " "
		if r.color == Chess.BLACK:
			number += 1
	text += result_string()
	lines.append(text)
	return "\n".join(lines) + "\n"


static func from_pgn(text: String) -> ChessMatch:
	var parsed := ChessNotation.parse_pgn(text)
	var tags_in: Dictionary = parsed["tags"]
	var m := ChessMatch.new()
	if not m.reset(str(tags_in.get("FEN", Chess.START_FEN))):
		return null
	for san in parsed["moves"]:
		if m.play_san(san) == null:
			push_warning("ChessMatch.from_pgn: illegal or unknown move '%s'" % san)
			return null
	m.tags = tags_in
	return m

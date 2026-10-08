class_name ChessSearch
extends RefCounted
## Iterative-deepening principal variation search (negamax alpha-beta) with
## a transposition table, quiescence search, null-move pruning, late move
## reductions, killer moves and history heuristic.
##
## Runs on a private copy of the position, so it is safe to execute on a
## worker thread. `stop()` may be called from another thread.

const INF := 1_000_000
const MATE := 100_000
const MATE_THRESHOLD := MATE - 1000
const MAX_PLY := 64

const TT_EXACT := 0
const TT_LOWER := 1
const TT_UPPER := 2
const TT_MAX_ENTRIES := 400_000

const ORDER_TT := 9_000_000
const ORDER_CAPTURE := 6_000_000
const ORDER_PROMO := 5_500_000
const ORDER_KILLER1 := 5_000_000
const ORDER_KILLER2 := 4_900_000

var nodes: int = 0
var completed_depth: int = 0

var _pos: ChessPosition
var _deadline: int = 0
var _stopped: bool = false
var _tt: Dictionary = {}
var _killers := PackedInt32Array()
var _history := PackedInt32Array()
var _use_quiescence := true


func stop() -> void:
	_stopped = true


## Searches `position` and returns
## {"move": int, "score": int, "depth": int, "nodes": int, "pv": String}.
## `limits`: max_depth (int), time_ms (int), quiescence (bool).
func search(position: ChessPosition, limits: Dictionary) -> Dictionary:
	_pos = position.clone()
	_stopped = false
	nodes = 0
	completed_depth = 0
	_killers.resize(MAX_PLY * 2)
	_killers.fill(0)
	_history.resize(64 * 64)
	_history.fill(0)
	if _tt.size() > TT_MAX_ENTRIES:
		_tt.clear()
	_use_quiescence = bool(limits.get("quiescence", true))
	var max_depth := int(limits.get("max_depth", 4))
	var time_ms := int(limits.get("time_ms", 2000))
	_deadline = Time.get_ticks_msec() + time_ms

	var legal := _pos.generate_legal_moves()
	if legal.is_empty():
		return {"move": Chess.NO_MOVE, "score": 0, "depth": 0, "nodes": 0, "pv": ""}
	var best_move := legal[0]
	var best_score := -INF
	if legal.size() == 1:
		return {"move": best_move, "score": 0, "depth": 0, "nodes": 0, "pv": Chess.move_to_uci(best_move)}

	for depth in range(1, max_depth + 1):
		var score := _negamax(depth, -INF, INF, 0, true)
		if _stopped and depth > 1:
			break
		var tt_move := _tt_move(_pos.hash)
		if tt_move != Chess.NO_MOVE:
			best_move = tt_move
			best_score = score
		completed_depth = depth
		if absi(score) >= MATE_THRESHOLD:
			break  # forced mate found; deeper search will not change the move
		# Stop early if half the budget is spent: the next iteration would
		# most likely not finish.
		if Time.get_ticks_msec() > _deadline - time_ms / 2:
			break
	return {
		"move": best_move,
		"score": best_score,
		"depth": completed_depth,
		"nodes": nodes,
		"pv": _principal_variation(best_move),
	}


## Scores every root move independently at a fixed depth. Used by the weaker
## difficulty levels, which then pick among near-best moves.
func score_root_moves(position: ChessPosition, depth: int, quiescence: bool) -> Array:
	_pos = position.clone()
	_stopped = false
	_use_quiescence = quiescence
	_deadline = Time.get_ticks_msec() + 10_000
	_killers.resize(MAX_PLY * 2)
	_killers.fill(0)
	_history.resize(64 * 64)
	_history.fill(0)
	var scored := []
	for move in _pos.generate_legal_moves():
		_pos.make_move(move)
		var score := -_negamax(depth - 1, -INF, INF, 1, false)
		_pos.unmake_move()
		scored.append([move, score])
	return scored


func _time_up() -> bool:
	if (nodes & 1023) == 0 and Time.get_ticks_msec() >= _deadline:
		_stopped = true
	return _stopped


func _negamax(depth: int, alpha: int, beta: int, ply: int, allow_null: bool) -> int:
	nodes += 1
	if _time_up():
		return 0
	var pos := _pos
	if ply > 0:
		if pos.halfmove_clock >= 100 or pos.repetition_count() >= 2 or pos.is_insufficient_material():
			return 0
		# Mate distance pruning.
		alpha = maxi(alpha, -MATE + ply)
		beta = mini(beta, MATE - ply - 1)
		if alpha >= beta:
			return alpha

	var in_check := pos.is_in_check()
	if in_check:
		depth += 1
	if depth <= 0:
		return _quiesce(alpha, beta, ply) if _use_quiescence else ChessEvaluator.evaluate(pos)
	if ply >= MAX_PLY - 1:
		return ChessEvaluator.evaluate(pos)

	var key := pos.hash
	var tt_move := Chess.NO_MOVE
	var entry: Variant = _tt.get(key)
	if entry != null:
		var e: int = entry
		tt_move = e & 0xFFFFF
		var e_depth := (e >> 20) & 127
		if e_depth >= depth and ply > 0:
			var e_flag := (e >> 27) & 3
			var e_score := _score_from_tt(((e >> 29) & 0x1FFFFF) - 0x100000, ply)
			if e_flag == TT_EXACT:
				return e_score
			if e_flag == TT_LOWER and e_score >= beta:
				return e_score
			if e_flag == TT_UPPER and e_score <= alpha:
				return e_score

	var pv_node := beta - alpha > 1
	# Null move pruning (skipped in pawn endings to avoid zugzwang errors).
	if allow_null and not in_check and not pv_node and depth >= 3 and _has_pieces(pos.side):
		if ChessEvaluator.evaluate(pos) >= beta:
			pos.make_null_move()
			var null_score := -_negamax(depth - 3, -beta, -beta + 1, ply + 1, false)
			pos.unmake_null_move()
			if _stopped:
				return 0
			if null_score >= beta:
				return beta

	var ordered := _order_moves(pos.generate_pseudo_moves(), tt_move, ply)
	var best_score := -INF
	var best_move := Chess.NO_MOVE
	var original_alpha := alpha
	var legal := 0
	var i := ordered.size() - 1
	while i >= 0:
		var move := int(ordered[i] & 0xFFFFFFFF)
		i -= 1
		if not pos.make_move(move):
			continue
		legal += 1
		var quiet := not Chess.is_capture(move) and Chess.move_promo(move) == 0
		var score: int
		if legal == 1:
			score = -_negamax(depth - 1, -beta, -alpha, ply + 1, true)
		else:
			var reduction := 0
			if quiet and depth >= 3 and legal > 4 and not in_check and not pos.is_in_check():
				reduction = 1 if legal < 10 else 2
			score = -_negamax(depth - 1 - reduction, -alpha - 1, -alpha, ply + 1, true)
			if score > alpha and (reduction > 0 or score < beta):
				score = -_negamax(depth - 1, -beta, -alpha, ply + 1, true)
		pos.unmake_move()
		if _stopped:
			return 0
		if score > best_score:
			best_score = score
			best_move = move
			if score > alpha:
				alpha = score
				if score >= beta:
					if quiet:
						if _killers[ply * 2] != move:
							_killers[ply * 2 + 1] = _killers[ply * 2]
							_killers[ply * 2] = move
						var hidx := (move & 63) * 64 + ((move >> 6) & 63)
						_history[hidx] = mini(_history[hidx] + depth * depth, 400_000)
					break
	if legal == 0:
		return -MATE + ply if in_check else 0

	var flag := TT_EXACT
	if best_score <= original_alpha:
		flag = TT_UPPER
	elif best_score >= beta:
		flag = TT_LOWER
	var stored := clampi(_score_to_tt(best_score, ply), -0xFFFFF, 0xFFFFF) + 0x100000
	_tt[key] = (best_move & 0xFFFFF) | (mini(depth, 127) << 20) | (flag << 27) | (stored << 29)
	return best_score


func _quiesce(alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if _time_up():
		return 0
	var pos := _pos
	var stand_pat := ChessEvaluator.evaluate(pos)
	if stand_pat >= beta or ply >= MAX_PLY - 1:
		return stand_pat
	if stand_pat > alpha:
		alpha = stand_pat
	var ordered := _order_moves(pos.generate_pseudo_moves(true), Chess.NO_MOVE, ply)
	var i := ordered.size() - 1
	while i >= 0:
		var move := int(ordered[i] & 0xFFFFFFFF)
		i -= 1
		# Delta pruning: even winning the captured piece cannot raise alpha.
		var victim := pos.squares[(move >> 6) & 63] & 7
		if Chess.move_promo(move) == 0 and stand_pat + Chess.PIECE_VALUES[victim] + 200 < alpha:
			continue
		if not pos.make_move(move):
			continue
		var score := -_quiesce(-beta, -alpha, ply + 1)
		pos.unmake_move()
		if _stopped:
			return 0
		if score >= beta:
			return score
		if score > alpha:
			alpha = score
	return alpha


## Returns moves packed with their ordering score in the high bits, sorted
## ascending (iterate from the end for best-first).
func _order_moves(moves: PackedInt32Array, tt_move: int, ply: int) -> PackedInt64Array:
	var keyed := PackedInt64Array()
	keyed.resize(moves.size())
	var sq_list := _pos.squares
	var k1 := _killers[ply * 2] if ply < MAX_PLY else 0
	var k2 := _killers[ply * 2 + 1] if ply < MAX_PLY else 0
	for i in moves.size():
		var move := moves[i]
		var score: int
		if move == tt_move:
			score = ORDER_TT
		elif Chess.is_capture(move):
			var victim := sq_list[(move >> 6) & 63] & 7
			if victim == 0:
				victim = Chess.PAWN  # en passant
			var attacker := sq_list[move & 63] & 7
			score = ORDER_CAPTURE + victim * 100 - attacker
		elif Chess.move_promo(move) != 0:
			score = ORDER_PROMO + Chess.move_promo(move)
		elif move == k1:
			score = ORDER_KILLER1
		elif move == k2:
			score = ORDER_KILLER2
		else:
			score = _history[(move & 63) * 64 + ((move >> 6) & 63)]
		keyed[i] = (score << 32) | move
	keyed.sort()
	return keyed


func _has_pieces(color: int) -> bool:
	for sq in 64:
		var piece := _pos.squares[sq]
		if piece != 0 and (piece >> 3) == color:
			var t := piece & 7
			if t != Chess.PAWN and t != Chess.KING:
				return true
	return false


func _tt_move(key: int) -> int:
	var entry: Variant = _tt.get(key)
	if entry == null:
		return Chess.NO_MOVE
	return int(entry) & 0xFFFFF


func _score_to_tt(score: int, ply: int) -> int:
	if score >= MATE_THRESHOLD:
		return score + ply
	if score <= -MATE_THRESHOLD:
		return score - ply
	return score


func _score_from_tt(score: int, ply: int) -> int:
	if score >= MATE_THRESHOLD:
		return score - ply
	if score <= -MATE_THRESHOLD:
		return score + ply
	return score


func _principal_variation(first: int) -> String:
	var line := PackedStringArray()
	var made := 0
	var move := first
	while move != Chess.NO_MOVE and made < 12:
		if not move in _pos.generate_legal_moves():
			break
		line.append(Chess.move_to_uci(move))
		_pos.make_move(move)
		made += 1
		move = _tt_move(_pos.hash)
	for _i in made:
		_pos.unmake_move()
	return " ".join(line)

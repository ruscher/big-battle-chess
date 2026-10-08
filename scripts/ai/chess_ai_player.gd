class_name ChessAIPlayer
extends Node
## Computer opponent. Searches on a worker thread so the game (and any
## cinematic) keeps running while it thinks. Results from cancelled or stale
## requests are discarded by request id.

signal move_ready(move: int, info: Dictionary)

enum Level { BEGINNER, CASUAL, INTERMEDIATE, ADVANCED, EXPERT, GRANDMASTER }

## Weaker levels score all root moves and choose among the near-best with
## noise ("noise" in centipawns), occasionally playing a plausible but weaker
## move ("slip"). This is a documented, deliberate handicap, not fake
## intelligence: the strong levels play the pure search result.
const LEVELS := {
	Level.BEGINNER: {"name": "AI_BEGINNER", "depth": 1, "quiescence": false, "noise": 260, "slip": 0.30, "time_ms": 300, "min_think_ms": 600},
	Level.CASUAL: {"name": "AI_CASUAL", "depth": 2, "quiescence": true, "noise": 90, "slip": 0.10, "time_ms": 600, "min_think_ms": 700},
	Level.INTERMEDIATE: {"name": "AI_INTERMEDIATE", "depth": 4, "quiescence": true, "noise": 0, "slip": 0.0, "time_ms": 1200, "min_think_ms": 600},
	Level.ADVANCED: {"name": "AI_ADVANCED", "depth": 6, "quiescence": true, "noise": 0, "slip": 0.0, "time_ms": 2500, "min_think_ms": 400},
	Level.EXPERT: {"name": "AI_EXPERT", "depth": 64, "quiescence": true, "noise": 0, "slip": 0.0, "time_ms": 5000, "min_think_ms": 300},
	Level.GRANDMASTER: {"name": "AI_GRANDMASTER", "depth": 64, "quiescence": true, "noise": 0, "slip": 0.0, "time_ms": 6000, "min_think_ms": 300, "uci": true},
}

var level: Level = Level.INTERMEDIATE
var uci_path: String = ""
var is_thinking: bool = false

var _thread: Thread
var _search: ChessSearch
var _uci: UciEngine
var _request_id: int = 0
var _started_ms: int = 0


static func level_name_key(l: Level) -> String:
	return LEVELS[l]["name"]


static func grandmaster_available(custom_path: String = "") -> bool:
	return not UciEngine.find_executable(custom_path).is_empty()


func request_move(position: ChessPosition) -> void:
	cancel()
	_request_id += 1
	var config: Dictionary = LEVELS[level].duplicate()
	if config.get("uci", false) and not grandmaster_available(uci_path):
		config["uci"] = false  # fall back to the built-in engine at max strength
		config["time_ms"] = 8000
	_search = ChessSearch.new()
	_started_ms = Time.get_ticks_msec()
	is_thinking = true
	_thread = Thread.new()
	_thread.start(_think.bind(position.clone(), _request_id, config, _thread, _search), Thread.PRIORITY_LOW)


func cancel() -> void:
	_request_id += 1
	is_thinking = false
	if _search != null:
		_search.stop()
	if _uci != null:
		_uci.close()
		_uci = null
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _exit_tree() -> void:
	cancel()


func _think(pos: ChessPosition, id: int, config: Dictionary, thread: Thread, search: ChessSearch) -> void:
	var result := {}
	if config.get("uci", false):
		result = _think_uci(pos, config)
	if result.is_empty():
		if int(config["noise"]) > 0:
			result = _think_handicapped(pos, config, search)
		else:
			result = search.search(pos, {
				"max_depth": config["depth"],
				"time_ms": config["time_ms"],
				"quiescence": config["quiescence"],
			})
	_deliver.call_deferred(id, result, thread)


func _think_uci(pos: ChessPosition, config: Dictionary) -> Dictionary:
	var engine := UciEngine.new()
	_uci = engine
	if not engine.start(UciEngine.find_executable(uci_path)):
		return {}
	var uci := engine.best_move(pos.get_fen(), int(config["time_ms"]))
	engine.close()
	if uci.length() < 4:
		return {}
	var promo := Chess.PIECE_CHARS.find(uci[4].to_upper()) if uci.length() > 4 else 0
	var move := pos.find_legal_move(Chess.parse_square(uci.substr(0, 2)), Chess.parse_square(uci.substr(2, 2)), promo)
	if move == Chess.NO_MOVE:
		return {}
	return {"move": move, "score": 0, "depth": 0, "nodes": 0, "pv": uci, "engine": "uci"}


func _think_handicapped(pos: ChessPosition, config: Dictionary, search: ChessSearch) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var scored: Array = search.score_root_moves(pos, int(config["depth"]), bool(config["quiescence"]))
	if scored.is_empty():
		return {"move": Chess.NO_MOVE}
	var noise := int(config["noise"])
	var best_score := -ChessSearch.INF
	for entry in scored:
		entry.append(int(entry[1]) + rng.randi_range(-noise, noise))
		best_score = maxi(best_score, int(entry[1]))
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	var choice: Array = scored[0]
	# Never "slip" past a mate-in-one or into hanging a mate: keep forced mates.
	if best_score < ChessSearch.MATE_THRESHOLD and rng.randf() < float(config["slip"]) and scored.size() > 2:
		choice = scored[rng.randi_range(1, mini(4, scored.size() - 1))]
	return {"move": choice[0], "score": choice[1], "depth": config["depth"], "nodes": search.nodes, "pv": Chess.move_to_uci(choice[0])}


func _deliver(id: int, result: Dictionary, thread: Thread) -> void:
	if thread.is_started():
		thread.wait_to_finish()
	if thread == _thread:
		_thread = null
	if id != _request_id:
		return
	var min_think := int(LEVELS[level]["min_think_ms"])
	var elapsed := Time.get_ticks_msec() - _started_ms
	if elapsed < min_think and is_inside_tree():
		await get_tree().create_timer((min_think - elapsed) / 1000.0).timeout
		if id != _request_id:
			return
	is_thinking = false
	move_ready.emit(int(result.get("move", Chess.NO_MOVE)), result)

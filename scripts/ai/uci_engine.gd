class_name UciEngine
extends RefCounted
## Minimal UCI client for an optional external engine (e.g. Stockfish, GPLv3).
##
## The engine is never bundled: it is only used when the player has it
## installed and it is found on disk, so the game's license is unaffected.
## All calls block and must run on a worker thread.

const CANDIDATES := [
	"/usr/bin/stockfish",
	"/usr/local/bin/stockfish",
	"/usr/games/stockfish",
	"/opt/homebrew/bin/stockfish",
]

var _pipe: FileAccess
var _pid: int = -1


static func find_executable(custom_path: String = "") -> String:
	var paths: Array = []
	if not custom_path.is_empty():
		paths.append(custom_path)
	paths.append_array(CANDIDATES)
	var exe_dir := OS.get_executable_path().get_base_dir()
	paths.append(exe_dir.path_join("stockfish"))
	paths.append(exe_dir.path_join("stockfish.exe"))
	for p: String in paths:
		if FileAccess.file_exists(p):
			return p
	return ""


func start(path: String) -> bool:
	var info := OS.execute_with_pipe(path, [], true)
	if info.is_empty():
		return false
	_pipe = info["stdio"]
	_pid = int(info["pid"])
	_send("uci")
	if _read_until("uciok").is_empty():
		close()
		return false
	_send("isready")
	return not _read_until("readyok").is_empty()


## Returns the best move in UCI notation, or "" on failure.
func best_move(fen: String, movetime_ms: int) -> String:
	if _pipe == null:
		return ""
	_send("position fen " + fen)
	_send("go movetime %d" % movetime_ms)
	var line := _read_until("bestmove")
	var parts := line.split(" ", false)
	return parts[1] if parts.size() >= 2 else ""


## Kills the process; unblocks a thread waiting on the pipe.
func close() -> void:
	if _pipe != null:
		_send("quit")
		_pipe = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


func _send(command: String) -> void:
	if _pipe != null:
		_pipe.store_string(command + "\n")
		_pipe.flush()


func _read_until(prefix: String) -> String:
	var guard := 0
	while _pipe != null and guard < 100_000:
		guard += 1
		var line := _pipe.get_line().strip_edges()
		if line.begins_with(prefix):
			return line
		if _pipe.get_error() != OK and line.is_empty():
			return ""
	return ""

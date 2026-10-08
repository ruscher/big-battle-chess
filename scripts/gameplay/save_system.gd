class_name SaveSystem
extends RefCounted
## JSON save files in user://saves. A save stores the configuration, the
## move list (replayed and re-validated on load), the clock and metadata.
## Finished games are archived in user://history as PGN for the history list.

const SAVE_DIR := "user://saves"
const HISTORY_DIR := "user://history"
const AUTOSAVE := "autosave"
const VERSION := 1


static func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


static func save_game(slot: String, config: GameConfig, match_data: ChessMatch, clock: ChessClock) -> bool:
	_ensure_dir(SAVE_DIR)
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"config": config.to_dict(),
		"match": match_data.to_dict(),
		"clock": clock.to_dict(),
		"summary": "%d %s" % [match_data.records.size(), "ply"],
	}
	var path := SAVE_DIR.path_join(slot + ".json")
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	# Write-then-rename so a crash never leaves a truncated save behind.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


## Returns {} when the slot is missing or invalid.
static func load_game(slot: String) -> Dictionary:
	var path := SAVE_DIR.path_join(slot + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("SaveSystem: corrupt save " + path)
		return {}
	var data: Dictionary = parsed
	var m := ChessMatch.from_dict(data.get("match", {}))
	if m == null:
		push_warning("SaveSystem: save contains illegal moves: " + path)
		return {}
	var clock := ChessClock.new()
	clock.from_dict(data.get("clock", {}))
	return {
		"config": GameConfig.from_dict(data.get("config", {})),
		"match": m,
		"clock": clock,
		"saved_at": str(data.get("saved_at", "")),
	}


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(SAVE_DIR.path_join(slot + ".json"))


static func delete_save(slot: String) -> void:
	var path := SAVE_DIR.path_join(slot + ".json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Lists manual save slots, newest first: [{slot, saved_at}].
static func list_saves() -> Array:
	_ensure_dir(SAVE_DIR)
	var result := []
	for file in DirAccess.get_files_at(SAVE_DIR):
		if not file.ends_with(".json"):
			continue
		var slot := file.get_basename()
		var text := FileAccess.get_file_as_string(SAVE_DIR.path_join(file))
		var parsed: Variant = JSON.parse_string(text)
		var saved_at := ""
		if parsed is Dictionary:
			saved_at = str(parsed.get("saved_at", ""))
		result.append({"slot": slot, "saved_at": saved_at})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["saved_at"] > b["saved_at"])
	return result


static func archive_finished(match_data: ChessMatch) -> String:
	_ensure_dir(HISTORY_DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var path := HISTORY_DIR.path_join("game_%s.pgn" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(match_data.to_pgn())
	return path


## [{path, white, black, result, date, moves}] newest first.
static func list_history() -> Array:
	_ensure_dir(HISTORY_DIR)
	var result := []
	var files := DirAccess.get_files_at(HISTORY_DIR)
	files.sort()
	files.reverse()
	for file in files:
		if not file.ends_with(".pgn"):
			continue
		var path := HISTORY_DIR.path_join(file)
		var parsed := ChessNotation.parse_pgn(FileAccess.get_file_as_string(path))
		var tags: Dictionary = parsed["tags"]
		result.append({
			"path": path,
			"white": tags.get("White", "?"), "black": tags.get("Black", "?"),
			"result": tags.get("Result", "*"), "date": tags.get("Date", ""),
			"moves": (parsed["moves"] as PackedStringArray).size(),
		})
	return result

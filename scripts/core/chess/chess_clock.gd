class_name ChessClock
extends RefCounted
## Two-sided chess clock with Fischer increment. Time is advanced explicitly
## by the owner (`tick`), which lets the game session pause it during
## cinematics, menus and loading so presentation never costs a player time.

signal flagged(color: int)

var enabled: bool = false
var initial_ms: int = 600_000
var increment_ms: int = 0
var remaining_ms := PackedInt64Array([600_000, 600_000])
var active_color: int = Chess.WHITE
var running: bool = false
var _flagged: bool = false


func configure(minutes: float, increment_seconds: float) -> void:
	enabled = minutes > 0.0
	initial_ms = int(minutes * 60_000.0)
	increment_ms = int(increment_seconds * 1000.0)
	remaining_ms = PackedInt64Array([initial_ms, initial_ms])
	active_color = Chess.WHITE
	running = false
	_flagged = false


func tick(delta: float) -> void:
	if not enabled or not running or _flagged:
		return
	remaining_ms[active_color] -= int(delta * 1000.0)
	if remaining_ms[active_color] <= 0:
		remaining_ms[active_color] = 0
		_flagged = true
		running = false
		flagged.emit(active_color)


## Called after `color` completed a move.
func on_move(color: int) -> void:
	if not enabled:
		return
	remaining_ms[color] += increment_ms
	active_color = color ^ 1


## Restores the turn indicator, e.g. after undo.
func set_active(color: int) -> void:
	active_color = color


func is_flagged() -> bool:
	return _flagged


static func format_ms(ms: int) -> String:
	var total := maxi(0, ms)
	var minutes := total / 60_000
	var seconds := (total / 1000) % 60
	if total < 10_000:
		return "%d:%02d.%d" % [minutes, seconds, (total / 100) % 10]
	return "%d:%02d" % [minutes, seconds]


func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"initial_ms": initial_ms,
		"increment_ms": increment_ms,
		"remaining": [remaining_ms[0], remaining_ms[1]],
		"active": active_color,
	}


func from_dict(data: Dictionary) -> void:
	enabled = bool(data.get("enabled", false))
	initial_ms = int(data.get("initial_ms", 600_000))
	increment_ms = int(data.get("increment_ms", 0))
	var r: Array = data.get("remaining", [initial_ms, initial_ms])
	remaining_ms = PackedInt64Array([int(r[0]), int(r[1])])
	active_color = int(data.get("active", Chess.WHITE))
	running = false
	_flagged = false

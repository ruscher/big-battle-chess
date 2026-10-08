class_name CombatTimeline
extends RefCounted
## Ordered list of timed cues produced by CombatChoreographer and executed by
## BattleDirector. Plain data: easy to inspect, test, skip and fast-forward.
##
## Cue = {"t": seconds, "op": String, ...op parameters}. Fight space: +X goes
## from the attacker's starting spot toward the defender, Y is up.

var cues: Array[Dictionary] = []
var duration: float = 0.0
## attacker/defender types and colors, title keys, finisher key, mode...
var meta: Dictionary = {}


func add(t: float, op: String, params: Dictionary = {}) -> void:
	var cue := params.duplicate()
	cue["t"] = maxf(0.0, t)
	cue["op"] = op
	cues.append(cue)
	duration = maxf(duration, cue["t"])


func finalize() -> void:
	# Stable sort keeps authoring order for cues sharing a timestamp.
	var indexed := []
	for i in cues.size():
		indexed.append([cues[i]["t"], i, cues[i]])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	cues.clear()
	for entry in indexed:
		cues.append(entry[2])
	if cues.is_empty() or cues[-1]["op"] != "end":
		add(duration, "end")


func count_op(op: String) -> int:
	var n := 0
	for c in cues:
		if c["op"] == op:
			n += 1
	return n


func cues_with(op: String, key: String, value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in cues:
		if c["op"] == op and c.get(key) == value:
			result.append(c)
	return result

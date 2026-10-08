extends TestSuite
## Battle choreography invariants for every attacker/defender pair and mode:
## the attacker always wins, the defender always falls, durations respect
## the selected cinematic mode and identical seeds produce identical battles.

const TYPES := [Chess.PAWN, Chess.KNIGHT, Chess.BISHOP, Chess.ROOK, Chess.QUEEN, Chess.KING]
const ARENA_MODES := [CinematicMode.Mode.EPIC, CinematicMode.Mode.DYNAMIC, CinematicMode.Mode.QUICK]


func _request(a: int, d: int, mode: int, seed: int) -> Dictionary:
	return {"attacker_type": a, "attacker_color": Chess.WHITE, "defender_type": d,
		"defender_color": Chess.BLACK, "mode": mode, "seed": seed}


func test_every_matchup_ends_with_attacker_victory() -> void:
	for mode in ARENA_MODES:
		for a in TYPES:
			for d in TYPES:
				if d == Chess.KING:
					continue  # kings are never captured
				for seed in [1, 77, 4242]:
					var tl := CombatChoreographer.build(_request(a, d, mode, seed))
					var label := "%s x %s mode %d seed %d" % [Chess.type_name(a), Chess.type_name(d), mode, seed]
					check(tl.cues_with("anim", "clip", "death").all(func(c: Dictionary) -> bool: return c["who"] == "d"),
						label + ": only the defender dies")
					check_eq(tl.cues_with("anim", "clip", "death").size(), 1, label + ": defender dies once")
					var victory := tl.cues_with("anim", "clip", "victory")
					check(victory.size() == 1 and victory[0]["who"] == "a", label + ": attacker celebrates")
					check_eq(tl.cues_with("fade", "who", "d").size(), 1, label + ": defender fades out")
					check(tl.cues_with("fade", "who", "a").is_empty(), label + ": attacker never fades")
					check_eq(tl.cues[-1]["op"], "end", label + ": ends with end cue")
					var death_t: float = tl.cues_with("anim", "clip", "death")[0]["t"]
					check(victory[0]["t"] > death_t, label + ": victory after the fall")


func test_durations_match_modes() -> void:
	var ranges := {
		CinematicMode.Mode.EPIC: Vector2(26.0, 58.0),
		CinematicMode.Mode.DYNAMIC: Vector2(8.0, 24.0),
		CinematicMode.Mode.QUICK: Vector2(2.5, 8.0),
	}
	var stats := {}
	for mode in ARENA_MODES:
		var lo := 1e9
		var hi := 0.0
		for a in TYPES:
			for d in [Chess.PAWN, Chess.KNIGHT, Chess.BISHOP, Chess.ROOK, Chess.QUEEN]:
				for seed in [3, 99]:
					var tl := CombatChoreographer.build(_request(a, d, mode, seed))
					var r: Vector2 = ranges[mode]
					check(tl.duration >= r.x and tl.duration <= r.y,
						"mode %d %s x %s: %.1f s outside %s" % [mode, Chess.type_name(a), Chess.type_name(d), tl.duration, r])
					lo = minf(lo, tl.duration)
					hi = maxf(hi, tl.duration)
		stats[mode] = "%.1f-%.1f s" % [lo, hi]
	print("      battle lengths: epic %s, dynamic %s, quick %s" % [stats[0], stats[1], stats[2]])


func test_deterministic_for_same_seed() -> void:
	var a := CombatChoreographer.build(_request(Chess.KNIGHT, Chess.BISHOP, CinematicMode.Mode.EPIC, 123))
	var b := CombatChoreographer.build(_request(Chess.KNIGHT, Chess.BISHOP, CinematicMode.Mode.EPIC, 123))
	check_eq(JSON.stringify(a.cues), JSON.stringify(b.cues), "same seed, same battle")
	var c := CombatChoreographer.build(_request(Chess.KNIGHT, Chess.BISHOP, CinematicMode.Mode.EPIC, 124))
	check(JSON.stringify(a.cues) != JSON.stringify(c.cues), "different seed, different battle")


func test_matchups_differ() -> void:
	var p_r := CombatChoreographer.build(_request(Chess.PAWN, Chess.ROOK, CinematicMode.Mode.DYNAMIC, 5))
	var b_n := CombatChoreographer.build(_request(Chess.BISHOP, Chess.KNIGHT, CinematicMode.Mode.DYNAMIC, 5))
	check(p_r.count_op("projectile") == 0, "infantry vs heavy uses no spells")
	check(b_n.count_op("projectile") + b_n.cues_with("vfx", "kind", "pillar").size() > 0, "mystic uses magic")
	check_eq(p_r.meta["title"], "TITLE_GIANT_SLAYER", "special matchup title")
	var legendary := CombatChoreographer.build(_request(Chess.PAWN, Chess.QUEEN, CinematicMode.Mode.EPIC, 5))
	check_eq(legendary.meta["title"], "TITLE_LEGENDARY_CAPTURE", "legendary capture")
	check(legendary.meta["underdog"], "pawn vs queen is an underdog fight")


func test_cues_are_sorted_and_known() -> void:
	var known := ["anim", "move", "place", "face", "spin", "camera", "vfx", "sfx", "shake", "timescale",
		"flash", "light", "title", "music", "fade", "horse", "projectile", "end"]
	for mode in ARENA_MODES:
		var tl := CombatChoreographer.build(_request(Chess.QUEEN, Chess.ROOK, mode, 8))
		var last := -1.0
		for cue in tl.cues:
			check(cue["op"] in known, "unknown op " + str(cue["op"]))
			check(float(cue["t"]) >= last, "cues sorted")
			last = cue["t"]

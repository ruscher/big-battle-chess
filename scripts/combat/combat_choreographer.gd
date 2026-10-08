class_name CombatChoreographer
extends RefCounted
## Builds a CombatTimeline for one capture.
##
## Inputs come only from the already-validated chess move: attacker and
## defender classes/colours, special flags and a deterministic seed. The
## attacker ALWAYS wins: defender attacks can be dodged or blocked, but the
## sequence always ends with the attacker's finisher and the defender's fall.
##
## Battles are assembled from reusable beats (exchanges, dashes, leaps, blade
## locks, spell volleys, charges...) chosen by the two combat profiles, so a
## pawn vs rook plays very differently from a bishop vs knight.

const MELEE_RANGE := 1.75
const MIN_GAP := 1.15

const MELEE_SHOTS := ["ots_a", "ots_d", "side", "low_a", "orbit_close", "dutch", "low_d", "high"]

var tl := CombatTimeline.new()
var rng := RandomNumberGenerator.new()
var t: float = 0.0
var x := {"a": -3.6, "d": 3.6}
var speed := {"a": 1.0, "d": 1.0}
var prof := {"a": {}, "d": {}}
var types := {"a": Chess.PAWN, "d": Chess.PAWN}
var colors := {"a": Chess.WHITE, "d": Chess.BLACK}
var mode: int = CinematicMode.Mode.DYNAMIC
var underdog: bool = false
var _last_shot: String = ""


## request keys: attacker_type, attacker_color, defender_type, defender_color,
## mode (CinematicMode.Mode), seed (int), en_passant (bool), promotion (int).
static func build(request: Dictionary) -> CombatTimeline:
	var c := CombatChoreographer.new()
	c._setup(request)
	c._compose(request)
	c.tl.finalize()
	return c.tl


func _setup(r: Dictionary) -> void:
	rng.seed = int(r.get("seed", 1))
	mode = int(r.get("mode", CinematicMode.Mode.DYNAMIC))
	types = {"a": int(r["attacker_type"]), "d": int(r["defender_type"])}
	colors = {"a": int(r["attacker_color"]), "d": int(r["defender_color"])}
	prof = {"a": CombatProfile.get_profile(types["a"]), "d": CombatProfile.get_profile(types["d"])}
	speed = {"a": float(prof["a"]["speed"]), "d": float(prof["d"]["speed"])}
	underdog = int(prof["d"]["hp_flavor"]) - int(prof["a"]["hp_flavor"]) >= 4
	tl.meta = {
		"attacker_type": types["a"], "attacker_color": colors["a"],
		"defender_type": types["d"], "defender_color": colors["d"],
		"mode": mode,
		"title": CombatProfile.matchup_title(types["a"], types["d"]),
		"finisher_key": CombatProfile.finisher_key(types["a"], colors["a"]),
		"underdog": underdog,
	}
	if r.get("en_passant", false):
		tl.meta["title"] = "TITLE_EN_PASSANT"


func _compose(r: Dictionary) -> void:
	var range_s: Vector2 = CinematicMode.DURATION.get(mode, Vector2(10, 20))
	var target_total := rng.randf_range(range_s.x, range_s.y)
	match mode:
		CinematicMode.Mode.EPIC:
			_intro(true)
			_faceoff()
			_approach()
			# Leave ~15 s for climax, defeat, victory and return.
			_middle(target_total - 15.0)
			_power_up(2.8)
			_finisher(true)
			_defeat(2.6)
			_victory(3.4)
		CinematicMode.Mode.DYNAMIC:
			_intro(false)
			_approach()
			_middle(target_total - 8.0)
			_power_up(1.4)
			_finisher(false)
			_defeat(1.8)
			_victory(2.0)
		_:
			_quick_intro()
			_finisher(false)
			_defeat(1.1)
			_victory(0.9)
	_cue(t + 0.2, "end")


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

func _cue(time: float, op: String, params: Dictionary = {}) -> void:
	tl.add(time, op, params)


func _other(who: String) -> String:
	return "d" if who == "a" else "a"


func _dir(who: String) -> float:
	## +1 when `who` must move toward +X to reach the opponent.
	return 1.0 if x[_other(who)] > x[who] else -1.0


func _anim(who: String, clip: String, time: float, blend: float = 0.1, spd: float = -1.0) -> void:
	_cue(time, "anim", {"who": who, "clip": clip, "blend": blend, "speed": speed[who] if spd < 0.0 else spd})


func _move(who: String, to_x: float, time: float, dur: float, arc: float = 0.0, ease: String = "inout") -> void:
	# Never let fighters pass through each other unless explicitly dashing.
	_cue(time, "move", {"who": who, "to": to_x, "dur": maxf(dur, 0.01), "arc": arc, "ease": ease})
	x[who] = to_x


func _shot(time: float, shot: String, blend: float = 0.0, params: Dictionary = {}) -> void:
	var p := params.duplicate()
	p["shot"] = shot
	p["blend"] = blend
	_cue(time, "camera", p)
	_last_shot = shot


func _pick_shot(options: Array) -> String:
	var choices := options.filter(func(s: String) -> bool: return s != _last_shot)
	return choices[rng.randi_range(0, choices.size() - 1)]


func _impact(time: float, kind: String, at: String, who: String, strength: float) -> void:
	_cue(time, "vfx", {"kind": kind, "at": at, "who": who, "scale": strength})
	_cue(time, "shake", {"amp": 0.08 + 0.25 * strength, "dur": 0.18 + 0.2 * strength})
	if strength >= 0.6:
		_cue(time, "flash", {"strength": 0.25 * strength})
	# Hit-stop: a few frames of near-freeze sell the weight of contact.
	_cue(time, "timescale", {"value": 0.06, "dur": 0.045 + 0.05 * strength})


func _speed_mult() -> float:
	return 1.0 if mode == CinematicMode.Mode.EPIC else 1.15


# --------------------------------------------------------------------------
# Opening
# --------------------------------------------------------------------------

func _intro(epic: bool) -> void:
	_anim("a", "idle", t, 0.0)
	_anim("d", "idle", t, 0.0)
	_cue(t, "music", {"cue": "battle"})
	_cue(t, "sfx", {"name": "wind"})
	_cue(t, "light", {"mode": "normal"})
	_shot(t, "establish")
	var title: String = tl.meta["title"]
	if not title.is_empty():
		_cue(t + 0.4, "title", {"key": title, "style": "matchup"})
	if epic:
		_shot(t + 1.6, "closeup_a", 0.0)
		var a_intro := "power_up" if prof["a"]["magic"] else "salute"
		_anim("a", a_intro, t + 1.6)
		if a_intro == "power_up":
			_cue(t + 1.8, "vfx", {"kind": "aura_on", "at": "a_chest", "who": "a", "scale": 0.5})
			_cue(t + 3.0, "vfx", {"kind": "aura_off", "at": "a_chest", "who": "a", "scale": 0.5})
		_shot(t + 3.1, "closeup_d", 0.0)
		_anim("d", "guard", t + 3.1, 0.25)
		_cue(t + 3.1, "sfx", {"name": "draw_weapon"})
		_anim("a", "guard", t + 4.2, 0.3)
		_shot(t + 4.2, "wide", 0.6)
		t += 5.0
	else:
		_anim("a", "guard", t + 0.5, 0.25)
		_anim("d", "guard", t + 0.3, 0.25)
		_shot(t + 0.9, "ots_a", 0.5)
		t += 1.6


func _quick_intro() -> void:
	x = {"a": -2.4, "d": 2.4}
	_cue(t, "place", {"who": "a", "x": x["a"]})
	_cue(t, "place", {"who": "d", "x": x["d"]})
	_anim("a", "guard", t, 0.0)
	_anim("d", "guard", t, 0.0)
	_cue(t, "music", {"cue": "battle"})
	_cue(t, "light", {"mode": "normal"})
	_shot(t, "side")
	t += 0.5


func _faceoff() -> void:
	_cue(t, "sfx", {"name": "heartbeat"})
	_cue(t, "timescale", {"value": 0.7, "dur": 2.4})
	_shot(t, "ots_a")
	_shot(t + 1.3, "ots_d")
	_shot(t + 2.5, "low_mid", 0.4)
	t += 3.0


func _approach() -> void:
	var gap := MELEE_RANGE + 0.1
	var mid: float = lerpf(x["a"], x["d"], 0.5 + 0.12 * (float(prof["d"]["mobility"]) - float(prof["a"]["mobility"])))
	var dist := absf(x["d"] - x["a"]) - gap
	var dur := clampf(dist / 6.0, 0.6, 1.3)
	_anim("a", "run", t, 0.15)
	_anim("d", "run", t + 0.15, 0.15)
	_cue(t, "sfx", {"name": "battle_cry", "who": "a"})
	_move("a", mid - gap * 0.5, t, dur, 0.0, "in")
	_move("d", mid + gap * 0.5, t + 0.15, dur - 0.15, 0.0, "in")
	_shot(t, "track_side", 0.0)
	t += dur
	_anim("a", "guard", t - 0.05, 0.12)
	_anim("d", "guard", t - 0.05, 0.12)


# --------------------------------------------------------------------------
# Middle: varied exchanges until the time budget is used
# --------------------------------------------------------------------------

func _middle(until: float) -> void:
	var beats_done := 0
	var last_beat := ""
	while t < until or beats_done < 1:
		var options := ["exchange", "exchange", "counter"]
		for s in prof["a"]["specials"]:
			options.append(s)
		if mode == CinematicMode.Mode.EPIC:
			options.append_array(["lock", "counter"])
		if underdog:
			options.append_array(["counter", "counter"])
		var beat: String = options[rng.randi_range(0, options.size() - 1)]
		if beat == last_beat and beat != "exchange":
			beat = "exchange"
		match beat:
			"exchange": _exchange("a")
			"counter": _counter()
			"dash": _dash_through("a")
			"leap": _leap_strike("a")
			"lock": _blade_lock()
			"volley": _volley("a")
			"charge": _charge("a")
			"slam": _slam("a")
		last_beat = beat
		beats_done += 1
		if beats_done > 24:
			break


func _close_in(who: String) -> void:
	var gap := absf(x["d"] - x["a"])
	if gap <= MELEE_RANGE + 0.15:
		return
	var other := _other(who)
	var target: float = x[other] - _dir(who) * MELEE_RANGE
	var dur := clampf((gap - MELEE_RANGE) / 7.0, 0.25, 0.7)
	_anim(who, "run", t, 0.08)
	_move(who, target, t, dur, 0.0, "in")
	t += dur
	_anim(who, "guard", t - 0.05, 0.08)


func _back_off(who: String, distance: float) -> void:
	var dur := 0.35
	_anim(who, "dodge", t, 0.08)
	_move(who, x[who] - _dir(who) * distance, t, dur, 0.25, "out")
	_cue(t + dur, "vfx", {"kind": "dust", "at": who + "_ground", "who": who, "scale": 0.5})
	t += dur + 0.15


## `striker` attacks; the other fighter defends. If the striker is the
## defender ("d"), the attack never lands.
func _exchange(striker: String, allow_hit: bool = true) -> void:
	var receiver := _other(striker)
	var attack: String = prof[striker]["attacks"][rng.randi_range(0, prof[striker]["attacks"].size() - 1)]
	if attack == "cast":
		_spell(striker)
		return
	_close_in(striker)
	var spd: float = speed[striker] * _speed_mult()
	var start := t
	var length := CombatProfile.clip_length(attack, spd)
	var hits := CombatProfile.clip_events(attack, "hit", spd)
	_anim(striker, attack, start, 0.08, spd)
	_shot(start, _pick_shot(MELEE_SHOTS), 0.0, {"focus": striker})
	var first_hit: float = hits[0] if not hits.is_empty() else length * 0.5
	_move(striker, x[striker] + _dir(striker) * 0.3, start + first_hit * 0.5, first_hit * 0.5, 0.0, "out")
	var defenses: Array = prof[receiver]["defenses"]
	var outcome: String = defenses[rng.randi_range(0, defenses.size() - 1)]
	if striker == "a" and allow_hit and rng.randf() < 0.3:
		outcome = "hit"
	if striker == "d" and outcome == "block" and rng.randf() < 0.4:
		outcome = "parry"
	for i in hits.size():
		var h := start + hits[i]
		_cue(h - 0.08, "sfx", {"name": "whoosh", "who": striker})
		match outcome:
			"block":
				if i == 0:
					_anim(receiver, "block" if hits.size() == 1 else "block_hold", h - 0.14, 0.06)
				_cue(h, "sfx", {"name": "clash_shield" if prof[receiver]["defenses"].has("block") else "clash"})
				_impact(h, "sparks", striker + "_tip", striker, 0.45)
				_move(receiver, x[receiver] + _dir(striker) * 0.18, h, 0.15, 0.0, "out")
			"parry":
				_anim(receiver, "parry", h - 0.11, 0.05)
				_cue(h, "sfx", {"name": "clash"})
				_impact(h, "sparks", striker + "_tip", striker, 0.55)
			"dodge":
				_anim(receiver, "dodge", h - 0.15, 0.05)
				_move(receiver, x[receiver] + _dir(striker) * 0.55, h - 0.15, 0.25, 0.15, "out")
				_cue(h - 0.1, "vfx", {"kind": "afterimage", "at": receiver + "_chest", "who": receiver, "scale": 0.6})
			"hit":
				_anim(receiver, "hit", h, 0.04)
				_cue(h, "sfx", {"name": "impact_flesh", "who": receiver})
				_cue(h + 0.05, "sfx", {"name": "grunt", "who": receiver})
				_impact(h, "impact", receiver + "_chest", striker, 0.7)
				_move(receiver, x[receiver] + _dir(striker) * 0.4, h, 0.2, 0.0, "out")
	if outcome == "block" and hits.size() > 1:
		_anim(receiver, "guard", start + length - 0.1, 0.15)
	t = start + length * 0.92


## The defender strikes back; the attacker avoids it (and may riposte).
func _counter() -> void:
	_exchange("d")
	if rng.randf() < 0.6:
		_exchange("a")


func _spell(caster: String) -> void:
	var target := _other(caster)
	if absf(x[target] - x[caster]) < 3.0:
		_back_off(caster, 2.2)
	var spd: float = speed[caster]
	var start := t
	var release := CombatProfile.clip_event("cast", "release", spd)
	var length := CombatProfile.clip_length("cast", spd)
	_anim(caster, "cast", start, 0.08, spd)
	_shot(start, "ots_" + caster)
	_cue(start + 0.1, "sfx", {"name": "magic_charge", "who": caster})
	_cue(start + 0.1, "vfx", {"kind": "charge", "at": caster + "_hand", "who": caster, "scale": 0.6})
	var travel := 0.42
	var arrive := start + release + travel
	_cue(start + release, "projectile", {"from": caster + "_hand", "to": target + "_chest", "dur": travel, "who": caster})
	_cue(start + release, "sfx", {"name": "magic_cast", "who": caster})
	_shot(start + release, "projectile", 0.0, {"focus": caster})
	var defenses: Array = prof[target]["defenses"]
	var outcome: String = defenses[rng.randi_range(0, defenses.size() - 1)]
	if caster == "a" and rng.randf() < 0.35:
		outcome = "hit"
	match outcome:
		"dodge":
			_anim(target, "dodge", arrive - 0.15, 0.05)
			_move(target, x[target], arrive - 0.15, 0.3, 0.3, "out")
			_cue(arrive - 0.1, "sfx", {"name": "whoosh", "who": target})
			_impact(arrive + 0.1, "magic_burst", target + "_behind", caster, 0.6)
			_cue(arrive + 0.1, "sfx", {"name": "magic_impact"})
		"hit":
			_anim(target, "hit", arrive, 0.04)
			_impact(arrive, "magic_burst", target + "_chest", caster, 0.75)
			_cue(arrive, "sfx", {"name": "magic_impact"})
			_move(target, x[target] - _dir(target) * 0.5, arrive, 0.25, 0.0, "out")
		_:
			_anim(target, "block", arrive - 0.14, 0.05)
			_impact(arrive, "magic_burst", target + "_front", caster, 0.6)
			_cue(arrive, "sfx", {"name": "magic_impact"})
			_move(target, x[target] - _dir(target) * 0.25, arrive, 0.2, 0.0, "out")
	_shot(arrive + 0.05, "wide", 0.3)
	t = maxf(start + length, arrive + 0.35)


func _dash_through(who: String) -> void:
	var other := _other(who)
	var behind: float = x[other] + _dir(who) * 1.6
	var spd: float = speed[who] * 1.35
	var start := t
	_anim(who, "guard", start, 0.1)
	_shot(start, "low_" + who, 0.0)
	_cue(start + 0.25, "sfx", {"name": "dash", "who": who})
	_cue(start + 0.25, "vfx", {"kind": "dash_trail", "at": who + "_chest", "who": who, "scale": 1.0})
	_anim(who, "slash", start + 0.25 - CombatProfile.clip_event("slash", "hit", spd) + 0.08, 0.05, spd)
	_move(who, behind, start + 0.25, 0.14, 0.0, "linear")
	_cue(start + 0.33, "vfx", {"kind": "slash_arc", "at": other + "_chest", "who": who, "scale": 0.8})
	_shot(start + 0.3, "wide", 0.0)
	var outcome_hit := rng.randf() < 0.55
	if outcome_hit:
		_anim(other, "stagger", start + 0.4, 0.05)
		_impact(start + 0.4, "impact", other + "_chest", who, 0.6)
		_cue(start + 0.4, "sfx", {"name": "slash_hit"})
	else:
		_anim(other, "parry", start + 0.28, 0.05)
		_impact(start + 0.33, "sparks", other + "_chest", who, 0.6)
		_cue(start + 0.33, "sfx", {"name": "clash"})
	_cue(start + 0.75, "face", {"who": who, "dur": 0.25})
	_cue(start + 0.85, "face", {"who": other, "dur": 0.3})
	_anim(other, "guard", start + 1.3, 0.2)
	t = start + 1.45


func _leap_strike(who: String) -> void:
	var other := _other(who)
	if absf(x[other] - x[who]) < 3.0:
		_back_off(who, 2.0)
	var start := t
	var spd: float = speed[who]
	_anim(who, "jump", start, 0.08, 1.0)
	_cue(start + 0.18, "sfx", {"name": "jump", "who": who})
	_cue(start + 0.2, "vfx", {"kind": "dust", "at": who + "_ground", "who": who, "scale": 0.8})
	_shot(start, "low_" + who, 0.0)
	var airtime := 0.75
	var land := start + 0.22 + airtime
	_move(who, x[other] - _dir(who) * 1.25, start + 0.22, airtime, 2.6, "linear")
	_cue(start + 0.5, "timescale", {"value": 0.35, "dur": 0.35})
	_shot(start + 0.45, "sky_" + who, 0.25)
	_anim(who, "land_strike", land - 0.1, 0.05, spd)
	_anim(other, "block", land - 0.25, 0.06)
	_cue(land, "sfx", {"name": "slam"})
	_impact(land, "shockwave", who + "_ground", who, 0.9)
	_cue(land, "vfx", {"kind": "sparks", "at": who + "_tip", "who": who, "scale": 0.8})
	_move(other, x[other] + _dir(who) * 0.45, land, 0.25, 0.0, "out")
	_shot(land, "side", 0.0)
	t = land + 0.75


func _blade_lock() -> void:
	_close_in("a")
	var start := t
	var mid: float = (x["a"] + x["d"]) * 0.5
	var side := _dir("a")
	_move("a", mid - side * 0.6, start, 0.15, 0.0, "in")
	_move("d", mid + side * 0.6, start, 0.15, 0.0, "in")
	_anim("a", "parry", start, 0.08)
	_anim("d", "parry", start, 0.08)
	_cue(start + 0.12, "sfx", {"name": "clash"})
	_impact(start + 0.15, "sparks", "mid", "a", 0.7)
	_shot(start + 0.15, "lock", 0.0)
	_cue(start + 0.3, "sfx", {"name": "blade_grind"})
	for i in 3:
		_cue(start + 0.45 + i * 0.35, "vfx", {"kind": "sparks", "at": "mid", "who": "a" if i % 2 == 0 else "d", "scale": 0.4})
	_cue(start + 0.3, "timescale", {"value": 0.6, "dur": 1.0})
	var push := start + 1.55
	_cue(push, "sfx", {"name": "clash"})
	_impact(push, "shockwave", "mid_ground", "a", 0.5)
	_anim("a", "guard", push, 0.1)
	_anim("d", "hit", push, 0.05)
	_move("a", x["a"] - _dir("a") * 1.2, push, 0.35, 0.0, "out")
	_move("d", x["d"] - _dir("d") * 1.8, push, 0.45, 0.0, "out")
	_cue(push + 0.1, "vfx", {"kind": "dust", "at": "d_ground", "who": "d", "scale": 0.6})
	_shot(push, "wide", 0.0)
	t = push + 0.6


func _volley(who: String) -> void:
	if not prof[who]["magic"]:
		_exchange(who)
		return
	_spell(who)
	if rng.randf() < 0.5:
		_spell(who)


func _charge(who: String) -> void:
	var other := _other(who)
	if absf(x[other] - x[who]) < 4.0:
		var away: float = x[who] - _dir(who) * 3.0
		_anim(who, "run", t, 0.1)
		_move(who, away, t, 0.6, 0.0, "out")
		_cue(t + 0.6, "face", {"who": who, "dur": 0.3})
		t += 0.95
	var start := t
	_cue(start, "horse", {"who": who, "clip": "rear"})
	_cue(start + 0.35, "sfx", {"name": "horse_neigh", "who": who})
	_shot(start, "low_" + who, 0.0)
	var go := start + 0.9
	_anim(who, "run", go, 0.1)
	var through: float = x[other] + _dir(who) * 1.8
	var dur := 0.8
	_move(who, through, go, dur, 0.0, "in")
	_shot(go, "track_side", 0.0)
	var contact := go + dur * 0.62
	_anim(who, "thrust", contact - CombatProfile.clip_event("thrust", "hit", speed[who]), 0.05)
	_anim(other, "block", contact - 0.14, 0.05)
	_cue(contact, "sfx", {"name": "clash_shield"})
	_impact(contact, "sparks", who + "_tip", who, 0.8)
	_move(other, x[other] + _dir(who) * 0.9, contact, 0.3, 0.2, "out")
	_cue(go + dur, "face", {"who": who, "dur": 0.4})
	_anim(who, "guard", go + dur + 0.1, 0.2)
	t = go + dur + 0.6


func _slam(who: String) -> void:
	var other := _other(who)
	if absf(x[other] - x[who]) < 2.5:
		_back_off(who, 1.5)
	var start := t
	var spd: float = speed[who]
	_anim(who, "overhead", start, 0.08, spd)
	_shot(start, "low_" + who, 0.0)
	var hit := start + CombatProfile.clip_event("overhead", "hit", spd)
	_cue(hit, "sfx", {"name": "slam"})
	_impact(hit, "shockwave", who + "_tip_ground", who, 0.85)
	_anim(other, "jump", hit - 0.1, 0.05)
	_move(other, x[other] + _dir(who) * 0.8, hit + 0.1, 0.55, 1.1, "linear")
	_anim(other, "guard", hit + 0.7, 0.1)
	_shot(hit, "wide", 0.0)
	t = hit + 0.9


# --------------------------------------------------------------------------
# Climax
# --------------------------------------------------------------------------

func _power_up(duration: float) -> void:
	var start := t
	if absf(x["d"] - x["a"]) < 2.4:
		_move("a", x["a"] - _dir("a") * 1.4, start, 0.35, 0.2, "out")
	_anim("a", "power_up", start + 0.2, 0.15)
	_anim("d", "guard", start, 0.2)
	_cue(start + 0.2, "music", {"cue": "climax"})
	_cue(start + 0.25, "light", {"mode": "charge", "who": "a"})
	_cue(start + 0.3, "vfx", {"kind": "aura_on", "at": "a_chest", "who": "a", "scale": 1.0})
	_cue(start + 0.3, "sfx", {"name": "power_up", "who": "a"})
	_shot(start + 0.2, "closeup_a", 0.0)
	_cue(start + 0.6, "title", {"key": tl.meta["finisher_key"], "style": "finisher"})
	_shot(start + duration * 0.55, "hero_a", 0.5)
	_cue(start + duration * 0.55, "shake", {"amp": 0.12, "dur": duration * 0.45})
	t = start + duration


func _finisher(epic: bool) -> void:
	var fin: String = prof["a"]["finisher"]
	var start := t
	var hit: float
	match fin:
		"valor_lunge", "crown_of_storms":
			if fin == "crown_of_storms":
				# Arcane storm first, then the decisive lunge.
				_anim("a", "cast", start, 0.08)
				for i in 3:
					var bolt := start + 0.35 + i * 0.22
					_cue(bolt, "vfx", {"kind": "lightning", "at": "d_chest", "who": "a", "scale": 0.8})
					_cue(bolt, "sfx", {"name": "thunder"})
					_cue(bolt, "flash", {"strength": 0.35})
				_anim("d", "stagger", start + 0.4, 0.05)
				_shot(start, "wide", 0.0)
				start += 1.2
			_cue(start, "sfx", {"name": "dash", "who": "a"})
			_cue(start, "vfx", {"kind": "dash_trail", "at": "a_chest", "who": "a", "scale": 1.4})
			var clip := "thrust"
			var spd: float = speed["a"] * 1.25
			var target_x: float = x["d"] - _dir("a") * 1.35
			_move("a", target_x, start, 0.16, 0.0, "linear")
			_anim("a", clip, start + 0.16 - CombatProfile.clip_event(clip, "hit", spd) + 0.02, 0.04, spd)
			hit = start + 0.18
			_shot(start, "track_side", 0.0)
		"thunder_charge":
			if absf(x["d"] - x["a"]) < 4.5:
				_anim("a", "run", start, 0.1)
				_move("a", x["a"] - _dir("a") * 2.5, start, 0.5, 0.0, "out")
				_cue(start + 0.5, "face", {"who": "a", "dur": 0.3})
				start += 0.85
			_cue(start, "horse", {"who": "a", "clip": "rear"})
			_cue(start + 0.3, "sfx", {"name": "horse_neigh", "who": "a"})
			_cue(start + 0.3, "vfx", {"kind": "lightning", "at": "a_tip", "who": "a", "scale": 0.7})
			_anim("a", "run", start + 0.9, 0.1)
			_move("a", x["d"] - _dir("a") * 1.4, start + 0.9, 0.55, 0.0, "in")
			_shot(start + 0.9, "track_side", 0.0)
			_anim("a", "thrust", start + 1.45 - CombatProfile.clip_event("thrust", "hit", speed["a"]), 0.05)
			hit = start + 1.45
		"sacred_pillar":
			_anim("a", "cast", start, 0.08)
			_cue(start + 0.1, "sfx", {"name": "magic_charge", "who": "a"})
			_shot(start, "low_a", 0.0)
			hit = start + CombatProfile.clip_event("cast", "release", speed["a"]) + 0.35
			_cue(hit - 0.35, "vfx", {"kind": "pillar_warn", "at": "d_ground", "who": "a", "scale": 1.0})
			_shot(hit - 0.3, "sky_d", 0.0)
		"earthshatter":
			if absf(x["d"] - x["a"]) < 3.0:
				_move("a", x["a"] - _dir("a") * 1.6, start, 0.35, 0.3, "out")
				start += 0.4
			_anim("a", "jump", start, 0.08, 1.0)
			_cue(start + 0.2, "vfx", {"kind": "dust", "at": "a_ground", "who": "a", "scale": 1.0})
			_move("a", x["d"] - _dir("a") * 1.3, start + 0.22, 0.85, 3.4, "linear")
			_cue(start + 0.55, "timescale", {"value": 0.3, "dur": 0.4})
			_shot(start + 0.3, "sky_a", 0.3)
			hit = start + 1.07
			_anim("a", "land_strike", hit - 0.1, 0.05, speed["a"])
		_:  # royal_verdict
			if absf(x["d"] - x["a"]) > 2.2:
				_close_in("a")
				start = t
			_cue(start, "spin", {"who": "a", "deg": 360.0, "dur": 0.45})
			_anim("a", "overhead", start + 0.2, 0.06)
			_shot(start, "low_a", 0.0)
			hit = start + 0.2 + CombatProfile.clip_event("overhead", "hit", speed["a"])
	# Defender's last stand: tries to block or counter right before impact.
	_anim("d", "block", hit - 0.3, 0.06)
	_shot(hit - 0.12, "impact", 0.0)
	_cue(hit, "sfx", {"name": "finisher_impact"})
	_cue(hit, "light", {"mode": "finisher", "who": "a"})
	var fx: String = {
		"valor_lunge": "slash_burst", "crown_of_storms": "slash_burst", "thunder_charge": "lightning",
		"sacred_pillar": "pillar", "earthshatter": "shockwave", "royal_verdict": "golden_wave",
	}[fin]
	_cue(hit, "vfx", {"kind": fx, "at": "d_chest" if fx != "shockwave" else "a_tip_ground", "who": "a", "scale": 1.4})
	_impact(hit, "impact", "d_chest", "a", 1.0)
	_cue(hit + 0.05, "timescale", {"value": 0.18, "dur": 0.7 if epic else 0.45})
	_cue(hit, "vfx", {"kind": "aura_off", "at": "a_chest", "who": "a", "scale": 1.0})
	_anim("d", "death", hit + 0.02, 0.03)
	_cue(hit + 0.05, "sfx", {"name": "death_cry", "who": "d"})
	if types["d"] == Chess.KNIGHT:
		_cue(hit + 0.1, "horse", {"who": "d", "clip": "fall"})
	_move("d", x["d"] + _dir("a") * 1.4, hit, 0.6, 0.35, "out")
	_shot(hit + 0.25, "wide_low", 0.35)
	t = hit + 0.9


func _defeat(duration: float) -> void:
	var start := t
	_cue(start + 0.4, "sfx", {"name": "armor_fall"})
	_cue(start + 0.5, "vfx", {"kind": "dust", "at": "d_ground", "who": "d", "scale": 0.9})
	_cue(start + duration * 0.45, "vfx", {"kind": "dissolve", "at": "d_chest", "who": "d", "scale": 1.0})
	_cue(start + duration * 0.45, "fade", {"who": "d", "dur": duration * 0.55})
	_cue(start + 0.2, "light", {"mode": "normal"})
	t = start + duration


func _victory(duration: float) -> void:
	var start := t
	_cue(start, "face", {"who": "a", "dur": 0.3, "toward": "camera"})
	_anim("a", "victory", start + 0.15, 0.2)
	_cue(start + 0.2, "music", {"cue": "victory"})
	_cue(start + 0.5, "sfx", {"name": "victory_cry", "who": "a"})
	_shot(start, "hero_a", 0.0)
	_cue(start + 0.1, "light", {"mode": "victory", "who": "a"})
	t = start + duration

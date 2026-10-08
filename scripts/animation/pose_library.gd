class_name PoseLibrary
extends RefCounted
## Authored poses and clips for the procedural rigs.
##
## Conventions (degrees, joint-local Euler, rig faces +Z):
##   shoulder/thigh x < 0 : limb swings forward      elbow x < 0 : forearm bends forward
##   knee x > 0           : shin bends backward        spine/chest/head x > 0 : lean forward
##   shoulder_l z > 0     : left arm raised sideways   (mirror sign for the right side)
##   y                    : twist toward the rig's left (+X)
##   "<joint>:offset"     : translation from the rest position (metres, rig space)
## Events inside clips: "hit" (contact), "whoosh" (weapon swing), "step",
## "release" (spell/projectile), "impact" (blocked hit), "land", "aura".

static var _humanoid_poses: Dictionary = {}
static var _humanoid_clips: Dictionary = {}
static var _horse_poses: Dictionary = {}
static var _horse_clips: Dictionary = {}


static func humanoid_poses() -> Dictionary:
	if _humanoid_poses.is_empty():
		_humanoid_poses = _build_humanoid_poses()
	return _humanoid_poses


static func humanoid_clips() -> Dictionary:
	if _humanoid_clips.is_empty():
		_humanoid_clips = _build_humanoid_clips()
	return _humanoid_clips


static func horse_poses() -> Dictionary:
	if _horse_poses.is_empty():
		_horse_poses = _build_horse_poses()
	return _horse_poses


static func horse_clips() -> Dictionary:
	if _horse_clips.is_empty():
		_horse_clips = _build_horse_clips()
	return _horse_clips


static func _v(x: float, y: float = 0.0, z: float = 0.0) -> Vector3:
	return Vector3(x, y, z)


## Merges `changes` over `base` (shallow) to derive pose variants.
static func _derive(base: Dictionary, changes: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in changes:
		out[k] = changes[k]
	return out


static func _build_humanoid_poses() -> Dictionary:
	var p := {}
	p["rest"] = {
		"shoulder_l": _v(0, 0, 8), "shoulder_r": _v(0, 0, -8),
		"elbow_l": _v(-10), "elbow_r": _v(-10),
	}
	p["idle"] = {
		"shoulder_r": _v(-12, 0, -10), "elbow_r": _v(-58), "hand_r": _v(0, 0, 0),
		"shoulder_l": _v(-22, 0, 14), "elbow_l": _v(-62),
		"thigh_l": _v(0, 0, 4), "thigh_r": _v(0, 0, -4),
		"head": _v(2),
	}
	p["guard"] = {
		"hips:offset": _v(0, -0.07, 0), "hips": _v(0, -18, 0),
		"spine": _v(8, 6, 0), "chest": _v(2, 10, 0), "head": _v(-4, 4, 0),
		"thigh_l": _v(-28, 0, 8), "knee_l": _v(32), "foot_l": _v(-4),
		"thigh_r": _v(18, 0, -8), "knee_r": _v(26), "foot_r": _v(-8),
		"shoulder_r": _v(-48, 0, -16), "elbow_r": _v(-72), "hand_r": _v(0, 0, 10),
		"shoulder_l": _v(-58, 0, 14), "elbow_l": _v(-82),
	}
	# Locomotion (4-key cycles: contact L, passing, contact R, passing).
	p["walk_l"] = {
		"hips:offset": _v(0, -0.025, 0), "spine": _v(4, 4, 0),
		"thigh_l": _v(-26), "knee_l": _v(6), "foot_l": _v(-6),
		"thigh_r": _v(20), "knee_r": _v(18), "foot_r": _v(10),
		"shoulder_l": _v(14, 0, 12), "elbow_l": _v(-55),
		"shoulder_r": _v(-22, 0, -10), "elbow_r": _v(-60),
	}
	p["walk_pass_a"] = {
		"hips:offset": _v(0, 0.01, 0), "spine": _v(4, 0, 0),
		"thigh_l": _v(-4), "knee_l": _v(6),
		"thigh_r": _v(-10), "knee_r": _v(42), "foot_r": _v(8),
		"shoulder_l": _v(-4, 0, 12), "elbow_l": _v(-58),
		"shoulder_r": _v(-12, 0, -10), "elbow_r": _v(-60),
	}
	p["walk_r"] = {
		"hips:offset": _v(0, -0.025, 0), "spine": _v(4, -4, 0),
		"thigh_r": _v(-26), "knee_r": _v(6), "foot_r": _v(-6),
		"thigh_l": _v(20), "knee_l": _v(18), "foot_l": _v(10),
		"shoulder_l": _v(-26, 0, 12), "elbow_l": _v(-62),
		"shoulder_r": _v(4, 0, -10), "elbow_r": _v(-55),
	}
	p["walk_pass_b"] = {
		"hips:offset": _v(0, 0.01, 0), "spine": _v(4, 0, 0),
		"thigh_r": _v(-4), "knee_r": _v(6),
		"thigh_l": _v(-10), "knee_l": _v(42), "foot_l": _v(8),
		"shoulder_l": _v(-14, 0, 12), "elbow_l": _v(-60),
		"shoulder_r": _v(-8, 0, -10), "elbow_r": _v(-58),
	}
	p["run_l"] = {
		"hips:offset": _v(0, -0.05, 0), "spine": _v(16, 8, 0), "chest": _v(4), "head": _v(-14),
		"thigh_l": _v(-55), "knee_l": _v(25), "foot_l": _v(-10),
		"thigh_r": _v(35), "knee_r": _v(55), "foot_r": _v(20),
		"shoulder_l": _v(38, 0, 14), "elbow_l": _v(-70),
		"shoulder_r": _v(-50, 0, -12), "elbow_r": _v(-80),
	}
	p["run_pass_a"] = {
		"hips:offset": _v(0, 0.04, 0), "spine": _v(16, 0, 0), "head": _v(-14),
		"thigh_l": _v(-12), "knee_l": _v(30),
		"thigh_r": _v(-30), "knee_r": _v(100), "foot_r": _v(20),
		"shoulder_l": _v(0, 0, 14), "elbow_l": _v(-80),
		"shoulder_r": _v(-25, 0, -12), "elbow_r": _v(-80),
	}
	p["run_r"] = {
		"hips:offset": _v(0, -0.05, 0), "spine": _v(16, -8, 0), "chest": _v(4), "head": _v(-14),
		"thigh_r": _v(-55), "knee_r": _v(25), "foot_r": _v(-10),
		"thigh_l": _v(35), "knee_l": _v(55), "foot_l": _v(20),
		"shoulder_l": _v(-45, 0, 14), "elbow_l": _v(-80),
		"shoulder_r": _v(20, 0, -12), "elbow_r": _v(-70),
	}
	p["run_pass_b"] = {
		"hips:offset": _v(0, 0.04, 0), "spine": _v(16, 0, 0), "head": _v(-14),
		"thigh_r": _v(-12), "knee_r": _v(30),
		"thigh_l": _v(-30), "knee_l": _v(100), "foot_l": _v(20),
		"shoulder_l": _v(-20, 0, 14), "elbow_l": _v(-80),
		"shoulder_r": _v(0, 0, -12), "elbow_r": _v(-75),
	}
	var g: Dictionary = p["guard"]
	# Horizontal slash (right to left).
	p["slash_windup"] = _derive(g, {
		"hips": _v(0, 25, 0), "spine": _v(-4, 20, 0), "chest": _v(-8, 25, 0), "head": _v(0, -35, 0),
		"shoulder_r": _v(-95, 0, -85), "elbow_r": _v(-50), "hand_r": _v(0, 0, 40),
		"shoulder_l": _v(-40, 0, 30), "elbow_l": _v(-70),
	})
	p["slash_strike"] = _derive(g, {
		"hips:offset": _v(0, -0.12, 0.22), "hips": _v(0, -35, 0),
		"spine": _v(14, -25, 0), "chest": _v(6, -30, 0), "head": _v(-10, 40, 0),
		"thigh_l": _v(-50, 0, 8), "knee_l": _v(55), "thigh_r": _v(32, 0, -8), "knee_r": _v(18),
		"shoulder_r": _v(-90, 0, 30), "elbow_r": _v(-8), "hand_r": _v(0, 0, -30),
		"shoulder_l": _v(-10, 0, 45), "elbow_l": _v(-40),
	})
	# Backhand slash (left to right).
	p["backhand_windup"] = _derive(g, {
		"hips": _v(0, -30, 0), "spine": _v(6, -20, 0), "chest": _v(0, -30, 0), "head": _v(0, 40, 0),
		"shoulder_r": _v(-85, 0, 35), "elbow_r": _v(-95), "hand_r": _v(0, 0, -50),
		"shoulder_l": _v(-30, 0, 25), "elbow_l": _v(-60),
	})
	p["backhand_strike"] = _derive(g, {
		"hips:offset": _v(0, -0.1, 0.18), "hips": _v(0, 30, 0),
		"spine": _v(12, 25, 0), "chest": _v(4, 30, 0), "head": _v(-8, -45, 0),
		"thigh_l": _v(-45, 0, 8), "knee_l": _v(50),
		"shoulder_r": _v(-80, 0, -95), "elbow_r": _v(-10), "hand_r": _v(0, 0, 30),
		"shoulder_l": _v(-20, 0, 50), "elbow_l": _v(-50),
	})
	# Overhead cleave.
	p["overhead_windup"] = _derive(g, {
		"hips:offset": _v(0, -0.02, -0.05), "spine": _v(-10, 0, 0), "chest": _v(-14, 0, 0), "head": _v(-14),
		"shoulder_r": _v(-185, 0, -12), "elbow_r": _v(-45),
		"shoulder_l": _v(-175, 0, 18), "elbow_l": _v(-50),
		"thigh_l": _v(-20, 0, 8), "knee_l": _v(15),
	})
	p["overhead_strike"] = _derive(g, {
		"hips:offset": _v(0, -0.22, 0.25), "spine": _v(32, 0, 0), "chest": _v(14, 0, 0), "head": _v(-25),
		"thigh_l": _v(-62, 0, 10), "knee_l": _v(75), "thigh_r": _v(30, 0, -10), "knee_r": _v(45),
		"shoulder_r": _v(-75, 0, -6), "elbow_r": _v(-5),
		"shoulder_l": _v(-70, 0, 8), "elbow_l": _v(-10),
	})
	# Thrust.
	p["thrust_windup"] = _derive(g, {
		"hips": _v(0, 20, 0), "spine": _v(0, 15, 0), "chest": _v(-4, 15, 0), "head": _v(0, -25, 0),
		"shoulder_r": _v(-15, 0, -20), "elbow_r": _v(-120), "hand_r": _v(-75, 0, 0),
		"shoulder_l": _v(-75, 0, 20), "elbow_l": _v(-30),
	})
	p["thrust_strike"] = _derive(g, {
		"hips:offset": _v(0, -0.14, 0.32), "hips": _v(0, -20, 0),
		"spine": _v(18, -15, 0), "chest": _v(4, -12, 0), "head": _v(-14, 22, 0),
		"thigh_l": _v(-58, 0, 6), "knee_l": _v(62), "thigh_r": _v(42, 0, -6), "knee_r": _v(10),
		"shoulder_r": _v(-92, 0, -4), "elbow_r": _v(0), "hand_r": _v(-90, 0, 0),
		"shoulder_l": _v(20, 0, 35), "elbow_l": _v(-30),
	})
	# Rising slash.
	p["rising_windup"] = _derive(g, {
		"hips:offset": _v(0, -0.2, 0), "spine": _v(25, 15, 0), "head": _v(-25),
		"thigh_l": _v(-55, 0, 10), "knee_l": _v(85), "thigh_r": _v(25, 0, -10), "knee_r": _v(70),
		"shoulder_r": _v(30, 0, -35), "elbow_r": _v(-20), "hand_r": _v(40, 0, 0),
		"shoulder_l": _v(-40, 0, 25), "elbow_l": _v(-70),
	})
	p["rising_strike"] = _derive(g, {
		"hips:offset": _v(0, 0.05, 0.15), "spine": _v(-14, -15, 0), "chest": _v(-12, -10, 0), "head": _v(-18),
		"thigh_l": _v(-20, 0, 6), "knee_l": _v(10), "thigh_r": _v(10, 0, -6), "knee_r": _v(10), "foot_r": _v(30),
		"shoulder_r": _v(-170, 0, -25), "elbow_r": _v(-10), "hand_r": _v(-20, 0, 0),
		"shoulder_l": _v(-10, 0, 50), "elbow_l": _v(-30),
	})
	# Defence.
	p["block"] = _derive(g, {
		"hips:offset": _v(0, -0.12, -0.06), "spine": _v(10, 0, 0), "head": _v(6),
		"shoulder_l": _v(-85, 0, 6), "elbow_l": _v(-95),
		"shoulder_r": _v(-80, 0, 30), "elbow_r": _v(-85), "hand_r": _v(0, 0, 70),
		"thigh_l": _v(-35, 0, 10), "knee_l": _v(48), "thigh_r": _v(26, 0, -10), "knee_r": _v(42),
	})
	p["parry"] = _derive(g, {
		"hips:offset": _v(0, -0.08, -0.04), "hips": _v(0, 15, 0), "chest": _v(0, 20, 0),
		"shoulder_r": _v(-120, 0, 10), "elbow_r": _v(-60), "hand_r": _v(0, 0, 60),
		"shoulder_l": _v(-30, 0, 30), "elbow_l": _v(-60),
	})
	p["dodge"] = _derive(g, {
		"hips:offset": _v(0, -0.16, -0.12), "hips": _v(0, 0, 12), "spine": _v(-14, 0, 18), "chest": _v(-8, 0, 10), "head": _v(8, 0, -16),
		"thigh_l": _v(-10, 0, 20), "knee_l": _v(40), "thigh_r": _v(40, 0, -10), "knee_r": _v(60),
		"shoulder_r": _v(-30, 0, -45), "elbow_r": _v(-60),
		"shoulder_l": _v(-20, 0, 55), "elbow_l": _v(-50),
	})
	p["hit_react"] = _derive(g, {
		"hips:offset": _v(0, -0.06, -0.1), "spine": _v(-18, 8, 0), "chest": _v(-14, 0, 0), "head": _v(-28, 10, 0),
		"shoulder_r": _v(-20, 0, -55), "elbow_r": _v(-30),
		"shoulder_l": _v(-10, 0, 60), "elbow_l": _v(-25),
		"thigh_l": _v(-10, 0, 8), "knee_l": _v(20),
	})
	p["stagger"] = _derive(g, {
		"hips:offset": _v(0, -0.2, -0.05), "spine": _v(30, 0, 6), "chest": _v(18, 0, 0), "head": _v(20),
		"shoulder_r": _v(-10, 0, -20), "elbow_r": _v(-40),
		"shoulder_l": _v(-30, 0, 12), "elbow_l": _v(-80),
		"thigh_l": _v(-40, 0, 10), "knee_l": _v(70), "thigh_r": _v(20, 0, -10), "knee_r": _v(60),
	})
	p["kneel"] = {
		"hips:offset": _v(0, -0.42, 0), "spine": _v(18), "chest": _v(8), "head": _v(22),
		"thigh_l": _v(-80, 0, 6), "knee_l": _v(88), "foot_l": _v(-6),
		"thigh_r": _v(10, 0, -6), "knee_r": _v(100), "foot_r": _v(40),
		"shoulder_r": _v(-25, 0, -12), "elbow_r": _v(-50),
		"shoulder_l": _v(-50, 0, 10), "elbow_l": _v(-70),
	}
	p["fall"] = _derive(p["kneel"], {
		"base": _v(84, 0, 6), "base:offset": _v(0, 0.12, 0.25),
		"hips:offset": _v(0, -0.3, 0), "spine": _v(6, 0, 8), "head": _v(-10, 20, 0),
		"thigh_l": _v(-20, 0, 10), "knee_l": _v(30), "thigh_r": _v(0, 0, -10), "knee_r": _v(20),
		"shoulder_r": _v(-160, 0, -40), "elbow_r": _v(-10),
		"shoulder_l": _v(-150, 0, 50), "elbow_l": _v(-20),
	})
	p["victory"] = {
		"spine": _v(-6), "chest": _v(-10), "head": _v(-14),
		"shoulder_r": _v(-178, 0, -14), "elbow_r": _v(-6), "hand_r": _v(-20, 0, 0),
		"shoulder_l": _v(-30, 0, 25), "elbow_l": _v(-100),
		"thigh_l": _v(-10, 0, 10), "knee_l": _v(10), "thigh_r": _v(6, 0, -8),
	}
	p["salute"] = _derive(p["idle"], {
		"shoulder_r": _v(-70, 0, 30), "elbow_r": _v(-120), "hand_r": _v(0, 0, 20),
		"head": _v(10),
	})
	p["power_charge"] = {
		"hips:offset": _v(0, -0.14, 0), "spine": _v(-8), "chest": _v(-16), "head": _v(-26),
		"shoulder_r": _v(-40, 0, -70), "elbow_r": _v(-30),
		"shoulder_l": _v(-40, 0, 70), "elbow_l": _v(-30),
		"thigh_l": _v(-20, 0, 18), "knee_l": _v(35), "thigh_r": _v(-20, 0, -18), "knee_r": _v(35),
	}
	p["cast_charge"] = _derive(g, {
		"spine": _v(-6, 10, 0), "chest": _v(-10, 12, 0), "head": _v(-6, -15, 0),
		"shoulder_r": _v(-150, 0, -10), "elbow_r": _v(-30),
		"shoulder_l": _v(-100, 0, 25), "elbow_l": _v(-60),
	})
	p["cast_release"] = _derive(g, {
		"hips:offset": _v(0, -0.1, 0.12), "spine": _v(18, -8, 0), "chest": _v(8, -8, 0), "head": _v(-14, 8, 0),
		"thigh_l": _v(-45, 0, 8), "knee_l": _v(50),
		"shoulder_r": _v(-95, 0, -5), "elbow_r": _v(-5),
		"shoulder_l": _v(-90, 0, 10), "elbow_l": _v(-5),
	})
	p["jump_crouch"] = _derive(g, {
		"hips:offset": _v(0, -0.3, 0), "spine": _v(30), "head": _v(-20),
		"thigh_l": _v(-70, 0, 10), "knee_l": _v(100), "thigh_r": _v(-50, 0, -10), "knee_r": _v(100),
		"shoulder_r": _v(30, 0, -30), "shoulder_l": _v(30, 0, 30),
	})
	p["jump_air"] = _derive(g, {
		"hips:offset": _v(0, 0.05, 0), "spine": _v(10), "head": _v(-10),
		"thigh_l": _v(-80, 0, 10), "knee_l": _v(110), "thigh_r": _v(-40, 0, -10), "knee_r": _v(120),
		"shoulder_r": _v(-175, 0, -10), "elbow_r": _v(-40),
		"shoulder_l": _v(-150, 0, 20), "elbow_l": _v(-40),
	})
	p["ride"] = {
		"hips:offset": _v(0, 0, 0), "spine": _v(4),
		"thigh_l": _v(-72, 0, 28), "knee_l": _v(78), "foot_l": _v(-10),
		"thigh_r": _v(-72, 0, -28), "knee_r": _v(78), "foot_r": _v(-10),
		"shoulder_r": _v(-25, 0, -10), "elbow_r": _v(-70),
		"shoulder_l": _v(-30, 0, 12), "elbow_l": _v(-70),
	}
	p["surrender"] = _derive(p["kneel"], {
		"head": _v(38), "spine": _v(26),
		"shoulder_r": _v(5, 0, -18), "elbow_r": _v(-5), "hand_r": _v(60, 0, 0),
		"shoulder_l": _v(-10, 0, 10), "elbow_l": _v(-30),
	})
	return p


static func _build_humanoid_clips() -> Dictionary:
	var c := {}
	c["rest"] = {"keys": [[0.0, "rest"]], "loop": true}
	c["idle"] = {"keys": [[0.0, "idle"]], "loop": true}
	c["guard"] = {"keys": [[0.0, "guard"]], "loop": true}
	c["ride"] = {"keys": [[0.0, "ride"]], "loop": true}
	c["walk"] = {"keys": [[0.0, "walk_l"], [0.3, "walk_pass_a"], [0.6, "walk_r"], [0.9, "walk_pass_b"], [1.2, "walk_l"]],
		"loop": true, "events": [[0.0, "step"], [0.6, "step"]]}
	c["run"] = {"keys": [[0.0, "run_l"], [0.17, "run_pass_a"], [0.34, "run_r"], [0.51, "run_pass_b"], [0.68, "run_l"]],
		"loop": true, "events": [[0.0, "step"], [0.34, "step"]]}
	c["slash"] = {"keys": [[0.0, "guard"], [0.26, "slash_windup"], [0.4, "slash_strike"], [0.85, "guard"]],
		"events": [[0.3, "whoosh"], [0.38, "hit"]]}
	c["backhand"] = {"keys": [[0.0, "guard"], [0.24, "backhand_windup"], [0.38, "backhand_strike"], [0.82, "guard"]],
		"events": [[0.28, "whoosh"], [0.36, "hit"]]}
	c["overhead"] = {"keys": [[0.0, "guard"], [0.36, "overhead_windup"], [0.52, "overhead_strike"], [1.05, "guard"]],
		"events": [[0.4, "whoosh"], [0.5, "hit"]]}
	c["thrust"] = {"keys": [[0.0, "guard"], [0.22, "thrust_windup"], [0.34, "thrust_strike"], [0.78, "guard"]],
		"events": [[0.26, "whoosh"], [0.32, "hit"]]}
	c["rising"] = {"keys": [[0.0, "guard"], [0.24, "rising_windup"], [0.4, "rising_strike"], [0.9, "guard"]],
		"events": [[0.3, "whoosh"], [0.38, "hit"]]}
	c["combo"] = {"keys": [[0.0, "guard"], [0.2, "slash_windup"], [0.32, "slash_strike"], [0.48, "backhand_windup"],
		[0.6, "backhand_strike"], [0.82, "thrust_windup"], [0.94, "thrust_strike"], [1.35, "guard"]],
		"events": [[0.25, "whoosh"], [0.31, "hit"], [0.53, "whoosh"], [0.59, "hit"], [0.86, "whoosh"], [0.93, "hit"]]}
	c["cast"] = {"keys": [[0.0, "guard"], [0.4, "cast_charge"], [0.56, "cast_release"], [1.0, "guard"]],
		"events": [[0.1, "charge"], [0.54, "release"]]}
	c["block"] = {"keys": [[0.0, "guard"], [0.12, "block"], [0.55, "block"], [0.8, "guard"]],
		"events": [[0.14, "impact"]]}
	c["block_hold"] = {"keys": [[0.0, "block"]], "loop": true}
	c["parry"] = {"keys": [[0.0, "guard"], [0.1, "parry"], [0.4, "parry"], [0.65, "guard"]],
		"events": [[0.11, "impact"]]}
	c["dodge"] = {"keys": [[0.0, "guard"], [0.14, "dodge"], [0.38, "dodge"], [0.65, "guard"]],
		"events": [[0.05, "whoosh"]]}
	c["hit"] = {"keys": [[0.0, "guard"], [0.08, "hit_react"], [0.5, "guard"]]}
	c["stagger"] = {"keys": [[0.0, "guard"], [0.08, "hit_react"], [0.35, "stagger"], [1.0, "stagger"]]}
	c["stagger_hold"] = {"keys": [[0.0, "stagger"]], "loop": true}
	c["death"] = {"keys": [[0.0, "hit_react"], [0.18, "hit_react"], [0.6, "kneel"], [0.95, "kneel"], [1.45, "fall"]],
		"events": [[0.6, "knee"], [1.4, "thud"]]}
	c["victory"] = {"keys": [[0.0, "guard"], [0.45, "victory"], [2.0, "victory"]],
		"events": [[0.45, "cheer"]]}
	c["salute"] = {"keys": [[0.0, "idle"], [0.5, "salute"], [1.1, "salute"], [1.5, "guard"]]}
	c["power_up"] = {"keys": [[0.0, "guard"], [0.5, "power_charge"], [1.6, "power_charge"]],
		"events": [[0.2, "aura"]]}
	c["jump"] = {"keys": [[0.0, "guard"], [0.2, "jump_crouch"], [0.4, "jump_air"], [1.0, "jump_air"]],
		"events": [[0.22, "jump"]]}
	c["land_strike"] = {"keys": [[0.0, "jump_air"], [0.12, "overhead_strike"], [0.6, "overhead_strike"], [0.95, "guard"]],
		"events": [[0.1, "hit"], [0.12, "land"]]}
	c["surrender"] = {"keys": [[0.0, "idle"], [0.9, "kneel"], [1.6, "surrender"], [3.0, "surrender"]],
		"events": [[0.9, "knee"], [1.5, "drop"]]}
	return c


static func _build_horse_poses() -> Dictionary:
	var p := {}
	p["stand"] = {"neck": _v(0), "head": _v(0), "tail": _v(20)}
	p["walk_a"] = {"leg_fl": _v(-18), "knee_fl": _v(10), "leg_br": _v(-14), "knee_br": _v(-10),
		"leg_fr": _v(14), "knee_fr": _v(30), "leg_bl": _v(16), "knee_bl": _v(-25), "neck": _v(4), "tail": _v(24)}
	p["walk_b"] = {"leg_fr": _v(-18), "knee_fr": _v(10), "leg_bl": _v(-14), "knee_bl": _v(-10),
		"leg_fl": _v(14), "knee_fl": _v(30), "leg_br": _v(16), "knee_br": _v(-25), "neck": _v(-2), "tail": _v(18)}
	p["gallop_gather"] = {"body:offset": _v(0, -0.06, 0), "body": _v(4),
		"leg_fl": _v(30), "knee_fl": _v(70), "leg_fr": _v(18), "knee_fr": _v(55),
		"leg_bl": _v(-38), "knee_bl": _v(-20), "leg_br": _v(-28), "knee_br": _v(-15),
		"neck": _v(12), "head": _v(-6), "tail": _v(35)}
	p["gallop_extend"] = {"body:offset": _v(0, 0.12, 0), "body": _v(-5),
		"leg_fl": _v(-55), "knee_fl": _v(5), "leg_fr": _v(-42), "knee_fr": _v(15),
		"leg_bl": _v(40), "knee_bl": _v(-5), "leg_br": _v(30), "knee_br": _v(-10),
		"neck": _v(-8), "head": _v(6), "tail": _v(55)}
	p["rear"] = {"body:offset": _v(0, 0.35, -0.2), "body": _v(-38),
		"leg_fl": _v(-70), "knee_fl": _v(100), "leg_fr": _v(-55), "knee_fr": _v(90),
		"leg_bl": _v(32), "knee_bl": _v(-10), "leg_br": _v(38), "knee_br": _v(-15),
		"neck": _v(-12), "head": _v(-20), "tail": _v(10)}
	p["fall"] = {"body:offset": _v(0, -0.75, 0), "body": _v(0, 0, 80),
		"leg_fl": _v(-20), "knee_fl": _v(40), "leg_fr": _v(10), "knee_fr": _v(30),
		"leg_bl": _v(20), "knee_bl": _v(-30), "leg_br": _v(-10), "knee_br": _v(-20),
		"neck": _v(30, 0, 0), "head": _v(20), "tail": _v(0)}
	return p


static func _build_horse_clips() -> Dictionary:
	var c := {}
	c["stand"] = {"keys": [[0.0, "stand"]], "loop": true}
	c["walk"] = {"keys": [[0.0, "walk_a"], [0.5, "walk_b"], [1.0, "walk_a"]], "loop": true,
		"events": [[0.0, "hoof"], [0.5, "hoof"]]}
	c["gallop"] = {"keys": [[0.0, "gallop_gather"], [0.22, "gallop_extend"], [0.44, "gallop_gather"]], "loop": true,
		"events": [[0.05, "hoof"], [0.27, "hoof"]]}
	c["rear"] = {"keys": [[0.0, "stand"], [0.45, "rear"], [1.0, "rear"], [1.5, "stand"]],
		"events": [[0.4, "neigh"], [1.45, "hoof"]]}
	c["fall"] = {"keys": [[0.0, "stand"], [0.3, "rear"], [1.1, "fall"]], "events": [[1.05, "thud"]]}
	return c

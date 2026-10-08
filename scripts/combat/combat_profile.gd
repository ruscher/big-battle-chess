class_name CombatProfile
extends RefCounted
## Data-driven fighting style of each piece class. The choreographer combines
## these profiles (attacker x defender) into a unique battle, so no pair of
## classes needs hand-made animation.

const PROFILES := {
	Chess.PAWN: {
		"style": "infantry", "speed": 1.12, "mobility": 0.9, "magic": false,
		"attacks": ["thrust", "slash", "combo", "rising", "thrust"],
		"defenses": ["block", "parry", "dodge"],
		"specials": ["dash", "leap"],
		"finisher": "valor_lunge",
		"hp_flavor": 1,
	},
	Chess.KNIGHT: {
		"style": "cavalry", "speed": 1.0, "mobility": 1.3, "magic": false, "mounted": true,
		"attacks": ["thrust", "slash", "overhead", "backhand"],
		"defenses": ["parry", "block"],
		"specials": ["charge", "charge"],
		"finisher": "thunder_charge",
		"hp_flavor": 3,
	},
	Chess.BISHOP: {
		"style": "mystic", "speed": 0.98, "mobility": 1.0, "magic": true,
		"attacks": ["cast", "overhead", "cast", "slash"],
		"defenses": ["parry", "dodge"],
		"specials": ["volley", "dash"],
		"finisher": "sacred_pillar",
		"hp_flavor": 3,
	},
	Chess.ROOK: {
		"style": "heavy", "speed": 0.82, "mobility": 0.7, "magic": false,
		"attacks": ["overhead", "slash", "backhand", "overhead"],
		"defenses": ["block", "block"],
		"specials": ["leap", "slam"],
		"finisher": "earthshatter",
		"hp_flavor": 5,
	},
	Chess.QUEEN: {
		"style": "duelist", "speed": 1.2, "mobility": 1.4, "magic": true,
		"attacks": ["combo", "thrust", "backhand", "cast", "slash"],
		"defenses": ["dodge", "parry", "dodge"],
		"specials": ["dash", "volley", "leap"],
		"finisher": "crown_of_storms",
		"hp_flavor": 9,
	},
	Chess.KING: {
		"style": "royal", "speed": 0.92, "mobility": 0.9, "magic": false,
		"attacks": ["overhead", "slash", "backhand", "rising"],
		"defenses": ["parry", "block"],
		"specials": ["leap", "slam"],
		"finisher": "royal_verdict",
		"hp_flavor": 10,
	},
}

## Finisher names (translation keys) per faction: [dawn, umbral].
const FINISHER_KEYS := {
	"valor_lunge": ["FIN_VALOR_LUNGE", "FIN_HOLLOW_FANG"],
	"thunder_charge": ["FIN_THUNDER_CHARGE", "FIN_NIGHTMARE_CHARGE"],
	"sacred_pillar": ["FIN_SACRED_PILLAR", "FIN_UMBRAL_ECLIPSE"],
	"earthshatter": ["FIN_EARTHSHATTER", "FIN_GRAVEQUAKE"],
	"crown_of_storms": ["FIN_CROWN_OF_STORMS", "FIN_VOID_TEMPEST"],
	"royal_verdict": ["FIN_ROYAL_VERDICT", "FIN_TYRANTS_DECREE"],
}

## Special matchup titles (attacker type, defender type) -> key.
const SPECIAL_MATCHUPS := {
	Vector2i(Chess.PAWN, Chess.QUEEN): "TITLE_LEGENDARY_CAPTURE",
	Vector2i(Chess.PAWN, Chess.ROOK): "TITLE_GIANT_SLAYER",
	Vector2i(Chess.PAWN, Chess.KNIGHT): "TITLE_GIANT_SLAYER",
	Vector2i(Chess.PAWN, Chess.BISHOP): "TITLE_GIANT_SLAYER",
	Vector2i(Chess.QUEEN, Chess.ROOK): "TITLE_STORM_VS_FORTRESS",
	Vector2i(Chess.KNIGHT, Chess.BISHOP): "TITLE_STEEL_VS_FAITH",
	Vector2i(Chess.ROOK, Chess.QUEEN): "TITLE_FORTRESS_FALLS_QUEEN",
	Vector2i(Chess.BISHOP, Chess.BISHOP): "TITLE_MIRROR_OF_FAITH",
	Vector2i(Chess.QUEEN, Chess.QUEEN): "TITLE_CLASH_OF_CROWNS",
}


static func get_profile(type: int) -> Dictionary:
	return PROFILES[clampi(type, 1, 6)]


static func finisher_key(type: int, color: int) -> String:
	var fin: String = get_profile(type)["finisher"]
	return FINISHER_KEYS[fin][clampi(color, 0, 1)]


static func matchup_title(attacker: int, defender: int) -> String:
	return SPECIAL_MATCHUPS.get(Vector2i(attacker, defender), "")


## Clip length (seconds) at a given speed, read from the pose library.
static func clip_length(clip: String, speed: float = 1.0) -> float:
	var c: Dictionary = PoseLibrary.humanoid_clips().get(clip, {})
	if c.is_empty():
		return 0.0
	return float(c["keys"][-1][0]) / speed


static func clip_event(clip: String, event_name: String, speed: float = 1.0) -> float:
	var c: Dictionary = PoseLibrary.humanoid_clips().get(clip, {})
	for e in c.get("events", []):
		if String(e[1]) == event_name:
			return float(e[0]) / speed
	return -1.0


static func clip_events(clip: String, event_name: String, speed: float = 1.0) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var c: Dictionary = PoseLibrary.humanoid_clips().get(clip, {})
	for e in c.get("events", []):
		if String(e[1]) == event_name:
			times.append(float(e[0]) / speed)
	return times

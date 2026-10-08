class_name FactionStyle
extends RefCounted
## Visual identity of the two armies. White pieces belong to the Kingdom of
## Dawn, black pieces to the Umbral Dominion. Everything here is original.

const DAWN := 0
const UMBRAL := 1

const STYLES := [
	{
		"id": "dawn",
		"name_key": "FACTION_DAWN",
		"armor": Color(0.80, 0.81, 0.84), "armor_metallic": 0.95, "armor_roughness": 0.24,
		"trim": Color(1.0, 0.77, 0.36),
		"cloth": Color(0.88, 0.84, 0.74),
		"cloth_alt": Color(0.12, 0.22, 0.56),
		"leather": Color(0.36, 0.23, 0.13),
		"energy": Color(1.0, 0.82, 0.45),
		"energy_alt": Color(0.55, 0.85, 1.0),
		"eyes": Color(0.6, 0.85, 1.0), "eye_glow": 0.6,
		"horse": Color(0.86, 0.84, 0.80),
		"mask": Color(1.0, 0.82, 0.48),
		"emblem": 0,
	},
	{
		"id": "umbral",
		"name_key": "FACTION_UMBRAL",
		"armor": Color(0.085, 0.085, 0.10), "armor_metallic": 0.88, "armor_roughness": 0.36,
		"trim": Color(0.62, 0.30, 0.14),
		"cloth": Color(0.40, 0.035, 0.055),
		"cloth_alt": Color(0.14, 0.045, 0.20),
		"leather": Color(0.12, 0.08, 0.07),
		"energy": Color(0.78, 0.22, 1.0),
		"energy_alt": Color(1.0, 0.18, 0.12),
		"eyes": Color(1.0, 0.16, 0.08), "eye_glow": 5.0,
		"horse": Color(0.06, 0.05, 0.055),
		"mask": Color(0.92, 0.9, 0.86),
		"emblem": 1,
	},
]

## Unit names per piece type (translation keys), index = Chess piece type.
const UNIT_KEYS := [
	["", "UNIT_DAWN_PAWN", "UNIT_DAWN_KNIGHT", "UNIT_DAWN_BISHOP", "UNIT_DAWN_ROOK", "UNIT_DAWN_QUEEN", "UNIT_DAWN_KING"],
	["", "UNIT_UMBRAL_PAWN", "UNIT_UMBRAL_KNIGHT", "UNIT_UMBRAL_BISHOP", "UNIT_UMBRAL_ROOK", "UNIT_UMBRAL_QUEEN", "UNIT_UMBRAL_KING"],
]


static func get_style(color: int) -> Dictionary:
	return STYLES[clampi(color, 0, 1)]


static func unit_key(color: int, piece_type: int) -> String:
	return UNIT_KEYS[clampi(color, 0, 1)][clampi(piece_type, 0, 6)]

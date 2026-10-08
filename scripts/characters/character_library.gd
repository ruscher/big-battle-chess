class_name CharacterLibrary
extends RefCounted
## Registry of imported (skinned) character assets.
##
## Imported models live in res://assets/characters_ext/ (built locally by
## tools/blender/build_characters.py and kept out of Git because of their
## third-party licenses). When an archetype is missing, the game uses the
## procedural CharacterRig, so the project always runs.

const ROOT := "res://assets/characters_ext/"

## Per piece type. "map": bone name map; "height": model height in metres;
## "board"/"arena": glTF per LOD; "hand_forward": weapon direction hint.
const ARCHETYPES := {
	Chess.ROOK: {
		"id": "rook", "board": "rook/rook_board.gltf", "arena": "rook/rook_arena.gltf",
		"map": "ue", "height": 1.92, "scale": 1.12, "tip_offset": 0.18,
		"look": {
			"dawn": {"cloth_tint": Color(0.16, 0.24, 0.55), "cloth_tint_amount": 0.7},
			"umbral": {"cloth_tint": Color(0.42, 0.05, 0.07), "cloth_tint_amount": 0.75},
		},
	},
	Chess.KING: {
		"id": "king", "board": "king/king_board.gltf", "arena": "king/king_arena.gltf",
		"map": "bbc", "height": 2.25, "scale": 1.15, "tip_offset": 0.85,
		# Heavy, regal movement: the fused sculpt also deforms best with restrained arms.
		"joint_scale": {"shoulder_l": 0.45, "elbow_l": 0.4, "shoulder_r": 0.8, "spine": 0.7, "chest": 0.7},
		"look": {
			# Sculpt with a weak metallic map: armour 0.1-0.5, robe < 0.1.
			"dawn": {"metal_mask_lo": 0.06, "metal_mask_hi": 0.2,
				"cloth_tint": Color(0.16, 0.26, 0.75), "cloth_tint_amount": 0.9, "cloth_floor": 0.03, "cloth_lum_scale": 3.2,
				"metal_tint": Color(1.0, 0.86, 0.6), "metal_lum_scale": 6.0, "metal_tint_amount": 0.8, "metal_roughness_mul": 0.7},
			"umbral": {"metal_mask_lo": 0.06, "metal_mask_hi": 0.2,
				"cloth_tint": Color(0.55, 0.03, 0.05), "cloth_tint_amount": 0.35, "cloth_floor": 0.02, "cloth_lum_scale": 2.0,
				"metal_tint": Color(0.5, 0.42, 0.42), "metal_lum_scale": 2.2, "metal_tint_amount": 0.35, "metal_gain": 1.0},
		},
	},
	Chess.BISHOP: {
		"id": "warrior", "board": "warrior/warrior_board.gltf", "arena": "warrior/warrior_arena.gltf",
		"map": "bbc", "height": 1.86, "scale": 1.04, "tip_offset": 0.85, "halo": true,
		"joint_scale": {"elbow_l": 0.25, "shoulder_l": 0.7},
		"look": {
			"dawn": {"cloth_tint": Color(0.97, 0.93, 0.84), "cloth_tint_amount": 0.25, "accent_color": Color(1.0, 0.72, 0.22), "accent_amount": 1.0, "accent_hue": 0.057, "accent_hue_width": 0.035, "accent_val_min": 0.1},
			"umbral": {"cloth_tint": Color(0.16, 0.08, 0.2), "cloth_tint_amount": 0.88, "accent_color": Color(0.6, 0.2, 0.95), "accent_amount": 1.0, "accent_hue": 0.057, "accent_hue_width": 0.035, "accent_val_min": 0.1},
		},
	},
	Chess.PAWN: {
		"id": "warrior", "board": "warrior/warrior_board.gltf", "arena": "warrior/warrior_arena.gltf",
		"map": "bbc", "height": 1.86, "scale": 0.9, "tip_offset": 0.85,
		"joint_scale": {"elbow_l": 0.25, "shoulder_l": 0.7},
		"look": {
			"dawn": {"cloth_tint": Color(0.95, 0.92, 0.86), "cloth_tint_amount": 0.2, "accent_color": Color(0.15, 0.3, 0.85), "accent_amount": 1.0, "accent_hue": 0.057, "accent_hue_width": 0.035, "accent_val_min": 0.1},
			"umbral": {"cloth_tint": Color(0.1, 0.09, 0.1), "cloth_tint_amount": 0.85, "accent_color": Color(0.8, 0.06, 0.1), "accent_amount": 1.0, "accent_hue": 0.057, "accent_hue_width": 0.035, "accent_val_min": 0.1},
		},
	},
}

## Bone maps: procedural joint -> skeleton bone.
const BONE_MAPS := {
	"ue": {
		"hips": "pelvis", "spine": "spine_02", "chest": "spine_04", "neck": "neck_01", "head": "head",
		"shoulder_l": "upperarm_l", "elbow_l": "lowerarm_l", "hand_l": "hand_l",
		"shoulder_r": "upperarm_r", "elbow_r": "lowerarm_r", "hand_r": "hand_r",
		"thigh_l": "thigh_l", "knee_l": "calf_l", "foot_l": "foot_l",
		"thigh_r": "thigh_r", "knee_r": "calf_r", "foot_r": "foot_r",
	},
	"bbc": {
		"hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "neck": "neck", "head": "head",
		"shoulder_l": "upperarm_l", "elbow_l": "lowerarm_l", "hand_l": "hand_l",
		"shoulder_r": "upperarm_r", "elbow_r": "lowerarm_r", "hand_r": "hand_r",
		"thigh_l": "thigh_l", "knee_l": "calf_l", "foot_l": "foot_l",
		"thigh_r": "thigh_r", "knee_r": "calf_r", "foot_r": "foot_r",
	},
}

## Joints whose rest direction is normalised to "hanging down" before the
## authored pose is applied (models are authored in A/T-pose).
const LIMB_FIX := ["shoulder_l", "elbow_l", "shoulder_r", "elbow_r", "thigh_l", "knee_l", "thigh_r", "knee_r"]

static var _scenes: Dictionary = {}
static var _disabled: bool = false


## Disables imported characters (procedural only), e.g. for comparisons.
static func set_enabled(enabled: bool) -> void:
	_disabled = not enabled


static func has_archetype(type: int) -> bool:
	if _disabled or not ARCHETYPES.has(type):
		return false
	var a: Dictionary = ARCHETYPES[type]
	return ResourceLoader.exists(ROOT + a["board"]) and ResourceLoader.exists(ROOT + a["arena"])


static func info(type: int) -> Dictionary:
	return ARCHETYPES.get(type, {})


## Cached PackedScene for a type and context ("board" or "arena").
static func scene(type: int, context: String) -> PackedScene:
	# Cached per file, so archetypes sharing a model share its resources.
	var path: String = ROOT + ARCHETYPES[type][context]
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]


static func clear_cache() -> void:
	_scenes.clear()
	SkinnedCharacterRig.clear_material_cache()


## Factory used by the board and the arena: imported model when available,
## procedural fallback otherwise. `context` is "board" or "arena".
static func create(type: int, color: int, context: String) -> CharacterRig:
	if has_archetype(type):
		var rig := SkinnedCharacterRig.new()
		rig.context = context
		return rig
	return CharacterRig.new()

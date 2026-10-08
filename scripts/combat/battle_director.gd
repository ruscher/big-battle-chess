class_name BattleDirector
extends Node3D
## Executes a CombatTimeline in the BattleArena.
##
## The director is purely presentational: it receives a request describing an
## already-committed capture and plays it. Skipping or fast-forwarding only
## shortens the show; it can never change the board, because the board was
## updated before the battle started.

signal finished
signal title_requested(text_key: String, style: String, color: Color)
signal flash_requested(strength: float, color: Color)

const MAX_REAL_SECONDS := 120.0
const VOICE_PITCH := {Chess.PAWN: 1.08, Chess.KNIGHT: 1.0, Chess.BISHOP: 0.95, Chess.ROOK: 0.78, Chess.QUEEN: 1.35, Chess.KING: 0.85}

var arena: BattleArena
var camera: CinematicCamera
var vfx: CombatVFX
var playing: bool = false
var timeline: CombatTimeline
var user_speed: float = 1.0

var _fighters: Dictionary = {}
var _colors: Dictionary = {}
var _types: Dictionary = {}
var _moves: Dictionary = {}
var _turns: Dictionary = {}
var _fades: Dictionary = {}
var _auras: Dictionary = {}
var _projectiles: Array[Dictionary] = []
var _t: float = 0.0
var _real: float = 0.0
var _cue_index: int = 0
var _ts: float = 1.0
var _ts_remaining: float = 0.0
## Ops executed during the last frame (profiling aid).
var last_frame_ops: PackedStringArray = []


func _ready() -> void:
	arena = BattleArena.new()
	arena.name = "Arena"
	add_child(arena)
	vfx = CombatVFX.new()
	vfx.name = "VFX"
	vfx.visual_layer = BattleArena.LAYER
	add_child(vfx)
	camera = CinematicCamera.new()
	camera.name = "CinematicCamera"
	camera.cull_mask = BattleArena.LAYER
	camera.environment = arena.environment
	camera.anchor_provider = _anchor
	add_child(camera)
	set_process(false)


## request: attacker_type, attacker_color, defender_type, defender_color,
## mode, seed, board_theme, en_passant.
func play(request: Dictionary) -> void:
	if playing:
		_cleanup()
	timeline = CombatChoreographer.build(request)
	_types = {"a": int(request["attacker_type"]), "d": int(request["defender_type"])}
	_colors = {
		"a": FactionStyle.get_style(int(request["attacker_color"]))["energy"],
		"d": FactionStyle.get_style(int(request["defender_color"]))["energy"],
	}
	_spawn("a", int(request["attacker_type"]), int(request["attacker_color"]), -3.6)
	_spawn("d", int(request["defender_type"]), int(request["defender_color"]), 3.6)
	arena.set_board_theme(int(request.get("board_theme", 0)))
	arena.reset_lighting()
	arena.visible = true
	var preset := int(Settings.get_value("graphics", "preset"))
	camera.dof_allowed = GraphicsQuality.allows_dof(preset)
	camera.body_radius = {
		"a": 1.9 if int(request["attacker_type"]) == Chess.KNIGHT else 0.95,
		"d": 1.9 if int(request["defender_type"]) == Chess.KNIGHT else 0.95,
	}
	camera.side_sign = 1.0 if (int(request.get("seed", 0)) & 1) == 0 else -1.0
	camera.current = true
	vfx.particle_scale = Settings.particle_scale() * GraphicsQuality.particle_budget(preset)
	vfx.flash_scale = Settings.flash_scale()
	_t = 0.0
	_real = 0.0
	_cue_index = 0
	_ts = 1.0
	_ts_remaining = 0.0
	user_speed = float(Settings.get_value("gameplay", "cinematic_speed"))
	playing = true
	set_process(true)
	_run_cues()
	camera.update_camera(0.0, 0.0)


func skip() -> void:
	if playing:
		_finish()


func _spawn(who: String, type: int, color: int, x: float) -> void:
	var rig := CharacterRig.new()
	rig.name = "Fighter_" + who
	add_child(rig)
	rig.build(type, color)
	_set_layers(rig, BattleArena.LAYER)
	rig.position = Vector3(x, 0, 0)
	rig.rotation.y = PI * 0.5 if x < 0.0 else -PI * 0.5
	rig.anim_event.connect(_on_anim_event.bind(who))
	_fighters[who] = rig


func _set_layers(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for c in node.get_children():
		_set_layers(c, layer)


func _process(delta: float) -> void:
	if not playing:
		return
	if Input.is_action_just_pressed("skip_cinematic"):
		skip()
		return
	var speed_held := Input.is_action_pressed("speed_cinematic")
	var speed_mult := user_speed * (3.0 if speed_held else 1.0)
	if _ts_remaining > 0.0:
		_ts_remaining -= delta * speed_mult
		if _ts_remaining <= 0.0:
			_ts = 1.0
	var dt := delta * speed_mult * _ts
	_t += dt
	_real += delta
	var anim_scale := speed_mult * _ts
	for who in _fighters:
		(_fighters[who] as CharacterRig).set_time_scale(anim_scale)
	vfx.speed_scale = anim_scale
	_run_cues()
	if not playing:
		return
	_update_motion()
	_update_projectiles(dt)
	_update_auras()
	camera.update_camera(dt, delta)
	if _t > timeline.duration + 3.0 or _real > MAX_REAL_SECONDS:
		_finish()


func _run_cues() -> void:
	last_frame_ops.clear()
	while playing and _cue_index < timeline.cues.size() and float(timeline.cues[_cue_index]["t"]) <= _t:
		var cue: Dictionary = timeline.cues[_cue_index]
		_cue_index += 1
		var t0 := Time.get_ticks_usec()
		_execute(cue)
		last_frame_ops.append("%s:%s(%dus)" % [cue["op"], cue.get("kind", cue.get("clip", cue.get("name", cue.get("shot", "")))), Time.get_ticks_usec() - t0])


func _execute(cue: Dictionary) -> void:
	var who: String = cue.get("who", "a")
	var rig: CharacterRig = _fighters.get(who)
	match cue["op"]:
		"anim":
			rig.play(StringName(cue["clip"]), float(cue.get("blend", 0.1)), float(cue.get("speed", 1.0)))
		"horse":
			rig.play_horse(StringName(cue["clip"]))
		"move":
			_moves[who] = {"from": rig.position, "to": Vector3(float(cue["to"]), 0, 0), "start": _t,
				"dur": float(cue["dur"]), "arc": float(cue.get("arc", 0.0)), "ease": cue.get("ease", "inout")}
			_turn_toward(who, _other_position(who), 0.12)
		"place":
			rig.position = Vector3(float(cue["x"]), 0, 0)
			_moves.erase(who)
			_face_instant(who)
		"face":
			var target := _other_position(who)
			if cue.get("toward", "") == "camera":
				target = camera.global_position
				target = to_local(target)
			_turn_toward(who, target, float(cue.get("dur", 0.25)))
		"spin":
			_turns[who] = {"from": rig.rotation.y, "to": rig.rotation.y + deg_to_rad(float(cue["deg"])),
				"start": _t, "dur": float(cue["dur"]), "then_face": true}
		"camera":
			camera.set_shot(cue, float(cue.get("blend", 0.0)))
		"vfx":
			_vfx(cue, who)
		"sfx":
			var pitch := 1.0
			if cue.has("who") and String(cue["name"]) in ["grunt", "battle_cry", "death_cry", "victory_cry"]:
				pitch = VOICE_PITCH.get(_types[who], 1.0)
			Audio.play_sfx(cue["name"], 0.0, pitch * randf_range(0.95, 1.05))
		"shake":
			camera.shake(float(cue["amp"]), float(cue["dur"]))
		"timescale":
			_ts = float(cue["value"])
			_ts_remaining = float(cue["dur"])
		"flash":
			flash_requested.emit(float(cue["strength"]) * Settings.flash_scale(), _colors["a"])
		"light":
			arena.set_light_mode(cue["mode"], _colors.get(who, Color.WHITE))
		"title":
			title_requested.emit(cue["key"], cue.get("style", "matchup"), _colors["a"])
		"music":
			Audio.music(cue["cue"])
		"fade":
			_fades[who] = {"start": _t, "dur": float(cue["dur"])}
		"projectile":
			_spawn_projectile(cue)
		"end":
			_finish()


func _vfx(cue: Dictionary, who: String) -> void:
	var kind: String = cue["kind"]
	var color: Color = _colors.get(who, Color.WHITE)
	var at := _anchor(cue.get("at", "mid"))
	match kind:
		"aura_on":
			if not _auras.has(who):
				_auras[who] = vfx.make_aura(color)
		"aura_off":
			if _auras.has(who):
				(_auras[who] as Node).queue_free()
				_auras.erase(who)
		_:
			var facing := _other_position(who) - (_fighters[who] as CharacterRig).position
			vfx.spawn(kind, to_local(at), color, float(cue.get("scale", 1.0)), {"facing": facing})


func _on_anim_event(event_name: StringName, who: String) -> void:
	if not playing:
		return
	match event_name:
		&"step":
			Audio.play_sfx("step", -10.0, randf_range(0.9, 1.1))
		&"hoof":
			Audio.play_sfx("hoof", -6.0, randf_range(0.9, 1.1))
		&"land":
			Audio.play_sfx("land", -2.0)
		&"knee", &"thud":
			Audio.play_sfx("armor_fall", -4.0)


# --------------------------------------------------------------------------
# Motion
# --------------------------------------------------------------------------

func _other_position(who: String) -> Vector3:
	var other: CharacterRig = _fighters.get("d" if who == "a" else "a")
	return other.position if other else Vector3.ZERO


func _face_instant(who: String) -> void:
	var rig: CharacterRig = _fighters[who]
	var d := _other_position(who) - rig.position
	if d.length() > 0.01:
		rig.rotation.y = atan2(d.x, d.z)


func _turn_toward(who: String, target: Vector3, dur: float) -> void:
	var rig: CharacterRig = _fighters[who]
	var d := target - rig.position
	d.y = 0.0
	if d.length() < 0.01:
		return
	var goal := atan2(d.x, d.z)
	var current := rig.rotation.y
	goal = current + wrapf(goal - current, -PI, PI)
	_turns[who] = {"from": current, "to": goal, "start": _t, "dur": maxf(dur, 0.01), "then_face": false}


func _update_motion() -> void:
	for who in _moves.keys():
		var m: Dictionary = _moves[who]
		var rig: CharacterRig = _fighters[who]
		var k := clampf((_t - float(m["start"])) / float(m["dur"]), 0.0, 1.0)
		var e := k
		match m["ease"]:
			"in": e = k * k
			"out": e = 1.0 - (1.0 - k) * (1.0 - k)
			"inout": e = k * k * (3.0 - 2.0 * k)
		var p: Vector3 = (m["from"] as Vector3).lerp(m["to"], e)
		p.y = float(m["arc"]) * 4.0 * k * (1.0 - k)
		rig.position = p
		if k >= 1.0:
			_moves.erase(who)
	for who in _turns.keys():
		var tr: Dictionary = _turns[who]
		var rig: CharacterRig = _fighters[who]
		var k := clampf((_t - float(tr["start"])) / float(tr["dur"]), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		rig.rotation.y = lerpf(float(tr["from"]), float(tr["to"]), k)
		if k >= 1.0:
			_turns.erase(who)
			if tr.get("then_face", false):
				_turn_toward(who, _other_position(who), 0.2)
	for who in _fades.keys():
		var f: Dictionary = _fades[who]
		var k := clampf((_t - float(f["start"])) / float(f["dur"]), 0.0, 1.0)
		(_fighters[who] as CharacterRig).set_fade(k)


func _update_auras() -> void:
	for who in _auras:
		var aura: Node3D = _auras[who]
		if is_instance_valid(aura):
			aura.position = (_fighters[who] as CharacterRig).position


func _spawn_projectile(cue: Dictionary) -> void:
	var who: String = cue["who"]
	var orb := Node3D.new()
	var color: Color = _colors[who]
	var shell := MeshInstance3D.new()
	shell.mesh = MaterialLibrary.sphere(0.22)
	shell.material_override = MaterialLibrary.energy_material(color, 4.0)
	orb.add_child(shell)
	var core := MeshInstance3D.new()
	core.mesh = MaterialLibrary.sphere(0.1)
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(3, 3, 3)
	core.material_override = core_mat
	orb.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.0
	orb.add_child(light)
	add_child(orb)
	_set_layers(orb, BattleArena.LAYER)
	light.light_cull_mask = BattleArena.LAYER
	orb.position = to_local(_anchor(cue["from"]))
	_projectiles.append({"node": orb, "from": orb.position, "to_anchor": cue["to"], "start": _t, "dur": float(cue["dur"])})


func _update_projectiles(_dt: float) -> void:
	var i := 0
	while i < _projectiles.size():
		var p: Dictionary = _projectiles[i]
		var node: Node3D = p["node"]
		var k := clampf((_t - float(p["start"])) / float(p["dur"]), 0.0, 1.0)
		var target := to_local(_anchor(p["to_anchor"]))
		var pos: Vector3 = (p["from"] as Vector3).lerp(target, k)
		pos.y += sin(k * PI) * 0.4
		node.position = pos
		node.rotate_y(0.3)
		if k >= 1.0:
			node.queue_free()
			_projectiles.remove_at(i)
			continue
		i += 1


# --------------------------------------------------------------------------
# Anchors (world space)
# --------------------------------------------------------------------------

func _anchor(name: String) -> Vector3:
	if name.begins_with("camera_front_"):
		var rig: CharacterRig = _fighters.get(name.right(1))
		if rig == null:
			return Vector3.FORWARD
		return rig.global_basis.z.normalized()
	if name == "mid" or name == "mid_ground":
		var a: CharacterRig = _fighters.get("a")
		var d: CharacterRig = _fighters.get("d")
		if a == null or d == null:
			return global_position
		var m := (a.chest_position() + d.chest_position()) * 0.5
		if name == "mid_ground":
			m.y = global_position.y + 0.05
		return m
	var who := name.left(1)
	var part := name.substr(2)
	var rig: CharacterRig = _fighters.get(who)
	if rig == null:
		return global_position
	var other: CharacterRig = _fighters.get("d" if who == "a" else "a")
	var toward := (other.global_position - rig.global_position) if other else Vector3.RIGHT
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.001 else Vector3.RIGHT
	match part:
		"ground":
			return rig.global_position
		"chest":
			return rig.chest_position()
		"head":
			return rig.head_position()
		"tip":
			return rig.weapon_tip()
		"tip_ground":
			var tip := rig.weapon_tip()
			tip.y = global_position.y + 0.05
			return tip
		"hand":
			return (rig.joints["hand_r"] as Node3D).global_position
		"front":
			return rig.chest_position() + toward * 0.7
		"behind":
			return rig.chest_position() - toward * 1.4
	return rig.global_position


# --------------------------------------------------------------------------
# Teardown
# --------------------------------------------------------------------------

func _finish() -> void:
	_cleanup()
	finished.emit()


func _cleanup() -> void:
	playing = false
	set_process(false)
	for who in _fighters:
		var rig: CharacterRig = _fighters[who]
		if is_instance_valid(rig):
			rig.queue_free()
	_fighters.clear()
	for who in _auras:
		if is_instance_valid(_auras[who]):
			(_auras[who] as Node).queue_free()
	_auras.clear()
	for p in _projectiles:
		if is_instance_valid(p["node"]):
			(p["node"] as Node).queue_free()
	_projectiles.clear()
	_moves.clear()
	_turns.clear()
	_fades.clear()
	vfx.clear_all()
	arena.visible = false
	camera.current = false
	Audio.music("board")


# --------------------------------------------------------------------------
# Shader / pipeline pre-warming
# --------------------------------------------------------------------------

var _warm_nodes: Array[Node] = []

## Renders every fighter archetype and effect once (behind a loading fade)
## so their shaders and pipelines compile before the first real battle.
func prewarm_begin() -> void:
	arena.visible = true
	camera.current = true
	camera.global_transform = Transform3D(Basis(), to_global(Vector3(0, 2.2, 9.0))).looking_at(to_global(Vector3(0, 1.0, 0)), Vector3.UP)
	var i := 0
	for type in [Chess.PAWN, Chess.KNIGHT, Chess.BISHOP, Chess.ROOK, Chess.QUEEN, Chess.KING]:
		for color in 2:
			var rig := CharacterRig.new()
			add_child(rig)
			rig.build(type, color)
			_set_layers(rig, BattleArena.LAYER)
			rig.position = Vector3(-5.5 + i, 0, -1.0 + color * 1.5)
			rig.play(&"power_up", 0.0)
			_warm_nodes.append(rig)
			i += 1
	var kinds := ["sparks", "impact", "shockwave", "dust", "slash_arc", "pillar", "pillar_warn", "lightning",
		"magic_burst", "charge", "dissolve", "dash_trail", "afterimage", "golden_wave", "embers"]
	for k in kinds.size():
		vfx.spawn(kinds[k], Vector3(-4.0 + k * 0.6, 1.0, 1.5), Color(1, 0.7, 0.4), 1.0, {})
	for color in [Color(1, 0.8, 0.4), Color(0.8, 0.2, 1.0)]:
		var aura := vfx.make_aura(color)
		aura.position = Vector3(2, 0, 2)
		_warm_nodes.append(aura)
	_spawn_projectile_at(Vector3(0, 1.2, 2), Color(1, 0.8, 0.4))


func prewarm_end() -> void:
	for n in _warm_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_warm_nodes.clear()
	for p in _projectiles:
		if is_instance_valid(p["node"]):
			(p["node"] as Node).queue_free()
	_projectiles.clear()
	vfx.clear_all()
	arena.visible = false
	camera.current = false


func _spawn_projectile_at(pos: Vector3, color: Color) -> void:
	_colors["warm"] = color
	_spawn_projectile({"who": "warm", "from": "warm_ground", "to": "warm_ground", "dur": 0.5})
	if not _projectiles.is_empty():
		(_projectiles[-1]["node"] as Node3D).position = pos

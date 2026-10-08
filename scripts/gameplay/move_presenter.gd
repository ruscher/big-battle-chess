class_name MovePresenter
extends Node
## Plays a committed ChessMoveRecord on the board: walking, galloping,
## castling, captures (board strike or arena battle), promotion and the
## checkmate scene.
##
## The logical position is already final when presentation starts, and every
## path ends with BoardView.sync_to_position(), so skipping, speeding up or
## interrupting can never duplicate or lose pieces.

signal battle_started
signal battle_finished

const WALK_SPEED := 1.5     # squares per second
const RUN_SPEED := 3.2

var board: BoardView
var board_camera: BoardCamera
var director: BattleDirector
var overlay: CinematicOverlay
var board_vfx: CombatVFX
var cinematic_mode: int = CinematicMode.Mode.DYNAMIC
var board_theme: int = 0
var busy: bool = false

var _skip: bool = false


func skip() -> void:
	_skip = true
	if director and director.playing:
		director.skip()


func present(record: ChessMoveRecord, position_after: ChessPosition) -> void:
	busy = true
	_skip = false
	if cinematic_mode == CinematicMode.Mode.SKIP:
		_finalize(record, position_after)
		if record.is_capture():
			Audio.play_sfx("capture_quick", -4.0)
		busy = false
		return
	var mover := board.detach_rig(record.from_square)
	if mover == null:
		_finalize(record, position_after)
		busy = false
		return
	var victim: CharacterRig = board.detach_rig(record.captured_square) if record.is_capture() else null
	var rook: CharacterRig = board.detach_rig(record.rook_from) if record.is_castle else null

	var from := BoardView.square_to_local(record.from_square)
	var to := BoardView.square_to_local(record.to_square)
	if victim != null:
		var target := BoardView.square_to_local(record.captured_square)
		var dir := (target - from).normalized() if (target - from).length() > 0.01 else Vector3.FORWARD
		var stop := target - dir * 0.62
		if record.is_en_passant:
			stop = to - (target - to).normalized() * 0.1
		await _travel(mover, from, stop, record.piece_type)
		_face(mover, victim.position)
		_face(victim, mover.position)
		if CinematicMode.uses_arena(cinematic_mode) and not _skip:
			await _arena_battle(record, mover, victim)
		elif not _skip:
			await _board_strike(mover, victim, record.piece_type)
		if is_instance_valid(victim):
			victim.queue_free()
		if not _skip:
			await _travel(mover, mover.position, to, record.piece_type)
	else:
		if rook != null:
			var rook_to := BoardView.square_to_local(record.rook_to)
			_travel(rook, rook.position, rook_to, Chess.ROOK)
		await _travel(mover, from, to, record.piece_type)
		Audio.play_sfx("piece_place", -6.0, randf_range(0.95, 1.05))

	if record.promotion_type != Chess.EMPTY and not _skip:
		await _promotion(mover, record)
	if is_instance_valid(mover):
		mover.set_meta("piece", Chess.make_piece(record.piece_type, record.color))
		board.place_rig(mover, record.to_square)
	if rook != null and is_instance_valid(rook):
		board.place_rig(rook, record.rook_to)
	_finalize(record, position_after)
	if record.is_checkmate and not _skip:
		await _checkmate_scene(record, position_after)
	busy = false


func _finalize(record: ChessMoveRecord, position_after: ChessPosition) -> void:
	board.sync_to_position(position_after)
	if record.gives_check and not record.is_checkmate:
		Audio.play_sfx("check", -6.0)


func _face(rig: CharacterRig, target: Vector3) -> void:
	var d := target - rig.position
	if d.length() > 0.01:
		rig.rotation.y = atan2(d.x, d.z)


# --------------------------------------------------------------------------
# Locomotion
# --------------------------------------------------------------------------

func _travel(rig: CharacterRig, from: Vector3, to: Vector3, piece_type: int) -> void:
	var dist := from.distance_to(to)
	if dist < 0.02:
		return
	var speed_mult := float(Settings.get_value("gameplay", "cinematic_speed"))
	var running := dist > 2.5 * BoardView.CELL or piece_type == Chess.KNIGHT
	var speed := (RUN_SPEED if running else WALK_SPEED) * speed_mult
	var duration := dist / speed
	var face_dir := to - from
	rig.rotation.y = atan2(face_dir.x, face_dir.z)
	rig.play(&"run" if running else &"walk", 0.15, speed_mult)
	var tw := rig.create_tween()
	if piece_type == Chess.KNIGHT:
		# The warhorse leaps over anything in its way.
		tw.tween_method(func(k: float) -> void:
			rig.position = from.lerp(to, k) + Vector3.UP * sin(k * PI) * minf(1.0, dist * 0.35), 0.0, 1.0, duration)
	else:
		tw.tween_property(rig, "position", to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait_tween(tw)
	rig.position = to
	rig.play(&"idle", 0.25)
	var color := Chess.piece_color(int(rig.get_meta("piece")))
	var goal := BoardView.facing_yaw(color, board.view_yaw())
	goal = rig.rotation.y + wrapf(goal - rig.rotation.y, -PI, PI)
	var tw2 := rig.create_tween()
	tw2.tween_property(rig, "rotation:y", goal, 0.3)
	if not _skip:
		await _wait_tween(tw2)


func _wait_tween(tw: Tween) -> void:
	while tw.is_valid() and tw.is_running():
		if _skip:
			tw.custom_step(1000.0)
			tw.kill()
			return
		await get_tree().process_frame


func _sleep(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		if not get_tree().paused:
			left -= get_process_delta_time()


# --------------------------------------------------------------------------
# Captures
# --------------------------------------------------------------------------

func _board_strike(attacker: CharacterRig, victim: CharacterRig, attacker_type: int) -> void:
	var attacks: Array = CombatProfile.get_profile(attacker_type)["attacks"]
	var clip: String = attacks[0]
	if clip == "cast":
		clip = "overhead"
	var hit := CombatProfile.clip_event(clip, "hit")
	attacker.play(StringName(clip), 0.1)
	Audio.play_sfx("whoosh", -6.0)
	await _sleep(maxf(0.05, hit))
	Audio.play_sfx("capture_quick", -2.0)
	board_vfx.spawn("sparks", attacker.weapon_tip(), Color(1, 0.85, 0.5), 0.35)
	victim.play(&"death", 0.05)
	await _sleep(0.9)
	var tw := victim.create_tween()
	tw.tween_method(victim.set_fade, 0.0, 1.0, 0.5)
	await _wait_tween(tw)
	attacker.play(&"idle", 0.3)


func _arena_battle(record: ChessMoveRecord, attacker: CharacterRig, victim: CharacterRig) -> void:
	battle_started.emit()
	var request := {
		"attacker_type": record.piece_type, "attacker_color": record.color,
		"defender_type": record.captured_type, "defender_color": record.color ^ 1,
		"mode": cinematic_mode, "seed": record.presentation_seed(), "board_theme": board_theme,
		"en_passant": record.is_en_passant,
	}
	# Dive into the square, then cut to the arena.
	board_camera.set_framing(30.0, 4.5, (attacker.position + victim.position) * 0.5 + Vector3.UP * 0.4)
	Audio.play_sfx("draw_weapon", -4.0)
	await _sleep(0.45)
	await overlay.fade(1.0, 0.25, Color(0.02, 0.01, 0.02))
	director.play(request)
	await overlay.fade(0.0, 0.35)
	if director.playing:
		await director.finished
	await overlay.fade(1.0, 0.25, Color(0.02, 0.01, 0.02))
	board_camera.current = true
	board_camera.reset_view(Chess.WHITE if board_camera.is_white_view() else Chess.BLACK)
	await overlay.fade(0.0, 0.35)
	battle_finished.emit()


func _promotion(rig: CharacterRig, record: ChessMoveRecord) -> void:
	overlay.show_title("TITLE_HEROIC_PROMOTION", "matchup", FactionStyle.get_style(record.color)["energy"])
	Audio.play_sfx("promotion")
	var at := board.square_to_world(record.to_square)
	board_vfx.spawn("pillar", board_vfx.to_local(at), FactionStyle.get_style(record.color)["energy"], 0.35)
	rig.play(&"power_up", 0.1)
	await _sleep(0.9)
	var tw := rig.create_tween()
	tw.tween_method(rig.set_fade, 0.0, 1.0, 0.3)
	await _wait_tween(tw)


func _checkmate_scene(record: ChessMoveRecord, pos: ChessPosition) -> void:
	var loser := pos.side
	var king_sq := pos.king_square[loser]
	var king := board.rig_at(king_sq)
	var hero := board.rig_at(record.to_square)
	if king == null:
		return
	board_camera.set_framing(24.0, 4.2, king.position + Vector3.UP * 0.3)
	Audio.play_sfx("checkmate")
	Audio.music("victory")
	overlay.show_title("TITLE_CHECKMATE", "finisher", FactionStyle.get_style(record.color)["energy"])
	if hero:
		hero.play(&"victory", 0.2)
	await _sleep(0.6)
	king.play(&"surrender", 0.3)
	board_vfx.spawn("dust", board_vfx.to_local(king.global_position), Color.WHITE, 0.25)
	await _sleep(3.2)

extends Node
## Composition root. Builds the 3D world (hall, board, battle stage), the
## gameplay services (session, AI, presenter) and the UI, then routes between
## the title screen and matches.
##
## Command-line options (after "--"), used for automated checks and capture:
##   --autostart=pve|pvp|ai_vs_ai   start a match immediately
##   --cinematic=epic|dynamic|quick|classic|skip   --ai-level=0..5
##   --demo-battle=<attacker>,<defender>[,<mode>]  play one arena battle
##   --shots=<s1>,<s2>,...  --shot-dir=<dir>      timed screenshots
##   --quit-after=<seconds>                         exit automatically
##   --fen=<FEN>                                    custom start position

const BATTLE_STAGE_POSITION := Vector3(0, 0, 3000)

var world: Node3D
var world_env: WorldEnvironment
var hall: HallEnvironment
var board: BoardView
var board_camera: BoardCamera
var director: BattleDirector
var board_vfx: CombatVFX
var presenter: MovePresenter
var session: GameSession
var ai: ChessAIPlayer
var main_menu: MainMenu
var hud: Hud
var dialogs: GameDialogs
var overlay: CinematicOverlay

## True once startup (shader prewarm, title screen) has finished.
var booted: bool = false
var _in_game: bool = false
var _ui_root: Control
var _cli: Dictionary = {}
var _env_index: int = -1
var _elapsed: float = 0.0
var _shots: Array[float] = []
var _shot_index: int = 0
var _frame_count: int = 0
var _worst_frame_ms: float = 0.0


func _ready() -> void:
	InputSetup.register()
	_parse_cli()
	if _cli.has("procedural-characters"):
		CharacterLibrary.set_enabled(false)
	_build_world()
	_build_logic()
	_build_ui()
	Settings.changed.connect(_on_settings_changed)
	_set_environment(int(Settings.get_value("gameplay", "environment")))
	board.apply_theme(int(Settings.get_value("gameplay", "board_theme")))
	_apply_graphics()
	await _prewarm()
	_show_menu(true)
	booted = true
	_run_cli()


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world.add_child(world_env)
	hall = HallEnvironment.new()
	hall.name = "Hall"
	world.add_child(hall)
	board = BoardView.new()
	board.name = "Board"
	world.add_child(board)
	board_camera = BoardCamera.new()
	board_camera.name = "BoardCamera"
	board_camera.cull_mask = 1
	world.add_child(board_camera)
	board_camera.current = true
	board.camera = board_camera
	board_vfx = CombatVFX.new()
	board_vfx.name = "BoardVFX"
	board_vfx.visual_layer = 1
	world.add_child(board_vfx)
	director = BattleDirector.new()
	director.name = "BattleStage"
	director.position = BATTLE_STAGE_POSITION
	add_child(director)


func _build_logic() -> void:
	ai = ChessAIPlayer.new()
	ai.name = "AI"
	add_child(ai)
	presenter = MovePresenter.new()
	presenter.name = "MovePresenter"
	add_child(presenter)
	session = GameSession.new()
	session.name = "GameSession"
	add_child(session)
	presenter.board = board
	presenter.board_camera = board_camera
	presenter.director = director
	presenter.board_vfx = board_vfx
	session.wire(board, board_camera, presenter, ai)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	layer.add_child(root)
	_ui_root = root

	hud = Hud.new()
	hud.name = "HUD"
	root.add_child(hud)
	hud.bind(session)
	hud.visible = false
	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	root.add_child(main_menu)
	overlay = CinematicOverlay.new()
	overlay.name = "CinematicOverlay"
	root.add_child(overlay)
	dialogs = GameDialogs.new()
	dialogs.name = "Dialogs"
	dialogs.session = session
	root.add_child(dialogs)
	presenter.overlay = overlay

	main_menu.start_requested.connect(_start_game)
	main_menu.continue_requested.connect(func() -> void: _load_game(SaveSystem.AUTOSAVE))
	main_menu.load_requested.connect(_load_game)
	main_menu.replay_requested.connect(_start_replay)
	main_menu.quit_requested.connect(_quit)
	main_menu.preview_changed.connect(func(theme_index: int, env_index: int) -> void:
		board.apply_theme(theme_index)
		_set_environment(env_index))

	hud.pause_requested.connect(_pause)
	dialogs.resume_requested.connect(_resume)
	dialogs.main_menu_requested.connect(func() -> void:
		_resume()
		_show_menu())
	dialogs.quit_requested.connect(_quit)
	dialogs.rematch_requested.connect(func() -> void:
		var c := GameConfig.from_dict(session.config.to_dict())
		if c.opponent == GameConfig.Opponent.AI:
			c.human_color = c.human_color
		_start_game(c))
	dialogs.save_requested.connect(func(slot: String) -> void:
		dialogs.toast(tr("MSG_SAVED") if session.save_to_slot(slot) else tr("MSG_SAVE_FAILED")))
	dialogs.promotion_chosen.connect(session.choose_promotion)
	dialogs.promotion_cancelled.connect(session.cancel_promotion)
	dialogs.draw_answered.connect(session.answer_draw)

	session.promotion_requested.connect(dialogs.show_promotion)
	session.draw_offer_received.connect(dialogs.show_draw_offer)
	session.notify.connect(dialogs.toast)
	session.game_finished.connect(func(_r: ChessMatch.Result, _reason: ChessMatch.Reason) -> void:
		await get_tree().create_timer(0.8).timeout
		if _in_game and session.state == GameSession.State.GAME_OVER:
			dialogs.show_game_over(session.match_data, session.config))
	session.battle_active.connect(func(active: bool) -> void:
		hud.set_battle_mode(active)
		overlay.letterbox(active))
	director.title_requested.connect(overlay.show_title)
	director.flash_requested.connect(overlay.flash)


# --------------------------------------------------------------------------
# Flow
# --------------------------------------------------------------------------

## Compiles battle shaders behind a black screen before the title appears.
func _prewarm() -> void:
	overlay.fade(1.0, 0.0)
	main_menu.visible = false
	hud.visible = false
	var splash: IntroSplash = null
	if _wants_intro():
		splash = IntroSplash.new()
		_ui_root.add_child(splash)
	director.prewarm_begin()
	for i in 6:
		await get_tree().process_frame
	director.prewarm_end()
	board_camera.current = true
	await get_tree().process_frame
	if splash != null and is_instance_valid(splash):
		await splash.finished


func _wants_intro() -> bool:
	if _cli.has("intro"):
		return true
	if DisplayServer.get_name() == "headless":
		return false
	for key in ["no-intro", "autostart", "demo-battle", "shots", "quit-after"]:
		if _cli.has(key):
			return false
	return true


func _show_menu(instant: bool = false) -> void:
	_in_game = false
	session.end_session()
	dialogs.close()
	hud.visible = false
	main_menu.visible = true
	main_menu.refresh()
	board.sync_to_position(ChessPosition.new())
	board.clear_marks()
	board.flipped_view = false
	board_camera.user_control = false
	board_camera.auto_orbit = 4.0
	board_camera.set_framing(26.0, 15.0, Vector3(1.5, 0.6, 0), instant)
	Audio.music("menu")
	Audio.ambience(true)
	overlay.fade(0.0, 0.1 if instant else 0.5)


func _start_game(config: GameConfig) -> void:
	if not _cli.get("fen", "").is_empty():
		config.start_fen = _cli["fen"]
	await overlay.fade(1.0, 0.35)
	_enter_game(config.board_theme, config.environment)
	session.start_new(config)
	await overlay.fade(0.0, 0.6)


func _load_game(slot: String) -> void:
	var data := SaveSystem.load_game(slot)
	if data.is_empty():
		dialogs.toast(tr("MSG_LOAD_FAILED"))
		Audio.ui("error")
		return
	var config: GameConfig = data["config"]
	await overlay.fade(1.0, 0.35)
	_enter_game(config.board_theme, config.environment)
	session.start_from_save(data)
	await overlay.fade(0.0, 0.6)
	dialogs.toast(tr("MSG_LOADED"))


func _start_replay(path: String) -> void:
	var m := ChessMatch.from_pgn(FileAccess.get_file_as_string(path))
	if m == null:
		dialogs.toast(tr("MSG_LOAD_FAILED"))
		return
	await overlay.fade(1.0, 0.35)
	_enter_game(int(Settings.get_value("gameplay", "board_theme")), int(Settings.get_value("gameplay", "environment")))
	session.start_replay(m)
	await overlay.fade(0.0, 0.6)


func _enter_game(theme_index: int, env_index: int) -> void:
	_in_game = true
	main_menu.visible = false
	hud.visible = true
	hud.modulate.a = 1.0
	board_camera.auto_orbit = 0.0
	board_camera.user_control = true
	board.apply_theme(theme_index)
	_set_environment(env_index)


func _pause() -> void:
	if not _in_game or get_tree().paused:
		return
	get_tree().paused = true
	dialogs.show_pause()


func _resume() -> void:
	get_tree().paused = false
	dialogs.close()


func _quit() -> void:
	session.end_session()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not _in_game:
		return
	if session.state == GameSession.State.PRESENTING and not director.playing:
		if event.is_action_pressed("skip_cinematic"):
			presenter.skip()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause_menu"):
		if get_tree().paused:
			if not dialogs.is_open() or true:
				_resume()
		elif not director.playing and not dialogs.is_open():
			_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("undo_move") and not get_tree().paused:
		session.undo()
	elif event.is_action_pressed("camera_reset"):
		board_camera.reset_view(Chess.WHITE if board_camera.is_white_view() else Chess.BLACK)
	elif event.is_action_pressed("toggle_hud") and not director.playing:
		hud.visible = not hud.visible


# --------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------

func _set_environment(index: int) -> void:
	var idx := clampi(index, 0, HallEnvironment.count() - 1)
	if idx == _env_index:
		return
	_env_index = idx
	hall.build(idx, world_env)
	_apply_graphics()


func _apply_graphics() -> void:
	var preset := int(Settings.get_value("graphics", "preset"))
	var scale := float(Settings.get_value("graphics", "render_scale"))
	var fsr: bool = Settings.get_value("graphics", "fsr")
	if world_env.environment:
		GraphicsQuality.apply(world_env.environment, get_viewport(), preset, scale, fsr)
	GraphicsQuality.apply(director.arena.environment, get_viewport(), preset, scale, fsr)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics":
		_apply_graphics()
	elif section == "gameplay":
		if session.match_data != null:
			session.refresh_requested.emit()
			session._refresh_marks()


# --------------------------------------------------------------------------
# Command line automation (tests, captures, demos)
# --------------------------------------------------------------------------

func _parse_cli() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_cli[kv[0]] = kv[1]
		elif a.begins_with("--"):
			_cli[a.substr(2)] = "true"
	if _cli.has("shots"):
		for s in str(_cli["shots"]).split(","):
			_shots.append(float(s))


func _run_cli() -> void:
	var modes := {"epic": 0, "dynamic": 1, "quick": 2, "classic": 3, "skip": 4}
	if _cli.has("resolution"):
		var wh := str(_cli["resolution"]).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	if _cli.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if _cli.has("preset"):
		Settings.set_override("graphics", "preset", int(_cli["preset"]))
	if _cli.has("cinematic"):
		Settings.set_override("gameplay", "cinematic_mode", modes.get(_cli["cinematic"], 1))
	if _cli.has("autostart"):
		var c := GameConfig.from_settings()
		c.opponent = {"pve": GameConfig.Opponent.AI, "pvp": GameConfig.Opponent.LOCAL_PLAYER,
			"ai_vs_ai": GameConfig.Opponent.AI_VS_AI}.get(_cli["autostart"], GameConfig.Opponent.AI)
		if _cli.has("ai-level"):
			c.ai_level = int(_cli["ai-level"])
		if _cli.has("board"):
			c.board_theme = int(_cli["board"])
		if _cli.has("env"):
			c.environment = int(_cli["env"])
		await _start_game(c)
		if _cli.has("clicks"):
			for sq in str(_cli["clicks"]).split(","):
				while session.state != GameSession.State.AWAIT_HUMAN:
					await get_tree().process_frame
				await get_tree().create_timer(0.4).timeout
				session._on_square_clicked(Chess.parse_square(sq))
	elif _cli.has("demo-battle"):
		_demo_battle(str(_cli["demo-battle"]))


func _demo_battle(spec: String) -> void:
	var names := {"pawn": Chess.PAWN, "knight": Chess.KNIGHT, "bishop": Chess.BISHOP, "rook": Chess.ROOK, "queen": Chess.QUEEN, "king": Chess.KING}
	var parts := spec.split(",")
	var modes := {"epic": 0, "dynamic": 1, "quick": 2}
	main_menu.visible = false
	var request := {
		"attacker_type": names.get(parts[0], Chess.KNIGHT), "attacker_color": int(_cli.get("attacker-color", "0")),
		"defender_type": names.get(parts[1] if parts.size() > 1 else "pawn", Chess.PAWN), "defender_color": 1 - int(_cli.get("attacker-color", "0")),
		"mode": modes.get(parts[2] if parts.size() > 2 else "dynamic", 1), "seed": int(_cli.get("seed", "7")),
		"board_theme": int(Settings.get_value("gameplay", "board_theme")),
	}
	overlay.letterbox(true)
	director.play(request)
	await director.finished
	overlay.letterbox(false)
	board_camera.current = true
	_show_menu()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 2.0:
		_frame_count += 1
		_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
		if _cli.has("log-hitches") and delta > 0.03:
			print("[hitch] t=%.2f %.1f ms %s" % [_elapsed, delta * 1000.0, director.last_frame_ops])
	if _shot_index < _shots.size() and _elapsed >= _shots[_shot_index]:
		var dir: String = _cli.get("shot-dir", "user://shots")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("shot_%02d.png" % _shot_index)
		get_viewport().get_texture().get_image().save_png(path)
		print("[capture] ", path)
		_shot_index += 1
	if _cli.has("quit-after") and _elapsed >= float(_cli["quit-after"]):
		print("[auto] quitting after %.1f s; state=%s plies=%s avg_fps=%.1f worst_frame=%.1f ms vram=%.0f MB" % [_elapsed,
			GameSession.State.keys()[session.state], session.match_data.records.size() if session.match_data else 0,
			_frame_count / maxf(0.001, _elapsed - 2.0), _worst_frame_ms,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		print("[auto] retarget %.2f ms/frame" % (SkinnedCharacterRig.retarget_usec / 1000.0 / maxf(1.0, float(Engine.get_process_frames()))))
		if session.match_data:
			print("[auto] PGN:\n", session.match_data.to_pgn())
		get_tree().quit()


func _exit_tree() -> void:
	session.end_session()
	MaterialLibrary.clear_caches()
	CombatVFX.clear_cache()
	UiTheme.clear_cache()

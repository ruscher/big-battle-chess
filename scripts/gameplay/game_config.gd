class_name GameConfig
extends RefCounted
## Everything chosen before a match starts. Serializable for saves.

enum Opponent { LOCAL_PLAYER, AI, AI_VS_AI }

var opponent: Opponent = Opponent.AI
var human_color: int = Chess.WHITE
var ai_level: int = ChessAIPlayer.Level.INTERMEDIATE
var cinematic_mode: int = CinematicMode.Mode.DYNAMIC
var board_theme: int = 0
var environment: int = 0
var clock_minutes: float = 0.0
var clock_increment: float = 0.0
var white_name: String = ""
var black_name: String = ""
var start_fen: String = Chess.START_FEN


func is_ai_color(color: int) -> bool:
	if opponent == Opponent.AI_VS_AI:
		return true
	return opponent == Opponent.AI and color != human_color


func allows_undo() -> bool:
	return true


static func from_settings() -> GameConfig:
	var c := GameConfig.new()
	c.cinematic_mode = int(Settings.get_value("gameplay", "cinematic_mode"))
	c.board_theme = int(Settings.get_value("gameplay", "board_theme"))
	c.environment = int(Settings.get_value("gameplay", "environment"))
	c.ai_level = int(Settings.get_value("gameplay", "ai_level"))
	c.clock_minutes = float(Settings.get_value("gameplay", "clock_minutes"))
	c.clock_increment = float(Settings.get_value("gameplay", "clock_increment"))
	c.human_color = int(Settings.get_value("gameplay", "human_color"))
	return c


func to_dict() -> Dictionary:
	return {
		"opponent": int(opponent), "human_color": human_color, "ai_level": ai_level,
		"cinematic_mode": cinematic_mode, "board_theme": board_theme, "environment": environment,
		"clock_minutes": clock_minutes, "clock_increment": clock_increment,
		"white_name": white_name, "black_name": black_name, "start_fen": start_fen,
	}


static func from_dict(d: Dictionary) -> GameConfig:
	var c := GameConfig.new()
	c.opponent = clampi(int(d.get("opponent", 1)), 0, 2) as Opponent
	c.human_color = clampi(int(d.get("human_color", 0)), 0, 1)
	c.ai_level = clampi(int(d.get("ai_level", 2)), 0, ChessAIPlayer.Level.GRANDMASTER)
	c.cinematic_mode = clampi(int(d.get("cinematic_mode", 1)), 0, CinematicMode.Mode.SKIP)
	c.board_theme = clampi(int(d.get("board_theme", 0)), 0, BoardTheme.count() - 1)
	c.environment = maxi(0, int(d.get("environment", 0)))
	c.clock_minutes = maxf(0.0, float(d.get("clock_minutes", 0.0)))
	c.clock_increment = maxf(0.0, float(d.get("clock_increment", 0.0)))
	c.white_name = str(d.get("white_name", ""))
	c.black_name = str(d.get("black_name", ""))
	c.start_fen = str(d.get("start_fen", Chess.START_FEN))
	return c

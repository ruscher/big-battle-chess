class_name IntroSplash
extends Control
## Opening splash with the official animated Big Battle Chess logo. Plays
## while battle shaders pre-warm; any key, click or gamepad button skips it.

signal finished

const VIDEO := "res://assets/branding/logo_intro.ogv"
const LOGO := "res://assets/branding/logo.png"

var _done: bool = false
var _started_ms: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var height := get_viewport_rect().size.y * 0.62
	if ResourceLoader.exists(VIDEO):
		var player := VideoStreamPlayer.new()
		player.stream = load(VIDEO)
		player.expand = true
		player.custom_minimum_size = Vector2(height * 16.0 / 9.0, height)
		player.finished.connect(_finish)
		center.add_child(player)
		player.play()
	elif ResourceLoader.exists(LOGO):
		var logo := TextureRect.new()
		logo.texture = load(LOGO)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(height * 1408.0 / 768.0, height)
		center.add_child(logo)
		get_tree().create_timer(2.0).timeout.connect(_finish)
	else:
		_finish.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
	_started_ms = Time.get_ticks_msec()


func _input(event: InputEvent) -> void:
	if _done:
		return
	# Ignore the burst of focus/resize events at window creation.
	if Time.get_ticks_msec() - _started_ms < 600:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.is_pressed() and not event.is_echo()
	elif event is InputEventMouseButton:
		pressed = event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventJoypadButton:
		pressed = event.is_pressed()
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	await tw.finished
	finished.emit()
	queue_free()

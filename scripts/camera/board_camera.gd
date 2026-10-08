class_name BoardCamera
extends Camera3D
## Smoothed orbit camera for the board. Mouse (right/middle drag, wheel),
## keyboard (Q/E, R/F, +/-) and gamepad (right stick, triggers) are all
## supported through input actions.

const MIN_DISTANCE := 5.5
const MAX_DISTANCE := 19.0
const MIN_PITCH := 18.0
const MAX_PITCH := 86.0

var target := Vector3(0, 0.2, 0)
var yaw: float = 0.0
var pitch: float = 50.0
var distance: float = 10.8
var user_control: bool = true
## Degrees per second of automatic orbit (main menu backdrop).
var auto_orbit: float = 0.0
## Shifts the look-at point toward the viewer so the near ranks clear the HUD.
var lead: float = 1.1
var _lead_goal: float = 1.1

var _yaw_goal: float = 0.0
var _pitch_goal: float = 50.0
var _distance_goal: float = 10.8
var _target_goal := Vector3(0, 0.2, 0)
var _dragging: bool = false


func _ready() -> void:
	fov = 40.0
	near = 0.05
	far = 400.0
	_apply(1.0)


## Turns the view to `color`'s side of the board.
func face_side(color: int, instant: bool = false) -> void:
	var goal := 0.0 if color == Chess.WHITE else 180.0
	# Take the shortest way around.
	var diff := wrapf(goal - _yaw_goal, -180.0, 180.0)
	_yaw_goal += diff
	if instant:
		yaw = _yaw_goal


func reset_view(color: int) -> void:
	_lead_goal = 1.1
	_pitch_goal = 50.0
	_distance_goal = 11.2
	_target_goal = Vector3(0, 0.2, 0)
	face_side(color)


func set_framing(new_pitch: float, new_distance: float, new_target: Vector3, instant: bool = false) -> void:
	_lead_goal = 0.0
	_pitch_goal = new_pitch
	_distance_goal = new_distance
	_target_goal = new_target
	if instant:
		pitch = new_pitch
		distance = new_distance
		target = new_target


func is_white_view() -> bool:
	return absf(wrapf(yaw, -180.0, 180.0)) < 90.0


func _unhandled_input(event: InputEvent) -> void:
	if not user_control or not current:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance_goal = clampf(_distance_goal * 0.9, MIN_DISTANCE, MAX_DISTANCE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance_goal = clampf(_distance_goal * 1.1, MIN_DISTANCE, MAX_DISTANCE)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw_goal -= mm.relative.x * 0.3
		_pitch_goal = clampf(_pitch_goal + mm.relative.y * 0.25, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	if user_control and current:
		var turn := Input.get_axis("camera_rotate_left", "camera_rotate_right")
		var tilt := Input.get_axis("camera_tilt_up", "camera_tilt_down")
		var zoom := Input.get_axis("camera_zoom_in", "camera_zoom_out")
		_yaw_goal += turn * 90.0 * delta
		_pitch_goal = clampf(_pitch_goal + tilt * 50.0 * delta, MIN_PITCH, MAX_PITCH)
		_distance_goal = clampf(_distance_goal * (1.0 + zoom * 1.2 * delta), MIN_DISTANCE, MAX_DISTANCE)
	if auto_orbit != 0.0:
		_yaw_goal += auto_orbit * delta
	_apply(1.0 - exp(-delta * 7.0))


func _apply(weight: float) -> void:
	yaw = lerpf(yaw, _yaw_goal, weight)
	pitch = lerpf(pitch, _pitch_goal, weight)
	distance = lerpf(distance, _distance_goal, weight)
	target = target.lerp(_target_goal, weight)
	lead = lerpf(lead, _lead_goal, weight)
	var yr := deg_to_rad(yaw)
	global_transform = orbit_transform(yaw, pitch, distance, target + Vector3(sin(yr), 0.0, cos(yr)) * lead)


static func orbit_transform(y: float, p: float, d: float, center: Vector3) -> Transform3D:
	var yr := deg_to_rad(y)
	var pr := deg_to_rad(p)
	var offset := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * d
	var t := Transform3D(Basis(), center + offset)
	return t.looking_at(center, Vector3.UP)

class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup (keyboard, mouse, gamepad).
## Done in code so bindings stay readable and reviewable in one place.

const ACTIONS := {
	"board_cursor_up": [KEY_UP, JOY_BUTTON_DPAD_UP, [JOY_AXIS_LEFT_Y, -1.0]],
	"board_cursor_down": [KEY_DOWN, JOY_BUTTON_DPAD_DOWN, [JOY_AXIS_LEFT_Y, 1.0]],
	"board_cursor_left": [KEY_LEFT, JOY_BUTTON_DPAD_LEFT, [JOY_AXIS_LEFT_X, -1.0]],
	"board_cursor_right": [KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, [JOY_AXIS_LEFT_X, 1.0]],
	"board_select": [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER, JOY_BUTTON_A],
	"board_cancel": [KEY_BACKSPACE, JOY_BUTTON_B],
	"camera_rotate_left": [KEY_Q, [JOY_AXIS_RIGHT_X, -1.0]],
	"camera_rotate_right": [KEY_E, [JOY_AXIS_RIGHT_X, 1.0]],
	"camera_tilt_up": [KEY_R, [JOY_AXIS_RIGHT_Y, -1.0]],
	"camera_tilt_down": [KEY_F, [JOY_AXIS_RIGHT_Y, 1.0]],
	"camera_zoom_in": [KEY_EQUAL, KEY_KP_ADD, [JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"camera_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT, [JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"camera_reset": [KEY_C, JOY_BUTTON_RIGHT_STICK],
	"pause_menu": [KEY_ESCAPE, JOY_BUTTON_START],
	"skip_cinematic": [KEY_SPACE, KEY_ENTER, KEY_ESCAPE, JOY_BUTTON_A, JOY_BUTTON_B],
	"speed_cinematic": [KEY_SHIFT, KEY_TAB, JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"undo_move": [KEY_U, JOY_BUTTON_BACK],
	"toggle_hud": [KEY_H, JOY_BUTTON_LEFT_STICK],
}

const DEADZONE := 0.45


static func register() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		InputMap.action_erase_events(action)
		for binding: Variant in ACTIONS[action]:
			InputMap.action_add_event(action, _make_event(action, binding))


static func _make_event(action: String, binding: Variant) -> InputEvent:
	if binding is Array:
		var motion := InputEventJoypadMotion.new()
		motion.axis = binding[0]
		motion.axis_value = binding[1]
		return motion
	var code := int(binding)
	# Key and joypad-button constants overlap numerically; joypad buttons are
	# all small (< 32) while key codes are >= 32.
	if code < 32:
		var button := InputEventJoypadButton.new()
		button.button_index = code
		return button
	var key := InputEventKey.new()
	key.physical_keycode = code
	return key

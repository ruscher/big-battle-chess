class_name PoseAnimator
extends Node
## Keyframe animator for procedural rigs (CharacterRig / HorseRig).
##
## A clip is a list of keyframes, each pointing at a named pose (joint ->
## Euler degrees, plus optional "offset" for the hips/body translation).
## Segments are eased, clips cross-fade from whatever pose is currently
## displayed, and timed events ("hit", "step", ...) are emitted so audio,
## VFX and camera stay locked to the animation instead of separate timers.
##
## `time_scale` lets the battle director apply slow motion / speed ramps.

signal event_triggered(event_name: StringName)
signal clip_finished(clip_name: StringName)

var joints: Dictionary = {}          # String -> Node3D
var rest_offsets: Dictionary = {}    # String -> Vector3 (rest position)
var library: Dictionary = {}         # poses
var clips: Dictionary = {}           # clips
var time_scale: float = 1.0
## Procedural breathing / sway amount (0 disables).
var breathing: float = 1.0
## Joints forced to a fixed rotation regardless of the clip (e.g. a mounted
## rider's legs). Same key format as poses.
var overrides: Dictionary = {}
var current_clip: StringName = &""

var _keys: Array = []
var _events: Array = []
var _loop: bool = false
var _length: float = 0.0
var _time: float = 0.0
var _blend_from: Dictionary = {}
var _blend_time: float = 0.0
var _blend_elapsed: float = 0.0
var _fired: Dictionary = {}
var _phase: float = 0.0
var _playing: bool = false


func setup(joint_map: Dictionary, pose_library: Dictionary, clip_library: Dictionary) -> void:
	joints = joint_map
	library = pose_library
	clips = clip_library
	for name in joints:
		rest_offsets[name] = (joints[name] as Node3D).position
	_phase = randf() * TAU


## Plays `clip_name`, cross-fading over `blend` seconds. `speed` multiplies
## the clip's own timing (independent of time_scale).
func play(clip_name: StringName, blend: float = 0.15, speed: float = 1.0) -> void:
	var clip: Dictionary = clips.get(String(clip_name), {})
	if clip.is_empty():
		push_warning("PoseAnimator: unknown clip '%s'" % clip_name)
		return
	_blend_from = _capture_current()
	_blend_time = maxf(blend, 0.0001)
	_blend_elapsed = 0.0
	current_clip = clip_name
	_keys = []
	for k in clip["keys"]:
		_keys.append([float(k[0]) / speed, k[1]])
	_events = []
	for e in clip.get("events", []):
		_events.append([float(e[0]) / speed, e[1]])
	_loop = bool(clip.get("loop", false))
	_length = float(_keys[-1][0]) if not _keys.is_empty() else 0.0
	_time = 0.0
	_fired.clear()
	_playing = true


func clip_length(clip_name: StringName, speed: float = 1.0) -> float:
	var clip: Dictionary = clips.get(String(clip_name), {})
	if clip.is_empty():
		return 0.0
	return float(clip["keys"][-1][0]) / speed


## Time (in clip seconds) of the first event with that name, or -1.
func event_time(clip_name: StringName, event_name: StringName, speed: float = 1.0) -> float:
	var clip: Dictionary = clips.get(String(clip_name), {})
	for e in clip.get("events", []):
		if e[1] == event_name:
			return float(e[0]) / speed
	return -1.0


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	advance(delta * time_scale)


func advance(dt: float) -> void:
	if joints.is_empty():
		return
	_phase += dt
	if _playing:
		_time += dt
		_blend_elapsed += dt
		for i in _events.size():
			var e: Array = _events[i]
			if not _fired.has(i) and _time >= float(e[0]):
				_fired[i] = true
				event_triggered.emit(e[1])
		if _time >= _length:
			if _loop and _length > 0.0:
				_time = fmod(_time, _length)
				_fired.clear()
			else:
				_time = _length
				_playing = false
				clip_finished.emit(current_clip)
	_apply()


func _sample() -> Dictionary:
	if _keys.is_empty():
		return {}
	if _keys.size() == 1 or _time <= float(_keys[0][0]):
		return library.get(_keys[0][1], {})
	for i in range(1, _keys.size()):
		var k1: Array = _keys[i]
		if _time <= float(k1[0]):
			var k0: Array = _keys[i - 1]
			var span := float(k1[0]) - float(k0[0])
			var t := 0.0 if span <= 0.0 else (_time - float(k0[0])) / span
			t = t * t * (3.0 - 2.0 * t)
			return _lerp_pose(library.get(k0[1], {}), library.get(k1[1], {}), t)
	return library.get(_keys[-1][1], {})


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = a[key]
	for key in b:
		var va: Vector3 = out.get(key, Vector3.ZERO)
		out[key] = va.lerp(b[key], t)
	for key in a:
		if not b.has(key):
			out[key] = (a[key] as Vector3).lerp(Vector3.ZERO, t)
	return out


func _capture_current() -> Dictionary:
	var pose := {}
	for name in joints:
		var j: Node3D = joints[name]
		pose[name] = j.rotation_degrees
		var off: Vector3 = j.position - rest_offsets[name]
		if off.length_squared() > 0.0:
			pose[String(name) + ":offset"] = off
	return pose


func _apply() -> void:
	var target := _sample()
	if _blend_elapsed < _blend_time:
		var bt := _blend_elapsed / _blend_time
		bt = bt * bt * (3.0 - 2.0 * bt)
		target = _lerp_pose(_blend_from, target, bt)
	var breath := sin(_phase * 2.1) * breathing
	var sway := sin(_phase * 0.7) * breathing
	for name in joints:
		var j: Node3D = joints[name]
		var rot: Vector3 = target.get(name, Vector3.ZERO)
		var off: Vector3 = target.get(String(name) + ":offset", Vector3.ZERO)
		if breathing > 0.0:
			match name:
				"chest":
					rot.x -= breath * 1.6
				"spine":
					rot.z += sway * 0.8
				"head":
					rot.x += breath * 0.8
				"neck":
					rot.y += sway * 2.0
				"shoulder_l", "shoulder_r":
					rot.z += breath * 0.8 * (1.0 if name == "shoulder_l" else -1.0)
		if not overrides.is_empty():
			rot = overrides.get(name, rot)
			off = overrides.get(String(name) + ":offset", off)
		j.rotation_degrees = rot
		j.position = rest_offsets[name] + off

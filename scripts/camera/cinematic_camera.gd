class_name CinematicCamera
extends Camera3D
## Shot-based camera for battles. Shots are computed every frame from the
## live fighter positions (tracking), blended with eased interpolation, and
## kept out of the fighters' bodies. Supports orbit, over-the-shoulder,
## low/high angles, close-ups, dutch roll, FOV punches, shake and DOF.

## Provides fighter anchors: Callable(name: String) -> Vector3.
var anchor_provider: Callable
var side_sign: float = 1.0
## Clearance radius per fighter ("a", "d"); mounted fighters need more room.
var body_radius: Dictionary = {"a": 0.95, "d": 0.95}
var dof_allowed: bool = true

var _shot: Dictionary = {}
var _shot_time: float = 0.0
var _blend_from := Transform3D.IDENTITY
var _blend_fov: float = 45.0
var _blend_duration: float = 0.0
var _blend_elapsed: float = 0.0
var _shake_amp: float = 0.0
var _shake_time: float = 0.0
var _shake_total: float = 0.0
var _noise := FastNoiseLite.new()
var _clock: float = 0.0
var _attributes := CameraAttributesPractical.new()


func _ready() -> void:
	near = 0.05
	far = 300.0
	fov = 45.0
	attributes = _attributes
	_noise.frequency = 2.2


func set_shot(shot: Dictionary, blend: float) -> void:
	_blend_from = global_transform
	_blend_fov = fov
	_blend_duration = blend
	_blend_elapsed = 0.0
	_shot = shot
	_shot_time = 0.0


func shake(amplitude: float, duration: float) -> void:
	var scale := Settings.shake_scale()
	if scale <= 0.0:
		return
	if amplitude * scale >= _shake_amp * (_shake_time / maxf(_shake_total, 0.001)):
		_shake_amp = amplitude * scale
		_shake_time = duration
		_shake_total = duration


## `dt` is battle time (slow motion aware); `real_dt` drives shake/smoothing.
func update_camera(dt: float, real_dt: float) -> void:
	if _shot.is_empty() or not anchor_provider.is_valid():
		return
	_shot_time += dt
	_clock += real_dt
	var goal := _compute(_shot, _shot_time)
	var goal_transform: Transform3D = goal[0]
	var goal_fov: float = goal[1]
	var t := goal_transform
	var f := goal_fov
	if _blend_elapsed < _blend_duration:
		_blend_elapsed += dt
		var w := clampf(_blend_elapsed / _blend_duration, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		t = _blend_from.interpolate_with(goal_transform, w)
		f = lerpf(_blend_fov, goal_fov, w)
	if _shake_time > 0.0:
		_shake_time -= real_dt
		var k := _shake_amp * clampf(_shake_time / maxf(_shake_total, 0.001), 0.0, 1.0)
		var offset := Vector3(_noise.get_noise_2d(_clock * 40.0, 0.0), _noise.get_noise_2d(0.0, _clock * 40.0), 0.0) * k
		t.origin += t.basis * (offset * 0.6)
		t.basis = t.basis.rotated(t.basis.z.normalized(), _noise.get_noise_2d(_clock * 30.0, 99.0) * k * 0.08)
	global_transform = t
	fov = f
	var focus: Vector3 = goal[2]
	_update_dof(t.origin.distance_to(focus), goal[3])


func _update_dof(focus_distance: float, closeup: bool) -> void:
	_attributes.dof_blur_far_enabled = dof_allowed
	_attributes.dof_blur_far_distance = focus_distance + (2.0 if closeup else 6.0)
	_attributes.dof_blur_far_transition = 6.0 if closeup else 14.0
	_attributes.dof_blur_near_enabled = dof_allowed and closeup
	_attributes.dof_blur_near_distance = maxf(0.1, focus_distance - 0.8)
	_attributes.dof_blur_near_transition = 0.6
	_attributes.dof_blur_amount = 0.08 if closeup else 0.05


func _a(name: String) -> Vector3:
	return anchor_provider.call(name)


## Returns [Transform3D, fov, focus_point, is_closeup].
func _compute(shot: Dictionary, time: float) -> Array:
	var a_pos := _a("a_ground")
	var d_pos := _a("d_ground")
	var a_chest := _a("a_chest")
	var d_chest := _a("d_chest")
	var mid := (a_pos + d_pos) * 0.5
	var axis := d_pos - a_pos
	axis.y = 0.0
	axis = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
	var side := axis.cross(Vector3.UP).normalized() * side_sign
	var up := Vector3.UP
	var pos: Vector3
	var look: Vector3
	var fov_out := 45.0
	var roll := 0.0
	var closeup := false
	var name: String = shot.get("shot", "wide")
	var who: String = shot.get("focus", "a")
	match name:
		"establish":
			var yaw := deg_to_rad(65.0 + time * 10.0)
			var dir := (side * cos(yaw) + axis * sin(yaw)).normalized()
			pos = mid + dir * 10.5 + up * 3.0
			look = mid + up * 1.2
			fov_out = 40.0
		"wide":
			pos = mid + side * 8.0 + up * 2.0 - axis * 0.5
			look = mid + up * 1.1
			fov_out = 40.0
		"wide_low":
			pos = mid + side * 6.5 + up * 0.55 - axis * 1.2
			look = mid + up * 1.0
			fov_out = 46.0
		"side":
			pos = mid + side * 5.0 + up * 1.5
			look = mid + up * 1.15
			fov_out = 44.0
		"track_side":
			pos = mid + side * 6.2 + up * 1.3 + axis * 0.6
			look = mid + up * 1.1 + axis * 0.4
			fov_out = 48.0
		"ots_a", "ots_d":
			var me := a_chest if name == "ots_a" else d_chest
			var foe := d_chest if name == "ots_a" else a_chest
			var fwd := (foe - me)
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := fwd.cross(up).normalized() * side_sign
			pos = me - fwd * 1.9 + right * 0.75 + up * 0.35
			look = foe + up * 0.05
			fov_out = 46.0
		"low_a", "low_d":
			var me := a_pos if name == "low_a" else d_pos
			var chest := a_chest if name == "low_a" else d_chest
			var foe := d_pos if name == "low_a" else a_pos
			var fwd := (foe - me)
			fwd.y = 0.0
			fwd = fwd.normalized()
			pos = me + fwd * 2.3 + side * 1.4 + up * 0.32
			look = chest + up * 0.25
			fov_out = 54.0
		"closeup_a", "closeup_d":
			var head := _a("a_head" if name == "closeup_a" else "d_head")
			var foe := d_pos if name == "closeup_a" else a_pos
			var me := a_pos if name == "closeup_a" else d_pos
			var fwd := (foe - me)
			fwd.y = 0.0
			fwd = fwd.normalized()
			pos = head + fwd * 1.15 + side * 0.4 + up * 0.02 - up * time * 0.03
			look = head - up * 0.04
			fov_out = 30.0 - time * 1.5
			closeup = true
		"hero_a":
			var me := a_pos
			var yaw := deg_to_rad(-30.0 + time * 14.0)
			var front := (_a("camera_front_a")).normalized()
			var right := front.cross(up).normalized()
			var dir := (front * cos(yaw) + right * sin(yaw)).normalized()
			pos = me + dir * 3.6 + up * 0.7
			look = a_chest + up * 0.15
			fov_out = 40.0
		"orbit_close":
			var yaw := deg_to_rad(time * 28.0)
			var dir := (side * cos(yaw) - axis * sin(yaw)).normalized()
			pos = mid + dir * 4.2 + up * 1.5
			look = mid + up * 1.2
			fov_out = 44.0
		"dutch":
			pos = mid + side * 4.0 + axis * 1.4 + up * 1.2
			look = mid + up * 1.2
			fov_out = 46.0
			roll = 13.0
		"high":
			pos = mid + up * 6.5 + side * 3.0
			look = mid
			fov_out = 46.0
		"low_mid":
			pos = mid + side * 3.4 + up * 0.25
			look = mid + up * 1.45
			fov_out = 56.0
		"lock":
			var yaw := deg_to_rad(time * 12.0)
			var dir := (side * cos(yaw) + axis * sin(yaw) * 0.4).normalized()
			pos = mid + dir * 2.3 + up * 1.45
			look = mid + up * 1.35
			fov_out = 36.0
			closeup = true
		"projectile":
			var caster_chest := a_chest if who == "a" else d_chest
			var target_chest := d_chest if who == "a" else a_chest
			var fwd := (target_chest - caster_chest).normalized()
			pos = caster_chest - fwd * 2.4 + up * 0.55 + side * 0.6
			look = target_chest.lerp(caster_chest, 0.3)
			fov_out = 50.0
		"sky_a", "sky_d":
			var me := a_pos if name == "sky_a" else d_pos
			pos = mid + side * 4.2 + up * 0.35
			look = (a_chest + up * 0.6) if name == "sky_a" else (me + up * 3.5)
			fov_out = 58.0
		"impact":
			pos = d_chest + side * 2.1 - axis * 0.9 + up * 0.15
			look = d_chest
			fov_out = 40.0 - minf(time, 0.3) * 20.0
			closeup = true
		_:
			pos = mid + side * 7.0 + up * 2.0
			look = mid + up * 1.0
	pos = _avoid_bodies(pos, [a_pos, d_pos], [float(body_radius["a"]), float(body_radius["d"])])
	pos.y = maxf(pos.y, 0.22)
	var t := Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	if roll != 0.0:
		t.basis = t.basis.rotated(t.basis.z.normalized(), deg_to_rad(roll) * side_sign)
	return [t, fov_out, look, closeup]


## Keeps the camera outside a cylinder around each fighter (no clipping).
func _avoid_bodies(pos: Vector3, bodies: Array, radii: Array) -> Vector3:
	var p := pos
	for i in bodies.size():
		var b: Vector3 = bodies[i]
		var r: float = radii[i]
		var flat := Vector2(p.x - b.x, p.z - b.z)
		if flat.length() < r and p.y < b.y + 3.2:
			var push := flat.normalized() if flat.length() > 0.001 else Vector2(1, 0)
			flat = push * r
			p.x = b.x + flat.x
			p.z = b.z + flat.y
	return p

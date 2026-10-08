class_name BoardView
extends Node3D
## 3D chessboard: surface, frame, coordinates, square markers, piece rigs and
## picking. It never decides anything about the game: it shows a position,
## reports clicked squares and offers primitives the MovePresenter animates.
##
## Coordinates: file -> +X, rank 1 at +Z (White's side), CELL metres/square.

signal square_clicked(square: int)
signal square_hovered(square: int)
signal cancel_requested

const CELL := 1.0
const PIECE_SCALE := 0.5
const KNIGHT_SCALE := 0.38
const BOARD_SHADER := preload("res://shaders/board_square.gdshader")
const MARK_SHADER := preload("res://shaders/square_highlight.gdshader")

enum Mark { LAST_MOVE, MOVE, CAPTURE, CHECK, SELECTED, CURSOR, HOVER }

## kind (shader), color, intensity
const MARK_STYLES := {
	Mark.LAST_MOVE: [0, Color(1.0, 0.78, 0.32), 0.5],
	Mark.MOVE: [1, Color(0.45, 0.9, 1.0), 1.1],
	Mark.CAPTURE: [2, Color(1.0, 0.3, 0.2), 1.4],
	Mark.CHECK: [3, Color(1.0, 0.1, 0.05), 1.6],
	Mark.SELECTED: [4, Color(1.0, 0.85, 0.4), 1.6],
	Mark.CURSOR: [4, Color(0.5, 1.0, 0.7), 1.3],
	Mark.HOVER: [0, Color(1.0, 1.0, 1.0), 0.25],
}

var pieces: Dictionary = {}          # square -> CharacterRig
var camera: Camera3D
var input_enabled: bool = false
var cursor_square: int = -1
var hover_square: int = -1
var theme_index: int = 0
## Board orientation for keyboard cursor movement (true = Black's view).
var flipped_view: bool = false

var _board_material: ShaderMaterial
var _frame_material: StandardMaterial3D
var _inlay_material: StandardMaterial3D
var _labels: Array[Label3D] = []
var _mark_materials: Dictionary = {}
var _mark_pool: Array[MeshInstance3D] = []
var _marks_used: int = 0
var _persistent_marks: Array = []
var _selected_square: int = -1


func _ready() -> void:
	_build_board()
	apply_theme(theme_index)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_board() -> void:
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8 * CELL, 8 * CELL)
	surface.mesh = plane
	_board_material = ShaderMaterial.new()
	_board_material.shader = BOARD_SHADER
	surface.material_override = _board_material
	add_child(surface)

	_frame_material = StandardMaterial3D.new()
	_frame_material.rim_enabled = true
	_frame_material.rim = 0.15
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(8 * CELL + 1.1, 0.36, 8 * CELL + 1.1)
	frame.mesh = frame_mesh
	frame.material_override = _frame_material
	frame.position.y = -0.181
	add_child(frame)
	# Bevelled lower tier gives the slab some mass.
	var tier := MeshInstance3D.new()
	var tier_mesh := BoxMesh.new()
	tier_mesh.size = Vector3(8 * CELL + 1.5, 0.22, 8 * CELL + 1.5)
	tier.mesh = tier_mesh
	tier.material_override = _frame_material
	tier.position.y = -0.42
	add_child(tier)

	_inlay_material = StandardMaterial3D.new()
	_inlay_material.metallic = 1.0
	_inlay_material.roughness = 0.25
	var half := 4 * CELL + 0.06
	for i in 4:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8 * CELL + 0.24, 0.02, 0.06) if i < 2 else Vector3(0.06, 0.02, 8 * CELL + 0.24)
		bar.mesh = bm
		bar.material_override = _inlay_material
		bar.position = [Vector3(0, 0.0, -half), Vector3(0, 0.0, half), Vector3(-half, 0.0, 0), Vector3(half, 0.0, 0)][i]
		add_child(bar)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var stud := MeshInstance3D.new()
		stud.mesh = MaterialLibrary.sphere(0.13)
		stud.material_override = _inlay_material
		stud.position = Vector3(corner.x * (half + 0.25), 0.0, corner.y * (half + 0.25))
		stud.scale = Vector3(1, 0.45, 1)
		add_child(stud)

	for i in 8:
		for side in [-1.0, 1.0]:
			var file_label := _make_label(Chess.FILES[i])
			file_label.position = Vector3((i - 3.5) * CELL, 0.005, side * (4 * CELL + 0.3))
			file_label.rotation_degrees = Vector3(-90, 0 if side > 0 else 180, 0)
			var rank_label := _make_label(str(i + 1))
			rank_label.position = Vector3(side * (4 * CELL + 0.3), 0.005, (3.5 - i) * CELL)
			rank_label.rotation_degrees = Vector3(-90, 0 if side < 0 else 180, 0)

	for kind in MARK_STYLES:
		var style: Array = MARK_STYLES[kind]
		var m := ShaderMaterial.new()
		m.shader = MARK_SHADER
		m.set_shader_parameter("kind", style[0])
		m.set_shader_parameter("color", style[1])
		m.set_shader_parameter("intensity", style[2])
		_mark_materials[kind] = m


func _make_label(text: String) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0045
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	add_child(l)
	_labels.append(l)
	return l


func apply_theme(index: int) -> void:
	theme_index = index
	var t := BoardTheme.get_theme(index)
	_board_material.set_shader_parameter("light_color", t["light"])
	_board_material.set_shader_parameter("dark_color", t["dark"])
	_board_material.set_shader_parameter("vein_color", t["vein"])
	_board_material.set_shader_parameter("vein_strength", t["vein_strength"])
	_board_material.set_shader_parameter("vein_scale", t["vein_scale"])
	_board_material.set_shader_parameter("grain", t["grain"])
	_board_material.set_shader_parameter("light_roughness", t["light_roughness"])
	_board_material.set_shader_parameter("dark_roughness", t["dark_roughness"])
	_board_material.set_shader_parameter("light_metallic", t["light_metallic"])
	_board_material.set_shader_parameter("dark_metallic", t["dark_metallic"])
	_board_material.set_shader_parameter("clearcoat_amount", t["clearcoat"])
	_board_material.set_shader_parameter("groove_color", t["groove"])
	_frame_material.albedo_color = t["frame"]
	_frame_material.roughness = t["frame_roughness"]
	_frame_material.metallic = t["frame_metallic"]
	_inlay_material.albedo_color = t["inlay"]
	for l in _labels:
		l.modulate = t["label"]


# --------------------------------------------------------------------------
# Coordinates
# --------------------------------------------------------------------------

static func square_to_local(sq: int) -> Vector3:
	return Vector3(((sq & 7) - 3.5) * CELL, 0.0, (3.5 - (sq >> 3)) * CELL)


func square_to_world(sq: int) -> Vector3:
	return to_global(square_to_local(sq))


func local_to_square(p: Vector3) -> int:
	var file := int(floor(p.x / CELL + 4.0))
	var rank := int(floor(4.0 - p.z / CELL))
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 8 + file


## Pieces at rest face the commander's camera (like troops awaiting orders),
## each army turned slightly the opposite way. The player always sees armour,
## heraldry and weapons; pieces still turn toward the enemy to move/fight.
const IDLE_TURN := deg_to_rad(20.0)

var _facing_yaw_applied: float = 0.0
var _camera_still: float = 0.0
var _last_camera_yaw: float = 0.0


## Yaw (radians) for a piece of `color` at rest, given the camera's yaw.
static func facing_yaw(color: int, view_yaw: float = 0.0) -> float:
	return view_yaw + (IDLE_TURN if color == Chess.WHITE else -IDLE_TURN)


## Horizontal direction from the board toward the camera, as a yaw.
func view_yaw() -> float:
	if camera == null:
		return 0.0
	var d := camera.global_position - global_position
	return atan2(d.x, d.z)


func _process(delta: float) -> void:
	# Re-face the troops once the player has finished rotating the camera.
	var y := view_yaw()
	if absf(wrapf(y - _last_camera_yaw, -PI, PI)) > 0.002:
		_camera_still = 0.0
	else:
		_camera_still += delta
	_last_camera_yaw = y
	if _camera_still > 0.35 and absf(wrapf(y - _facing_yaw_applied, -PI, PI)) > deg_to_rad(25.0):
		refresh_facing()


## Turns every piece at rest toward the current viewing side (smoothly).
func refresh_facing(duration: float = 0.6) -> void:
	var vy := view_yaw()
	_facing_yaw_applied = vy
	for sq in pieces:
		var rig: CharacterRig = pieces[sq]
		if rig.animator.current_clip != &"idle" and rig.animator.current_clip != &"guard":
			continue
		var goal := facing_yaw(Chess.piece_color(int(rig.get_meta("piece"))), vy)
		goal = rig.rotation.y + wrapf(goal - rig.rotation.y, -PI, PI)
		rig.create_tween().tween_property(rig, "rotation:y", goal, duration).set_trans(Tween.TRANS_SINE)


static func piece_scale(type: int) -> float:
	return KNIGHT_SCALE if type == Chess.KNIGHT else PIECE_SCALE


# --------------------------------------------------------------------------
# Pieces
# --------------------------------------------------------------------------

func create_piece_rig(type: int, color: int) -> CharacterRig:
	var rig := CharacterLibrary.create(type, color, "board")
	rig.name = "%s_%s" % [Chess.color_name(color), Chess.type_name(type)]
	add_child(rig)
	rig.build(type, color)
	if rig is SkinnedCharacterRig:
		# Imported models are real-size: normalise to the procedural 1.9 m reference.
		rig.scale = Vector3.ONE * piece_scale(type) * 1.9 / float(CharacterLibrary.info(type)["height"])
	else:
		rig.scale = Vector3.ONE * piece_scale(type)
	rig.set_meta("piece", Chess.make_piece(type, color))
	# Faction plinth improves readability from any camera angle.
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	plinth.mesh = MaterialLibrary.cylinder(0.78, 0.84, 0.08, 28)
	plinth.material_override = MaterialLibrary.get_material("armor" if color == Chess.BLACK else "cloth", color)
	plinth.position.y = 0.04
	rig.add_child(plinth)
	var ring := MeshInstance3D.new()
	ring.mesh = MaterialLibrary.torus(0.78, 0.86)
	ring.material_override = MaterialLibrary.get_material("plinth_glow", color)
	ring.position.y = 0.075
	ring.scale = Vector3(1, 0.5, 1)
	rig.add_child(ring)
	if type == Chess.KNIGHT:
		plinth.scale = Vector3(1.6, 1, 2.4)
		ring.scale = Vector3(1.6, 0.5, 2.4)
	return rig


func place_rig(rig: CharacterRig, sq: int) -> void:
	pieces[sq] = rig
	rig.position = square_to_local(sq)
	_facing_yaw_applied = view_yaw()
	rig.rotation = Vector3(0, facing_yaw(Chess.piece_color(int(rig.get_meta("piece"))), _facing_yaw_applied), 0)


## Removes a rig from the square map without freeing it (for animation).
func detach_rig(sq: int) -> CharacterRig:
	var rig: CharacterRig = pieces.get(sq)
	pieces.erase(sq)
	return rig


func rig_at(sq: int) -> CharacterRig:
	return pieces.get(sq)


## Reconciles the visual pieces with `position` exactly: creates, removes,
## re-types and re-places rigs. Called after every presented move, undo,
## load and skip, so visuals can never drift from the authoritative state.
func sync_to_position(position: ChessPosition) -> void:
	var keep := {}
	for sq in 64:
		var piece := position.squares[sq]
		if piece == Chess.EMPTY:
			continue
		var rig: CharacterRig = pieces.get(sq)
		if rig != null and is_instance_valid(rig) and int(rig.get_meta("piece")) == piece:
			keep[sq] = rig
		else:
			keep[sq] = create_piece_rig(piece & 7, piece >> 3)
	for sq in pieces:
		var rig: CharacterRig = pieces[sq]
		if is_instance_valid(rig) and keep.get(sq) != rig:
			rig.queue_free()
	# Rigs floating outside the map (e.g. mid-animation) are also removed.
	for child in get_children():
		if child is CharacterRig and not keep.values().has(child):
			child.queue_free()
	pieces.clear()
	for sq in keep:
		var rig: CharacterRig = keep[sq]
		place_rig(rig, sq)
		rig.set_fade(0.0)
		rig.reset_pose_state()
		rig.visible = true
		rig.play(&"idle", 0.25)


func piece_count() -> int:
	return pieces.size()


# --------------------------------------------------------------------------
# Markers
# --------------------------------------------------------------------------

func clear_marks() -> void:
	for i in _marks_used:
		_mark_pool[i].visible = false
	_marks_used = 0


func add_mark(sq: int, kind: Mark) -> void:
	if sq < 0 or sq > 63:
		return
	if _marks_used >= _mark_pool.size():
		var mi := MeshInstance3D.new()
		mi.mesh = MaterialLibrary.quad(Vector2(CELL * 0.98, CELL * 0.98))
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mark_pool.append(mi)
	var mark := _mark_pool[_marks_used]
	_marks_used += 1
	mark.material_override = _mark_materials[kind]
	mark.position = square_to_local(sq) + Vector3(0, 0.006 + 0.001 * int(kind), 0)
	mark.visible = true


## Redraws all markers. `moves` are legal moves of the selected piece.
func show_state(selected: int, moves: PackedInt32Array, last_from: int, last_to: int, check_square: int) -> void:
	clear_marks()
	if last_from >= 0:
		add_mark(last_from, Mark.LAST_MOVE)
		add_mark(last_to, Mark.LAST_MOVE)
	if check_square >= 0:
		add_mark(check_square, Mark.CHECK)
	if selected >= 0:
		add_mark(selected, Mark.SELECTED)
	var shown := {}
	for move in moves:
		var to := Chess.move_to(move)
		if shown.has(to):
			continue
		shown[to] = true
		add_mark(to, Mark.CAPTURE if Chess.is_capture(move) else Mark.MOVE)
	if input_enabled:
		if cursor_square >= 0:
			add_mark(cursor_square, Mark.CURSOR)
		if hover_square >= 0 and hover_square != selected:
			add_mark(hover_square, Mark.HOVER)
	_update_selection_pose(selected)


func _update_selection_pose(selected: int) -> void:
	if selected == _selected_square:
		return
	var old: CharacterRig = pieces.get(_selected_square)
	if old != null and is_instance_valid(old):
		old.play(&"idle", 0.3)
	_selected_square = selected
	var rig: CharacterRig = pieces.get(selected)
	if rig != null:
		rig.play(&"guard", 0.2)


# --------------------------------------------------------------------------
# Picking & input
# --------------------------------------------------------------------------

## Square under a screen position. Pieces are tested first (vertical
## cylinders), so clicking a tall figure selects its square, not the square
## behind it.
func pick_square(screen_pos: Vector2) -> int:
	if camera == null:
		return -1
	var origin := to_local(camera.project_ray_origin(screen_pos))
	var dir := (global_basis.inverse() * camera.project_ray_normal(screen_pos)).normalized()
	var best := -1
	var best_t := INF
	var d2 := Vector2(dir.x, dir.z)
	var d2_len2 := d2.length_squared()
	if d2_len2 > 1e-6:
		for sq in pieces:
			var rig: CharacterRig = pieces[sq]
			var c := rig.position
			var t := Vector2(c.x - origin.x, c.z - origin.z).dot(d2) / d2_len2
			if t <= 0.0:
				continue
			var p := origin + dir * t
			var h := rig.height() * rig.scale.y
			if p.y < -0.05 or p.y > h:
				continue
			if Vector2(p.x - c.x, p.z - c.z).length() <= CELL * 0.36 and t < best_t:
				best_t = t
				best = sq
	if best >= 0:
		return best
	if absf(dir.y) < 1e-5:
		return -1
	var t_plane := -origin.y / dir.y
	if t_plane < 0.0:
		return -1
	return local_to_square(origin + dir * t_plane)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var sq := pick_square((event as InputEventMouseMotion).position)
		if sq != hover_square:
			hover_square = sq
			square_hovered.emit(sq)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var sq := pick_square(mb.position)
			cursor_square = -1
			if sq >= 0:
				square_clicked.emit(sq)
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("board_cursor_up"):
		_move_cursor(0, 1)
	elif event.is_action_pressed("board_cursor_down"):
		_move_cursor(0, -1)
	elif event.is_action_pressed("board_cursor_left"):
		_move_cursor(-1, 0)
	elif event.is_action_pressed("board_cursor_right"):
		_move_cursor(1, 0)
	elif event.is_action_pressed("board_select"):
		if cursor_square >= 0:
			square_clicked.emit(cursor_square)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("board_cancel"):
		cancel_requested.emit()


func _move_cursor(df: int, dr: int) -> void:
	if flipped_view:
		df = -df
		dr = -dr
	if cursor_square < 0:
		cursor_square = 12 if not flipped_view else 52
	else:
		var f := clampi((cursor_square & 7) + df, 0, 7)
		var r := clampi((cursor_square >> 3) + dr, 0, 7)
		cursor_square = r * 8 + f
	hover_square = -1
	square_hovered.emit(cursor_square)
	get_viewport().set_input_as_handled()

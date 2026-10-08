extends SceneTree
## Renders every character archetype (both factions) and saves a PNG.
##   godot --path . --script res://tools/character_gallery.gd -- --out=/tmp/gallery.png --clip=guard
## Requires a display (not --headless) because it captures the viewport.

var _frames := 0
var _out := "user://character_gallery.png"
var _clip := &"idle"
var _view := "front"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--clip="):
			_clip = StringName(a.trim_prefix("--clip="))
		elif a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	root.size = Vector2i(1920, 1080)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.2, 0.28)
	sky_mat.sky_horizon_color = Color(0.5, 0.45, 0.42)
	sky_mat.ground_bottom_color = Color(0.1, 0.09, 0.08)
	sky_mat.ground_horizon_color = Color(0.4, 0.36, 0.33)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.6, 0.7, 1.0)
	world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.23, 0.22)
	fm.roughness = 0.8
	floor_mesh.material_override = fm
	world.add_child(floor_mesh)
	var types := [Chess.PAWN, Chess.KNIGHT, Chess.BISHOP, Chess.ROOK, Chess.QUEEN, Chess.KING]
	for color in 2:
		for i in types.size():
			var rig := CharacterRig.new()
			world.add_child(rig)
			rig.build(types[i], color)
			rig.position = Vector3((i - 2.5) * 1.6, 0, -1.6 if color == 1 else 1.0)
			if _view == "side":
				rig.rotation_degrees.y = 90
			rig.play(_clip, 0.0)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	if _view == "close":
		cam.position = Vector3(-2.5, 2.0, 4.6)
		cam.look_at_from_position(cam.position, Vector3(-2.4, 1.2, 0))
	else:
		cam.position = Vector3(0, 3.2, 9.5)
		cam.look_at_from_position(cam.position, Vector3(0, 1.1, -0.3))
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 45:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		return true
	return false

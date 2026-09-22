## Displays a level with a free-flying camera.
##
## Command line (after `--`):
##   --level=N                 Level to load (3–8, default 3).
##   --camera=x,y,z            Initial camera position (Godot coordinates).
##   --look-at=x,y,z           Point the camera at this position.
##   --screenshot=path.png     Save a screenshot after loading and quit.
extends Node3D

@onready var level: Level = $Level
@onready var camera: Camera3D = $Camera
@onready var info: Label = $Info


func _ready() -> void:
	var args := Args.get_all()
	var start := Time.get_ticks_msec()
	level.load_level(int(args.get("level", "3")))
	print("Level %d loaded in %d ms" % [level.number, Time.get_ticks_msec() - start])

	# Start where the player lands.
	camera.global_position = level.get_start_position() + Vector3.UP * 20.0
	camera.yaw = level.get_start_yaw()
	camera.pitch = deg_to_rad(-10.0)
	camera.rotation = Vector3(camera.pitch, camera.yaw, 0.0)
	if args.has("camera"):
		camera.global_position = Args.parse_vector(args.camera)
	if args.has("look-at"):
		camera.look_at_point(Args.parse_vector(args["look-at"]))
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot)


func _process(_delta: float) -> void:
	info.text = "Level %d — %d arenas, %d triangles\nWASD/QE: move, click: mouse look, Shift: fast\nCamera: %s  FPS: %d" % [
			level.number, level.mto.get_arena_names().size(), level.triangle_count,
			camera.global_position.round(), Engine.get_frames_per_second()]

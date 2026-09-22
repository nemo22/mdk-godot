## Loads a level's arenas and displays them with a free camera.
##
## Command line (after `--`):
##   --level=N                 Level to load (3–8, default 3).
##   --camera=x,y,z            Initial camera position (Godot coordinates).
##   --look-at=x,y,z           Point the camera at this position.
##   --screenshot=path.png     Save a screenshot after loading and quit.
extends Node3D

const SKY_SHADER := preload("res://mdk/shaders/sky.gdshader")

var level := 3
var dti: MDKDti
var mto: MDKMto
var level_textures: MDKTextureArchive

@onready var camera: Camera3D = $Camera
@onready var info: Label = $Info


func _ready() -> void:
	var args := _parse_args()
	level = int(args.get("level", "3"))
	var start := Time.get_ticks_msec()
	_load_level()
	print("Level %d loaded in %d ms" % [level, Time.get_ticks_msec() - start])

	if args.has("camera"):
		camera.global_position = _parse_vector(args.camera)
	if args.has("look-at"):
		camera.look_at_point(_parse_vector(args["look-at"]))
	if args.has("screenshot"):
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.screenshot)
		print("Saved screenshot: %s" % args.screenshot)
		get_tree().quit()


func _load_level() -> void:
	var dir := "TRAVERSE/LEVEL%d/" % level
	dti = MDKDti.load_file(MDKData.path(dir + "LEVEL%d.DTI" % level))
	mto = MDKMto.load_file(MDKData.path(dir + "LEVEL%dO.MTO" % level))
	level_textures = MDKTextureArchive.load_file(MDKData.path(dir + "LEVEL%dS.MTI" % level))

	var triangle_count := 0
	for arena_name: String in mto.get_arena_names():
		var arena := mto.get_arena(arena_name)
		var palette := dti.palette.with_arena_colors(arena.palette_rgb)
		var resolver := MDKMeshBuilder.MaterialResolver.new(palette, [arena.textures, level_textures])
		var instance := MeshInstance3D.new()
		instance.name = arena_name
		instance.mesh = MDKMeshBuilder.build_arena_mesh(arena, resolver)
		if not resolver.missing.is_empty():
			push_warning("%s: materials not found: %s" % [arena_name, ", ".join(resolver.missing)])
		if not resolver.skipped_special.is_empty():
			print("%s: skipped special materials (value: triangles): %s" % [arena_name, resolver.skipped_special])
		add_child(instance)
		triangle_count += arena.triangle_materials.size()

	_setup_sky()
	info.text = "Level %d — %d arenas, %d triangles\nWASD/QE: move, click: mouse look, Shift: fast" % [
			level, mto.get_arena_names().size(), triangle_count]

	# Start where the player lands.
	camera.global_position = MDKMeshBuilder.to_godot(dti.start_position) + Vector3.UP * 20.0
	camera.yaw = deg_to_rad(dti.start_angle - 90.0)
	camera.pitch = deg_to_rad(-10.0)
	camera.rotation = Vector3(camera.pitch, camera.yaw, 0.0)


func _setup_sky() -> void:
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter(&"sky_index", dti.sky.get_index_texture())
	material.set_shader_parameter(&"palette", dti.palette.get_texture())
	material.set_shader_parameter(&"texture_width", float(dti.sky.width))
	material.set_shader_parameter(&"wrap_width", float(dti.sky_wrap_width))
	material.set_shader_parameter(&"horizon_row", float(dti.sky_horizon_row))
	material.set_shader_parameter(&"offset", float(dti.sky_offset))
	material.set_shader_parameter(&"top_color", dti.sky_top_color)
	material.set_shader_parameter(&"bottom_color", dti.sky_bottom_color)
	var sky := Sky.new()
	sky.sky_material = material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _process(_delta: float) -> void:
	info.text = info.text.get_slice("\n", 0) + "\n" + info.text.get_slice("\n", 1) + "\nCamera: %s  FPS: %d" % [
			camera.global_position.round(), Engine.get_frames_per_second()]


static func _parse_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


static func _parse_vector(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

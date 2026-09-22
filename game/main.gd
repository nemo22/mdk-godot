## The game: a level with Kurt and the third person camera.
##
## Command line (after `--`):
##   --level=N                 Level to load (3–8, default: the one chosen in the menu).
##   --viewer                  Open the free-camera level viewer instead.
##   --models                  Open the model viewer instead (see `model_viewer.gd`).
##   --walk=seconds            Hold "move forward" for this long (for automated tests).
##   --screenshot=path.png     Save a screenshot after loading (and walking) and quit.
##   --profile=seconds         Print performance and script statistics after this long, then quit.
##   --no-scripts              Don't run the level scripts (no objects or aliens).
extends Node3D

@onready var level: Level = $Level
@onready var kurt: Kurt = $Kurt
@onready var scripts: MDKScriptRuntime = $Scripts
@onready var info: Label = $Info


func _ready() -> void:
	var args := Args.get_all()
	if args.has("viewer"):
		get_tree().change_scene_to_file.call_deferred("res://game/level_viewer.tscn")
		return
	if args.has("models"):
		get_tree().change_scene_to_file.call_deferred("res://game/model_viewer.tscn")
		return
	var start := Time.get_ticks_msec()
	level.load_level(int(args.get("level", str(GameState.level))))
	print("Level %d loaded in %d ms" % [level.number, Time.get_ticks_msec() - start])

	var sprites := MDKBni.load_file(MDKData.path("TRAVERSE/TRAVSPRT.BNI"))
	kurt.setup(sprites, level.get_palette(), level.get_sound)
	# The start position is slightly below the landing pad (the original lands Kurt by parachute),
	# so drop him from a bit higher.
	kurt.teleport(level.get_start_position() + Vector3.UP * 3.0, level.get_start_yaw())
	if not args.has("no-scripts"):
		scripts.setup(level, kurt)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if args.has("walk"):
		Input.action_press(&"move_forward")
		await get_tree().create_timer(float(args.walk)).timeout
		Input.action_release(&"move_forward")
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot, 20)
	if args.has("profile"):
		_profile(float(args.profile))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# There's no pause menu yet: go back to the main menu.
		get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	info.text = "Level %d  %s  Kurt: %s  %s  objects: %d  FPS: %d" % [level.number, scripts.current_arena,
			MDKScriptRuntime.to_mdk(kurt.global_position).round(), Kurt.State.keys()[kurt.state],
			scripts.objects.size(), Engine.get_frames_per_second()]


func _profile(seconds: float) -> void:
	var frames := 0
	var start := Time.get_ticks_msec()
	var slowest := 0
	var last := start
	var process_ms := 0.0
	var physics_ms := 0.0
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		slowest = maxi(slowest, now - last)
		last = now
		frames += 1
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("FPS %.1f (slowest frame %d ms), objects %d, arena %s" % [frames / seconds, slowest, scripts.objects.size(), scripts.current_arena])
	print("per frame: process %.1f ms, physics %.1f ms, draw calls %d; script tick %.2f ms" % [
			process_ms / frames, physics_ms / frames,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), scripts.average_tick_ms()])
	if scripts.vm:
		print("unimplemented opcodes (opcode: count): ", scripts.vm.unimplemented)
		for obj in scripts.objects:
			print("  %s_%d %s yaw %d move %d path %d anim %s speed %.1f" % [obj.type_name, obj.instance_id,
					obj.mdk_position.round(), obj.yaw, obj.move_command, obj.path,
					obj.animation.name if obj.animation else "-", obj.speed])
		print("Kurt health %d" % kurt.health)
	get_tree().quit()

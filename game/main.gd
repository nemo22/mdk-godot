## The game: a level with Kurt and the third person camera.
##
## Command line (after `--`):
##   --level=N                 Level to load (3–8, default: the one chosen in the menu).
##   --viewer                  Open the free-camera level viewer instead.
##   --models                  Open the model viewer instead (see `model_viewer.gd`).
##   --at=x,y,z[,yaw]          Start Kurt there instead (MDK coordinates and yaw, for tests).
##   --delay=seconds           Wait this long before walking.
##   --walk=seconds            Hold "move forward" for this long (for automated tests).
##   --fire                    Hold "fire" (for automated tests).
##   --health=N                Start with this much health (for tests).
##   --give=SW_A,SW_B          Start with these pickups (for tests).
##   --use                     Press "use item" after the delay (for tests).
##   --wait=seconds            Wait this long before the screenshot.
##   --screenshot=path.png     Save a screenshot after loading (and walking) and quit.
##   --profile=seconds         Print performance and script statistics after this long, then quit.
##   --no-scripts              Don't run the level scripts (no objects or aliens).
##   --town=seconds            The minecrawler flattens the town after this long (for tests).
extends Node3D

@onready var level: Level = $Level
@onready var kurt: Kurt = $Kurt
@onready var scripts: MDKScriptRuntime = $Scripts
@onready var info: Label = $Info
@onready var hud: HUD = $HUDLayer/HUD


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
	hud.setup(kurt, sprites, level.get_palette(), MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI")))
	kurt.died.connect(_on_kurt_died)
	if args.has("health"):
		kurt.health = int(args.health)
	if args.has("give"):
		for pickup: String in args.give.split(","):
			kurt.inventory.collect(pickup, kurt)
	# The start position is slightly below the landing pad (the original lands Kurt by parachute),
	# so drop him from a bit higher.
	kurt.teleport(level.get_start_position() + Vector3.UP * 3.0, level.get_start_yaw())
	if args.has("at"):
		var at: PackedFloat64Array = args.at.split_floats(",")
		kurt.teleport(MDKMeshBuilder.to_godot(Vector3(at[0], at[1], at[2])), deg_to_rad(at[3] - 90.0) if at.size() > 3 else kurt.yaw)
	if not args.has("no-scripts"):
		scripts.messages = hud.messages
		scripts.setup(level, kurt)
		hud.scripts = scripts
		if args.has("town"):
			scripts.town_ticks = roundi(float(args.town) * 30.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if args.has("fire"):
		Input.action_press(&"fire")
	if args.has("delay"):
		await get_tree().create_timer(float(args.delay)).timeout
	if args.has("use"):
		Input.action_press(&"item_use")
		await get_tree().create_timer(0.1).timeout
		Input.action_release(&"item_use")
	if args.has("walk"):
		Input.action_press(&"move_forward")
		await get_tree().create_timer(float(args.walk)).timeout
		Input.action_release(&"move_forward")
	if args.has("wait"):
		await get_tree().create_timer(float(args.wait)).timeout
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot, 20)
	if args.has("profile"):
		_profile(float(args.profile))


## Kurt died: play the level again (the original loads the last saved game).
func _on_kurt_died() -> void:
	GameState.level = level.number
	get_tree().reload_current_scene()


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
		if not is_inside_tree():
			return
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
			print("  %s_%d %s %s yaw %d move %d path %d anim %s frame %d speed %.1f health %d flags %x%s" % [
					obj.type_name, obj.instance_id, obj.arena, obj.mdk_position.round(), obj.yaw, obj.move_command,
					obj.path, obj.animation.name if obj.animation else "-", obj.animation_frame, obj.speed, obj.health, obj.flags,
					" door %x" % obj.door_state if obj.flags & MDKObject.FLAG_DOOR else ""])
		var items := []
		for slot in kurt.inventory.slots:
			items.push_back("%s×%d" % [KurtInventory.Item.keys()[slot.item], slot.count])
		print("Kurt at %s health %d, items %s (selected %d), ammo %s, super chain gun %d" % [MDKScriptRuntime.to_mdk(kurt.global_position).round(), kurt.health, items,
				kurt.inventory.selected, kurt.inventory.ammo, kurt.inventory.super_chain_gun])
	get_tree().quit()

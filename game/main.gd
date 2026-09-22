## The game: a level with Kurt and the third person camera.
##
## Command line (after `--`):
##   --level=N                 Level to load (3–8, default: the one chosen in the menu).
##   --viewer                  Open the free-camera level viewer instead.
##   --models                  Open the model viewer instead (see `model_viewer.gd`).
##   --walk=seconds            Hold "move forward" for this long (for automated tests).
##   --screenshot=path.png     Save a screenshot after loading (and walking) and quit.
extends Node3D

@onready var level: Level = $Level
@onready var kurt: Kurt = $Kurt
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
	kurt.setup(sprites, level.get_palette())
	# The start position is slightly below the landing pad (the original lands Kurt by parachute),
	# so drop him from a bit higher.
	kurt.teleport(level.get_start_position() + Vector3.UP * 3.0, level.get_start_yaw())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if args.has("walk"):
		Input.action_press(&"move_forward")
		await get_tree().create_timer(float(args.walk)).timeout
		Input.action_release(&"move_forward")
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot, 20)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# There's no pause menu yet: go back to the main menu.
		get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	info.text = "Level %d  Kurt: %s  %s  FPS: %d" % [level.number, kurt.global_position.round(),
			Kurt.State.keys()[kurt.state], Engine.get_frames_per_second()]

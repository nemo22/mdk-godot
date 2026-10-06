## Bug test: LEVEL6's slide from COLYM_1 drops Kurt into OLYM_2 against a wall; still moving, he
## lay there sliding until friction stopped him (about 13 s). The original's arena switch (0x41c550)
## sets the slide flag 0x573be8 to −15: `damp_buttslide` ends the slide 15 ticks later (falling).
## Run: godot --headless --audio-driver Dummy --path . -s tests/slide_exit_test.gd
extends SceneTree

const LEVEL := 6
const START_ARENA := "COLYM_1"
const END_ARENA := "OLYM_2"
## The first wind zone (MDK), facing along the wind.
const START := Vector3(-1150.0, -790.0, -85.0)
const START_YAW := 90.0
## Physics frames (60 per second): the slide reaches OLYM_2 after about 25 s; 15 ticks are 30 frames.
const SLIDE_FRAMES := 1800
const END_FRAMES := 40

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	var kurt: Node = main.get_node("Kurt")
	while scripts.tick_count() == 0:
		await physics_frame
	scripts.teleport_kurt(START_ARENA, START, START_YAW)

	# Slide until he enters OLYM_2.
	var slid := false
	for i in SLIDE_FRAMES:
		await physics_frame
		slid = slid or kurt.sliding
		if scripts.current_arena == END_ARENA:
			break
	_expect(slid, "never slid")
	_expect(scripts.current_arena == END_ARENA, "not in %s: %s" % [END_ARENA, scripts.current_arena])

	# 15 ticks later the slide is over.
	for i in END_FRAMES:
		await physics_frame
	_expect(not kurt.sliding, "still sliding at %s" % scripts.kurt_position)
	_expect(kurt.slide_velocity == Vector2.ZERO, "slide velocity %s" % kurt.slide_velocity)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

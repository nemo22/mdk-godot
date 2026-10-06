## Bug test: the turn keys steered the slide the wrong way (left turned right). As walking, left
## turns left, at 45°/s (`damp_buttslide`). The mouse didn't steer it: it turns it as walking, at
## most 4 × 45°/s (`damp_control` clamps the turn rate 0x5014d4).
## Run: godot --headless --audio-driver Dummy --path . -s tests/slide_steer_test.gd
extends SceneTree

## LEVEL6 (the slide's animations are there), from where Kurt starts, facing +y (MDK).
const LEVEL := 6
const KURT_YAW := 90.0
const SLIDE_SPEED := 30.0
## Physics frames (60 per second): settle, then half a second of steering (22.5° at 45°/s).
const SETTLE_FRAMES := 60
const STEER_FRAMES := 30
const KEY_TURN := 22.5
## The keys take a frame or two to count.
const TOLERANCE := 2.0
## A frame's mouse turn (degrees): a small one and one beyond the 3° (180°/s) cap.
const MOUSE_TURN := 2.0
const MOUSE_FLICK := 1000.0
const MOUSE_CAP := 3.0
const MOUSE_TOLERANCE := 0.25

var _failures := 0
var _kurt: Node
var _room := ""
var _spot := Vector3()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	_kurt = main.get_node("Kurt")
	while scripts.tick_count() == 0:
		await physics_frame
	_room = scripts.current_arena
	_spot = scripts.kurt_position

	# The left key turns left (MDK yaw grows).
	await _slide(scripts)
	Input.action_press(&"turn_left")
	for i in STEER_FRAMES:
		await physics_frame
	Input.action_release(&"turn_left")
	_expect_yaw(KURT_YAW + KEY_TURN, TOLERANCE, "turn left")

	# The mouse turns the slide, capped.
	for turn in [[MOUSE_TURN, MOUSE_TURN], [MOUSE_FLICK, MOUSE_CAP], [-MOUSE_FLICK, -MOUSE_CAP]]:
		await _slide(scripts)
		await physics_frame
		_kurt._mouse_turn = turn[0]
		await physics_frame
		await physics_frame
		_expect_yaw(KURT_YAW + turn[1], MOUSE_TOLERANCE, "mouse %.0f" % turn[0])

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Puts Kurt on the floor, then sliding ahead.
func _slide(scripts: Node) -> void:
	scripts.teleport_kurt(_room, _spot, KURT_YAW)
	for i in SETTLE_FRAMES:
		await physics_frame
	_kurt.start_slide()
	_kurt.slide_velocity = Vector2.from_angle(deg_to_rad(KURT_YAW)) * SLIDE_SPEED


## Kurt's MDK yaw (Godot's yaw 0 faces MDK +y).
func _expect_yaw(expected: float, tolerance: float, message: String) -> void:
	var yaw := rad_to_deg(_kurt.yaw) + 90.0
	_expect(absf(wrapf(yaw - expected, -180.0, 180.0)) < tolerance, "%s: yaw %.2f, not %.2f" % [message, yaw, expected])


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

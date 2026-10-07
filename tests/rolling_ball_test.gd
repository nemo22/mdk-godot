## Bug test: LEVEL6 OLYM_6's boulders XBO. They pop out of a pit towards Kurt and roll on the floor.
## They hung in the air on the back of a hidden one-sided wall (y = 2772), which the original's BSP
## sweep passes (0x45fec4). Then they showed as half-domes sunk into the floor: the ball rests on
## its centred origin, its script sets a height offset of 5 (`set_height_offset`, radius 5.15) that
## the original adds to z when drawing a rolling object (0x43b65c).
## Run: godot --headless --audio-driver Dummy --path . -s tests/rolling_ball_test.gd
extends SceneTree

const LEVEL := 6
const ROOM := "OLYM_6"
const BALL := "XBO"
## Inside the balls' spawn box (if_kurt_in_box at 0xcc34).
const ENTRY := Vector3(-1900.0, 3100.0, -2160.0)
## Physics frames (60 per second): 5 s of rolling.
const ROLL_FRAMES := 300
## How far below its origin a floor counts as under the ball.
const FLOOR_REACH := 2.0
const FLOOR_TOLERANCE := 0.5
## `Level.RAY_LAYER` (the class needs autoloads not there when this script compiles).
const RAY_LAYER := 1

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	while scripts.tick_count() == 0:
		await physics_frame
	scripts.teleport_kurt(ROOM, ENTRY, 0.0)
	for i in ROLL_FRAMES:
		await physics_frame

	var balls: Array = scripts.objects.filter(func(o): return o.type_name == BALL and not o.dead)
	_expect(not balls.is_empty(), "no %s" % BALL)
	for ball in balls:
		_check_on_floor(ball)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## The ball rests on a floor, its lowest drawn point on it.
func _check_on_floor(ball: Node3D) -> void:
	var from: Vector3 = MDKMeshBuilder.to_godot(ball.mdk_position) + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_REACH, RAY_LAYER)
	var hit := ball.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(not hit.is_empty(), "%s in the air at %s" % [BALL, ball.mdk_position])
	if hit.is_empty():
		return

	var lowest := INF
	for part: PackedVector3Array in ball.get_pose():
		for v in part:
			lowest = minf(lowest, (ball.global_transform * MDKMeshBuilder.to_godot(v)).y)
	var gap: float = lowest - hit.position.y
	_expect(absf(gap) <= FLOOR_TOLERANCE, "%s's lowest point %.2f off the floor" % [BALL, gap])


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test: in LEVEL8's GUNT_10 a winged alien XG walked into the arena's centre hole (x -61..-25
## at y 3327; the X10_CAP platform over it stops Kurt only) and slid out of sight below the -400
## floor, so the script waiting for the last XG never went on. The original's if_no_floor_at
## (0x45694b, probe 0x46046c) tests a point dx ahead the way add_vel_local does (-dx along the yaw:
## the scripts' -20 is 20 units ahead), from z + 3 down to z - 3 (or z + depth), up-facing faces of
## the object's arena only; the XG turns away at the edge.
## Run: godot --headless --audio-driver Dummy --path . -s tests/no_floor_test.gd
extends SceneTree

const LEVEL := 8
const ARENA := "GUNT_10"
const ALIEN := "XG"
## The XG's walk loop (0x22134): edge and wall checks, turns.
const WALK_SCRIPT := 0x22134
## West of the hole, facing it (yaw 0 is +x).
const START := Vector3(-85.0, 3327.0, -399.0)
## Behind the XG, out of its sight.
const KURT_SPOT := Vector3(-150.0, 3327.0, -399.0)
## The pace 0x223a3 sets before the walk.
const MAX_SPEED := 40.0
const ACCELERATION := 25.0
const DECELERATION := 30.0
## Physics frames (60 per second): 15 s.
const WALK_FRAMES := 900
## The hole's west edge at y 3327, and the XG's longest edge check (if_no_floor_at -20).
const HOLE_WEST := -61.0
const EDGE_REACH := 20.0
## The ring around the hole slopes down to about -410 at its rim; walking bumps.
const LOWEST_FLOOR := -410.0
const FEET_REACH := 5.0
## `MDKObject.FLAG_GRAVITY | FLAG_COLLIDES` (the class needs autoloads not there when this compiles).
const WALKER_FLAGS := 0x2 | 0x4
## `Level.RAY_LAYER`.
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
	scripts.teleport_kurt(ARENA, KURT_SPOT, 0.0)
	await physics_frame
	await physics_frame

	var controller: Node = scripts.get_arena_state(ARENA).controller
	var alien: Node3D = scripts.spawn(controller, ALIEN, START, 0.0, -1, WALK_SCRIPT, false)
	_expect(alien != null, "no %s" % ALIEN)
	if alien == null:
		_finish()
		return
	alien.flags |= WALKER_FLAGS
	alien.max_speed = MAX_SPEED
	alien.acceleration = ACCELERATION
	alien.deceleration = DECELERATION

	# Walk for a while: it reaches the edge, never sinks below the ring's floor and ends on it.
	var farthest: float = alien.mdk_position.x
	var lowest: float = alien.mdk_position.z
	for i in WALK_FRAMES:
		await physics_frame
		farthest = maxf(farthest, alien.mdk_position.x)
		lowest = minf(lowest, alien.mdk_position.z)

	_expect(farthest > HOLE_WEST - EDGE_REACH, "the XG didn't reach the edge: %.1f" % farthest)
	_expect(lowest > LOWEST_FLOOR - FEET_REACH, "the XG fell off the floor: z %.1f" % lowest)
	var from: Vector3 = MDKMeshBuilder.to_godot(alien.mdk_position) + Vector3.UP * FEET_REACH
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FEET_REACH * 2.0, RAY_LAYER)
	var hit := alien.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(not hit.is_empty(), "the XG ended off the floor: %s" % alien.mdk_position)
	_finish()


func _finish() -> void:
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

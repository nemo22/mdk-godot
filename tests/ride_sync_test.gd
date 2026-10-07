## Bug test (playtest): riding LEVEL7's XD2 or XE drew a ghost. Kurt moves each physics step (60
## per second), the objects each tick (30). The XD2 took Kurt's place only each tick, and Kurt took
## the XE's place before it moved, so every other frame drew them up to a unit apart.
## Run: godot --headless --audio-driver Dummy --path . -s tests/ride_sync_test.gd
extends SceneTree

const LEVEL := 7
## The XD2 in DANT_9 (as `tests/walker_ride_test.sh`), walked forward.
const WALKER := "XD2"
const WALKER_SPOT := Vector3(46.0, 4807.0, -25.0)
const WALKER_YAW := 270.0
## The comm device of DANT_5 calls the XE (as `main.gd`'s `--bomber`).
const BOMBER := "XE"
const BOMBER_ARENA := "DANT_5"
const BOMBER_SPOT := Vector3(100.0, 2320.0, -60.0)
const BOMBER_CALL_GROUP := 16
## `MDKScriptRuntime.HIT_CHAIN_GUN`, `MDKRides.FLAG_RIDEABLE` (the classes need autoloads not there
## when this script compiles).
const HIT_CHAIN_GUN := 2
const FLAG_RIDEABLE := 0x2000000
## Physics frames (60 per second).
const SECOND := 60
const TRACE_SECONDS := 4
const WAIT_SECONDS := 30
const TOLERANCE := 0.01

var _failures := 0
var _scripts: Node
var _kurt: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	_scripts = main.get_node("Scripts")
	_kurt = main.get_node("Kurt")
	var level: Node = main.get_node("Level")
	while _scripts.tick_count() == 0:
		await physics_frame

	# The XD2, walked forward.
	_scripts.teleport_kurt(level.get_arena_at(MDKMeshBuilder.to_godot(WALKER_SPOT)), WALKER_SPOT, WALKER_YAW)
	await _frames(SECOND / 2)
	var walker: Node = _scripts.find_object_named(WALKER)
	_scripts.rides.ride_walker(walker)
	Input.action_press(&"move_forward")
	await _trace(walker)
	Input.action_release(&"move_forward")
	_scripts.rides.ridden.flags &= ~FLAG_RIDEABLE
	await _frames(SECOND)

	# The XE, once it flies off with Kurt.
	_scripts.teleport_kurt(BOMBER_ARENA, BOMBER_SPOT, 0.0)
	await _frames(SECOND)
	_scripts.hit_group(BOMBER_ARENA, BOMBER_CALL_GROUP, 1, HIT_CHAIN_GUN, 0)
	var xe: Node = null
	for i in WAIT_SECONDS * SECOND:
		xe = _rideable(BOMBER)
		if xe:
			break
		await physics_frame
	_expect(xe != null, "no rideable %s" % BOMBER)
	if xe:
		var top: float = _scripts.get_world_bounds(xe).end.z
		_kurt.teleport(MDKMeshBuilder.to_godot(Vector3(xe.mdk_position.x, xe.mdk_position.y, top + 1.0)), _kurt.yaw)
		for i in WAIT_SECONDS * SECOND:
			if _scripts.rides.bomber:
				break
			await physics_frame
		_expect(_scripts.rides.bomber != null, "not on the %s" % BOMBER)
		await _trace(xe)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Each physics frame, once everything moved: how far Kurt is from what he rides.
func _trace(ride: Node) -> void:
	var worst := 0.0
	var start: Vector3 = ride.mdk_position
	for i in TRACE_SECONDS * SECOND:
		await physics_frame
		var feet := MDKMeshBuilder.to_godot(ride.mdk_position)
		worst = maxf(worst, _kurt.global_position.distance_to(feet))
	var moved: float = ride.mdk_position.distance_to(start)
	print("%s moved %.1f, Kurt up to %.3f from it" % [ride.type_name, moved, worst])
	_expect(moved > 1.0, "%s didn't move" % ride.type_name)
	_expect(worst < TOLERANCE, "Kurt %.3f from the %s" % [worst, ride.type_name])


func _rideable(type_name: String) -> Node:
	for obj in _scripts.objects:
		if obj.type_name == type_name and obj.flags & FLAG_RIDEABLE:
			return obj
	return null


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

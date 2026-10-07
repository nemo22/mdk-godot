## Kurt against an object, by its flags (the original's rule): a wall has neither 0x10 nor 0x800
## (`damp_collide_move` 0x465e34), a floor has 0x100 and not 0x10 (`damp_platform_floor`
## 0x41d2c4); 0x800000 plays no part. E.g. the ridden snowboard (0x800900) is a floor only.
## A level 3 turret is put in front of Kurt on HMO_1's floor with each set of flags (the scripts
## stopped).
## Run: godot --headless --audio-driver Dummy --path . -s tests/object_flags_test.gd
extends SceneTree

const LEVEL := 3
const ARENA := "HMO_1"
## The floor between the two grunts.
const SPOT := Vector3(-15.0, 155.0, 130.0)
const BOX := "XTUR"
## In front of Kurt (+y), its bottom on the floor.
const AHEAD := 14.0
const START_GAP := 6.0
## Physics frames (60 per second).
const SETTLE := 30
const DROP := 60
const WALK := 90
const DROP_HEIGHT := 4.0
## Feet this close to the top: he stands on it.
const TOLERANCE := 1.0
## MDK yaw facing +y.
const NORTH := 90.0

enum Meets { PASSES_THROUGH = 0, BLOCKED = 1, STANDS_ON = 2, SOLID = 3 }

## Flags and what Kurt must do.
const CASES := [
	[0x0, Meets.BLOCKED],
	[0x100, Meets.SOLID],
	[0x800100, Meets.SOLID],
	[0x10, Meets.PASSES_THROUGH],
	[0x800110, Meets.PASSES_THROUGH],
	[0x800, Meets.PASSES_THROUGH],
	[0x900, Meets.STANDS_ON],
	[0x800900, Meets.STANDS_ON],
	[0x910, Meets.PASSES_THROUGH],
]

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
	while _scripts.tick_count() == 0:
		await physics_frame
	for obj in _scripts.objects:
		obj.restart = 0
	_scripts.teleport_kurt(ARENA, SPOT, NORTH)
	await _frames(DROP)
	var feet: Vector3 = _scripts.to_mdk(_kurt.global_position)
	var box: Node = _first(BOX, ARENA)
	_expect(box != null, "no %s" % BOX)
	if not box:
		_finish()
		return

	# The box, still, ahead of Kurt.
	box.velocity = Vector3.ZERO
	var bounds: AABB = _scripts.get_world_bounds(box)
	box.set_mdk_position(box.mdk_position + Vector3(feet.x, feet.y + AHEAD, feet.z) - Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z))
	for case in CASES:
		box.flags = case[0]
		await _frames(1)
		bounds = _scripts.get_world_bounds(box)
		var top := bounds.end.z
		var centre := bounds.get_center()

		# Dropped on its top.
		_scripts.teleport_kurt("", Vector3(centre.x, centre.y, top + DROP_HEIGHT), NORTH)
		await _frames(DROP)
		var stands := absf(_scripts.to_mdk(_kurt.global_position).z - top) < TOLERANCE

		# Walking at it from the floor.
		_scripts.teleport_kurt("", Vector3(centre.x, bounds.position.y - START_GAP, feet.z), NORTH)
		await _frames(SETTLE)
		Input.action_press(&"move_forward")
		await _frames(WALK)
		Input.action_release(&"move_forward")
		var blocked: bool = _scripts.to_mdk(_kurt.global_position).y < bounds.position.y

		var meets := (Meets.BLOCKED if blocked else 0) | (Meets.STANDS_ON if stands else 0)
		print("flags 0x%x: %s" % [case[0], Meets.keys()[meets]])
		_expect(meets == case[1], "flags 0x%x: %s, not %s" % [case[0], Meets.keys()[meets], Meets.keys()[case[1]]])
		await _frames(SETTLE)
	_finish()


func _first(type_name: String, arena: String) -> Node:
	for obj in _scripts.objects:
		if obj.type_name == type_name and obj.arena == arena and not obj.dead:
			return obj
	return null


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _finish() -> void:
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

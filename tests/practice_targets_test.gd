## Bug test: LEVEL7's practice room (DANT_2). Shooting the crate makes XGEN spit three targets,
## each flying to its pedestal (`move_to_point`, opcode 200, 0x459555). The step scaled by the
## straight-line distance, so the 2nd and 3rd stuck to the glass, sideways (docs/practice_room.md).
## Run: godot --headless --audio-driver Dummy --path . -s tests/practice_targets_test.gd
extends SceneTree

const LEVEL := 7
const ROOM := "DANT_2"
const CRATE := "XBANG"
const TARGET := "XGTARG"
const KURT_SPOT := Vector3(0.0, 900.0, -27.0)
const KURT_YAW := 90.0
## Pedestal tops the targets fly to (move_to_point at 0x5458, 0x5490, 0x54c8).
const PEDESTALS: Array[Vector3] = [Vector3(-17, 941, -20), Vector3(-24, 959, -15), Vector3(-23, 977, -10)]
const TOLERANCE := 1.0
## Physics frames (60 per second): settle, then 10 s for the targets to land.
const SETTLE_FRAMES := 60
const LANDING_FRAMES := 600

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
	scripts.teleport_kurt(ROOM, KURT_SPOT, KURT_YAW)
	for i in SETTLE_FRAMES:
		await physics_frame

	for obj in scripts.objects:
		if obj.type_name == CRATE and obj.arena == ROOM and not obj.dead:
			scripts.kill(obj)
			break
	for i in LANDING_FRAMES:
		await physics_frame

	var targets: Array = scripts.objects.filter(func(o): return o.type_name == TARGET and not o.dead)
	for t in targets:
		print("%s at %s" % [TARGET, t.mdk_position])
	_expect(targets.size() == PEDESTALS.size(), "targets: %d" % targets.size())
	for pedestal in PEDESTALS:
		var landed := targets.any(func(t): return t.mdk_position.distance_to(pedestal) < TOLERANCE)
		_expect(landed, "nothing on the pedestal at %s" % pedestal)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test (found by the C# port's soak tour): teleported onto a doorway before the first tick,
## Kurt moved through it, but the first tick forgot the teleport and took his new place as the
## previous one; he stayed in the room while in the corridor and fell out when it went. The
## original's teleport sets both positions (0x41bce4).
## Run: godot --headless --audio-driver Dummy --path . -s tests/teleport_first_tick_test.gd
extends SceneTree

const LEVEL := 4
const ROOM := "MEAT_7"
const CORRIDOR := "CMEAT_7"
## MDK coordinates of the doorway's plane (connection 1012) and of the floor by it.
const DOORWAY := 14822.0
const FLOOR := 21.0
## A script tick (30 per second) runs within this many physics frames (60 per second).
const TICK_FRAMES := 3

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	while scripts.level == null:
		await process_frame
	_expect(scripts.tick_count() == 0, "ticks already ran: %d" % scripts.tick_count())

	# On the doorway, then a step through it, all before the first tick.
	scripts.teleport_kurt(ROOM, Vector3(0.0, DOORWAY, FLOOR), 90.0)
	var kurt: Node = main.get_node("Kurt")
	# MDK (x, y, z) is Godot (x, z, −y).
	kurt.teleport(Vector3(0.0, FLOOR, -(DOORWAY + 3.0)), kurt.yaw)
	for i in TICK_FRAMES:
		await physics_frame

	_expect(scripts.tick_count() > 0, "no tick ran")
	_expect(scripts.current_arena == CORRIDOR, "through the doorway: %s" % scripts.current_arena)
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

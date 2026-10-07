## Bug test (playtest): nothing showed a fan blowing on level 6. The fans' fire sparks start a
## quarter unit below the grate (0x414230) and bounced under it until they died. The original puts a
## piece that hits something at the contact (0x4061d8), a segment starting on a plane crosses
## nothing (0x421470), and the fans lift a piece after a bounce too, so the spark rises through.
## Run: godot --headless --audio-driver Dummy --path . -s tests/fan_spark_test.gd
extends SceneTree

const LEVEL := 6
const ARENA := "OLYM_6"
## The arena's fan (hotspot 1): its bottom, 68 units below its top.
const FAN_BOTTOM := -2209.0
const NEAR_FAN := Vector3(-1945.0, 2900.0, -2211.0)
const YAW := 90.0
## Sparks rising through the box get this far above the grate.
const RISEN := 20.0
## Physics frames (60 per second).
const FRAMES := 600

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
	scripts.teleport_kurt(ARENA, NEAR_FAN, YAW)

	var highest := -INF
	for i in FRAMES:
		kurt.teleport(MDKMeshBuilder.to_godot(NEAR_FAN), deg_to_rad(YAW - 90.0))
		await physics_frame
		# Sparks are the pieces without materials.
		for piece in scripts.debris._pieces:
			if piece.materials.is_empty() and piece.arena == ARENA:
				highest = maxf(highest, piece.center.z)
	print("highest spark %.2f" % highest)
	_expect(highest > FAN_BOTTOM + RISEN, "sparks stay under the grate (highest %.2f)" % highest)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test (playtest): Kurt fell behind LEVEL6's lift XTR_1000 (the XTR he stands on in OLYM_8).
## It drops up to 25 units a tick (30 per second); Kurt must ride it (`damp_platform_floor`
## 0x41d2c4: a platform carries Kurt standing on it), not fall after it.
## Run: godot --headless --audio-driver Dummy --path . -s tests/platform_carry_test.gd
extends SceneTree

const LEVEL := 6
## Kurt on the lift (as mdk-sdl's `tests/carry_test.sh`); stepping on it sends it down.
const ARENA := "OLYM_8"
const SPOT := Vector3(-1658.0, 3381.0, -1869.9)
const LIFT := "XTR"
## Physics frames (60 per second).
const SECOND := 60
const TRACE_SECONDS := 4
## Kurt's feet against the lift's top (its box tilts down its slope).
const TOLERANCE := 0.5
const MIN_DROP := 50.0

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
	scripts.teleport_kurt(ARENA, SPOT, 0.0)
	var lift: Node = _nearest(scripts, LIFT, SPOT)
	_expect(lift != null, "no %s" % LIFT)
	if not lift:
		_finish()
		return

	# Each physics frame, once the lift moved: Kurt's feet against its top.
	var start: float = lift.mdk_position.z
	var worst := 0.0
	var riding := 0
	for i in TRACE_SECONDS * SECOND:
		await physics_frame
		var top: float = scripts.get_world_bounds(lift).end.z
		var feet: float = scripts.to_mdk(kurt.global_position).z
		if start - lift.mdk_position.z < 1.0:
			continue
		riding += 1
		worst = maxf(worst, absf(feet - top))
	var drop: float = start - lift.mdk_position.z
	print("%s dropped %.1f, Kurt up to %.2f from its top over %d frames" % [LIFT, drop, worst, riding])
	_expect(drop > MIN_DROP, "%s didn't go down" % LIFT)
	_expect(worst < TOLERANCE, "Kurt %.2f from the %s" % [worst, LIFT])
	_finish()


## The object of that type closest to `spot` (OLYM_8 has four XTR lifts).
func _nearest(scripts: Node, type_name: String, spot: Vector3) -> Node:
	var best: Node = null
	for obj in scripts.objects:
		if obj.type_name != type_name:
			continue
		if not best or obj.mdk_position.distance_to(spot) < best.mdk_position.distance_to(spot):
			best = obj
	return best


func _finish() -> void:
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

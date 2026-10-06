## Bug test: LEVEL6 OLYM_3, three grunts taunt behind a glass wall; a sniper mortar round lobbed
## through its small opening kills them. Behind the opening is a face seen from its back (y = −149).
## The original moves the round with a 0.5 box (`bsp_sweep_box`, 0x462708) that only faces' fronts
## stop, so it passes; a two-sided ray stopped it. The round goes off at 7 s by XG_1001, the grunts
## fall with their floor and SW_KEY flies out.
## Run: godot --headless --audio-driver Dummy --path . -s tests/mortar_opening_test.gd
extends SceneTree

const LEVEL := 6
const KURT_SPOT := Vector3(-1636.9, -76.5, -647.0)
const KURT_YAW := 241.0
const SNIPER_PITCH := -32.0
const MORTAR := 4
const GRUNT := "XG"
const GRUNTS := 3
const KEY := "SW_KEY"
## The key flies out of the grunts' room (C# port: 62 units).
const KEY_FLIGHT := 10.0
## Physics frames (60 per second): settle, then 11 s.
const SETTLE_FRAMES := 30
const SHOT_FRAMES := 660

var _failures := 0
var _scripts: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	_scripts = main.get_node("Scripts")
	var kurt: Node = main.get_node("Kurt")
	var level: Node = main.get_node("Level")
	while _scripts.tick_count() == 0:
		await physics_frame
	var arena: String = level.get_arena_at(MDKMeshBuilder.to_godot(KURT_SPOT))
	_scripts.teleport_kurt(arena, KURT_SPOT, KURT_YAW)
	for i in SETTLE_FRAMES:
		await physics_frame
	var grunts := _grunts()
	_expect(grunts.size() == GRUNTS, "grunts before: %d" % grunts.size())
	var key: Node = _scripts.objects.filter(func(o): return o.type_name == KEY and o.arena == arena)[0]
	var key_start: Vector3 = key.mdk_position

	# One mortar round, aimed up through the opening.
	kurt._enter_sniper(true)
	kurt.sniper_pitch = SNIPER_PITCH
	_expect(kurt.sniper_fire.call(MORTAR), "not fired")
	for i in SHOT_FRAMES:
		await physics_frame

	_expect(_grunts().is_empty(), "grunts alive: %d" % _grunts().size())
	_expect(key.mdk_position.distance_to(key_start) > KEY_FLIGHT, "%s still at %s" % [KEY, key.mdk_position])

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _grunts() -> Array:
	return _scripts.objects.filter(func(o): return o.type_name == GRUNT and not o.dead)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

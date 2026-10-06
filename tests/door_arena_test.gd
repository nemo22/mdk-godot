## Bug test (found by playtest): on LEVEL7, back from DANT_2 to the start tunnel CDANT_1, the
## doorway showed the sky. The tunnel's door stayed in CDANT_1; once that arena was put away the door
## froze shut, undrawn and not solid, so it never opened to show the tunnel. The original moves a
## door into Kurt's arena when he is on its other side (0x43cc68), and into an arena being loaded
## from its neighbours (`arena_load` 0x419d00), turned around (0x43ca00).
## Run: godot --headless --audio-driver Dummy --path . -s tests/door_arena_test.gd
extends SceneTree

const LEVEL := 7
const TUNNEL := "CDANT_1"
const ROOM := "DANT_2"
const CORRIDOR := "CDANT_2"
## The tunnel's door into DANT_2 (`spawn_connector` of CDANT_1), at yaw 90 (MDK).
const TUNNEL_DOOR := Vector3(0.0, 673.0, -3.0)
const DOOR_YAW := 90.0
const TURNED_YAW := 270.0
const FLOOR := -3.0
const TUNNEL_Y := 655.0
## The room's floor a little in, and far enough for the door to close.
const NEAR_DOOR := Vector3(0.0, 688.0, -5.0)
const FAR_FROM_DOOR := Vector3(0.0, 750.0, -8.0)
const CORRIDOR_SPOT := Vector3(100.0, 990.0, -6.0)
const SECOND_TICKS := 30
## A script tick (30 per second) runs within this many physics frames (60 per second).
const TICK_FRAMES := 2

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

	await _door_shows_tunnel_on_the_way_back()
	await _loaded_arena_pulls_its_doors()

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Kurt goes through the tunnel's door into DANT_2, away until it shuts, and back: it opens again
## and shows the tunnel.
func _door_shows_tunnel_on_the_way_back() -> void:
	_scripts.teleport_kurt(TUNNEL, Vector3(0.0, TUNNEL_Y, FLOOR), DOOR_YAW)
	for y in range(int(TUNNEL_Y), int(NEAR_DOOR.y)):
		await _stand_at(Vector3(0.0, y, FLOOR), 1)
	_expect(_scripts.current_arena == ROOM, "through the door: %s" % _scripts.current_arena)

	# Into the room, out of the door's reach: it closes and the tunnel goes.
	await _stand_at(FAR_FROM_DOOR, 3 * SECOND_TICKS)
	_expect(not _scripts.is_live_arena(TUNNEL), "tunnel still drawn")

	# Back to the door.
	await _stand_at(NEAR_DOOR, 2 * SECOND_TICKS)
	var door := _door_at(TUNNEL_DOOR)
	_expect(door.arena == ROOM and door.connects == TUNNEL, "door %s → %s" % [door.arena, door.connects])
	_expect(_scripts.is_live_arena(TUNNEL), "tunnel not drawn on the way back")


## Loading DANT_2 ahead (from CDANT_2) pulls the tunnel's door into it, turned around.
func _loaded_arena_pulls_its_doors() -> void:
	_scripts.teleport_kurt(TUNNEL, Vector3(0.0, TUNNEL_Y, FLOOR), DOOR_YAW)
	await _stand_at(Vector3(0.0, TUNNEL_Y, FLOOR), 1)
	_scripts.teleport_kurt(CORRIDOR, CORRIDOR_SPOT, 0.0)
	await _stand_at(CORRIDOR_SPOT, 1)
	# Back in the tunnel's hands since Kurt was put in CDANT_1.
	var door := _door_at(TUNNEL_DOOR)
	_expect(door.arena == TUNNEL, "teleported: door in %s" % door.arena)

	_scripts.preload_arena(ROOM)
	_expect(door.arena == ROOM and door.connects == TUNNEL, "loaded: door %s → %s" % [door.arena, door.connects])
	_expect(is_equal_approx(door.yaw, TURNED_YAW), "loaded: door yaw %.1f" % door.yaw)


## Keeps Kurt at a spot (MDK) for that many ticks.
func _stand_at(feet: Vector3, ticks: int) -> void:
	for i in ticks:
		_kurt.teleport(MDKMeshBuilder.to_godot(feet), deg_to_rad(DOOR_YAW - 90.0))
		for frame in TICK_FRAMES:
			await physics_frame


func _door_at(position: Vector3) -> Node:
	for obj in _scripts.objects:
		if not obj.dead and obj.flags & MDKObject.FLAG_DOOR and obj.mdk_position.distance_to(position) < 1.0:
			return obj
	return null


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

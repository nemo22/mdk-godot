## Bug test (found by playtest): LEVEL4's sub airlock kept Kurt in. Script flag word 5 is the
## object's own door state (obj+0x312, 0x440a34), but it read the linked object's flags. Past the
## airlock door #1998 its script waits for word 5 bit 3 (closed), locks it and opens #1999 to
## MEAT_6; #1999 never opened. Doors locked until nuked (LEVEL6-8) wait for bit 6 (locked) the
## same way and went on at once.
##   MEAT_5 ──hatch #1000 (y 13353)──► airlock ──#1998 (y 13375)──► CMEAT_5 ──#1999 (y 13406)──► MEAT_6
## Run: godot --headless --audio-driver Dummy --path . -s tests/door_flags_test.gd
extends SceneTree

const SECOND_TICKS := 30
## A script tick (30 per second) runs within this many physics frames (60 per second).
const TICK_FRAMES := 2
const DOOR_FLAGS := 5
const DOOR_CLOSED := 0x8
const DOOR_LOCKED := 0x40
const DOOR_OPEN := 0x1
const DOOR_OPENING := 0x2
const KEY := "SW_KEY"
## The key in the inventory (KurtInventory.Item.KEY; the class needs autoloads to compile).
const KEY_ITEM := 7
## Long enough for Kurt to outlive the nuke.
const INVULNERABLE := 1000.0

## The airlock (LEVEL4): Kurt throws the key in the nuke's box (y 13306..13351), waits in the
## airlock (y 13354..13376) for the hatch to shut behind him, then goes past #1998 to #1999.
const AIRLOCK_LEVEL := 4
const AIRLOCK_ARENA := "MEAT_5"
const AIRLOCK_X := -126.0
const AIRLOCK_FLOOR := -1989.0
const AHEAD := 90.0
const NUKE_SPOT := 13310.0
const AIRLOCK := 13365.0
const BEFORE_LAST_DOOR := 13398.0
const OUT_DOOR := 1999
const NUKE_SECONDS := 10
const WAIT_SECONDS := 5

## Doors locked until nuked: [level, arena, door, Kurt's spot before it, his yaw, the key's throw
## yaw]. The key goes away from the door: here thrown items pass closed XCORRDOR doors. In GUNT_6
## the floor drops behind Kurt, so he stands further in; in CGUNT_6 it hits the corridor's wall.
## (CDANT_9's door tests bit 64 & 31 = 0, open: it goes on at once, in the original too.)
const LOCKED_DOORS := [
	[6, "OLYM_1", Vector3(-1142, -931, -73), Vector3(-1142, -946, -73), 90.0, 270.0],
	[7, "DANT_1", Vector3(0, 481, 15), Vector3(0, 466, 15), 90.0, 270.0],
	[7, "DANT_5", Vector3(252, 3633, -71), Vector3(252, 3618, -71), 90.0, 270.0],
	[7, "CDANT_5", Vector3(252, 3633, -71), Vector3(252, 3648, -71), 270.0, 90.0],
	[7, "DANT_9", Vector3(276, 4782, -37), Vector3(261, 4782, -37), 0.0, 180.0],
	[8, "GUNT_1", Vector3(-68, 93, 12), Vector3(-53, 93, 12), 180.0, 0.0],
	[8, "GUNT_6", Vector3(75, 2571, -269), Vector3(105, 2571, -278), 180.0, 180.0],
	[8, "CGUNT_6", Vector3(75, 2571, -269), Vector3(60, 2571, -269), 0.0, 90.0],
]
const SETTLE_SECONDS := 2

var _failures := 0
var _main: Node
var _scripts: Node
var _kurt: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _load(AIRLOCK_LEVEL)
	_word_five_is_door_state()
	await _airlock_opens_to_meat6()
	for case in LOCKED_DOORS:
		await _load(case[0])
		await _nuke_unlocks_door(case[1], case[2], case[3], case[4], case[5])

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## A fresh game on a level.
func _load(level: int) -> void:
	if _main:
		_main.free()
	root.get_node("GameState").level = level
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	_scripts = _main.get_node("Scripts")
	_kurt = _main.get_node("Kurt")
	while _scripts.tick_count() == 0:
		await physics_frame


## Word 5 reads and writes a door's own state, not its linked object's flags.
func _word_five_is_door_state() -> void:
	var door: Variant = MDKObject.new()
	door.flags |= MDKObject.FLAG_DOOR
	door.door_state = DOOR_CLOSED
	door.linked = MDKObject.new()
	var vm: Variant = _scripts.vm
	_expect(vm._get_flags(door, DOOR_FLAGS) == DOOR_CLOSED, "word 5 reads %x" % vm._get_flags(door, DOOR_FLAGS))
	vm._set_flags(door, DOOR_FLAGS, DOOR_CLOSED | DOOR_LOCKED)
	_expect(door.door_state == DOOR_CLOSED | DOOR_LOCKED, "word 5 wrote %x" % door.door_state)
	_expect(door.linked.script_flags == 0, "word 5 wrote the linked object's flags")
	door.linked.free()
	door.free()


func _airlock_opens_to_meat6() -> void:
	var start := Vector3(AIRLOCK_X, NUKE_SPOT, AIRLOCK_FLOOR)
	_scripts.teleport_kurt(AIRLOCK_ARENA, start, AHEAD)
	await _stand_at(start, AHEAD, 1)

	# The nuke goes off by the hatch.
	_throw_key(AHEAD)
	await _stand_at(start, AHEAD, NUKE_SECONDS * SECOND_TICKS)

	# Through the hatch into the airlock; it shuts behind him.
	await _walk(NUKE_SPOT, AIRLOCK)
	await _stand_at(Vector3(AIRLOCK_X, AIRLOCK, AIRLOCK_FLOOR), AHEAD, WAIT_SECONDS * SECOND_TICKS)

	# Through #1998, then wait for it to shut.
	await _walk(AIRLOCK, BEFORE_LAST_DOOR)
	await _stand_at(Vector3(AIRLOCK_X, BEFORE_LAST_DOOR, AIRLOCK_FLOOR), AHEAD, WAIT_SECONDS * SECOND_TICKS)

	var door := _door_with_id(OUT_DOOR)
	_expect(door != null and door.door_state & (DOOR_OPEN | DOOR_OPENING) != 0,
			"airlock: #1999 %s" % ("missing" if door == null else "state %x" % door.door_state))


## Kurt stands before the door facing it: it stays locked and its script waits. He throws the key;
## the nuke unlocks the door, its script goes on, and the door opens as he steps closer.
func _nuke_unlocks_door(arena: String, at: Vector3, feet: Vector3, yaw: float, throw: float) -> void:
	_scripts.teleport_kurt(arena, feet, yaw)
	await _stand_at(feet, yaw, SETTLE_SECONDS * SECOND_TICKS)

	# Locked, its script waiting.
	var door := _door_at(at)
	if door == null:
		_expect(false, "%s: no door" % arena)
		return
	var waiting: int = door.restart
	await _stand_at(feet, yaw, SETTLE_SECONDS * SECOND_TICKS)
	_expect(door.restart == waiting, "%s: script went on before the nuke" % arena)
	_expect(door.door_state & DOOR_LOCKED != 0, "%s: not locked (%x)" % [arena, door.door_state])

	# The nuke.
	_throw_key(throw)
	await _stand_at(feet, yaw, NUKE_SECONDS * SECOND_TICKS)
	_expect(door.restart != waiting, "%s: script still waits" % arena)
	_expect(door.door_state & DOOR_LOCKED == 0, "%s: still locked (%x)" % [arena, door.door_state])

	# Closer: it opens.
	await _stand_at(feet.lerp(at, 0.5), yaw, SETTLE_SECONDS * SECOND_TICKS)
	_expect(door.door_state & (DOOR_OPEN | DOOR_OPENING) != 0, "%s: shut (%x)" % [arena, door.door_state])


## Kurt takes the key and throws it along yaw: it becomes the nuke.
func _throw_key(yaw: float) -> void:
	var inventory: Variant = _kurt.inventory
	inventory.collect(KEY, _kurt)
	for i in inventory.slots.size():
		if inventory.slots[i].item == KEY_ITEM:
			inventory.selected = i
	# Outside a tick the throw's yaw is the last object's target.
	_scripts.target_yaw = yaw
	_scripts.items.use_item()


## Walks Kurt along +y in the airlock, a unit a tick.
func _walk(from: float, to: float) -> void:
	var y := from
	while y < to:
		await _stand_at(Vector3(AIRLOCK_X, y, AIRLOCK_FLOOR), AHEAD, 1)
		y += 1.0


## Keeps Kurt at a spot (MDK) for that many ticks, unhurt.
func _stand_at(feet: Vector3, yaw: float, ticks: int) -> void:
	for i in ticks:
		_kurt.invulnerable = INVULNERABLE
		_kurt.teleport(MDKMeshBuilder.to_godot(feet), deg_to_rad(yaw - 90.0))
		for frame in TICK_FRAMES:
			await physics_frame


func _door_at(position: Vector3) -> Node:
	for obj in _scripts.objects:
		if not obj.dead and obj.flags & MDKObject.FLAG_DOOR and obj.mdk_position.distance_to(position) < 1.0:
			return obj
	return null


func _door_with_id(id: int) -> Node:
	for obj in _scripts.objects:
		if not obj.dead and obj.flags & MDKObject.FLAG_DOOR and obj.instance_id == id:
			return obj
	return null


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

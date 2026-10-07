## Bug test: LEVEL8's start ship (GUNT_1 XBSHIP_0) is indestructible (65000), but a sniper round on
## one of its 7 blue turrets T1-T7 blows it off; without them it falls and explodes. Rounds hit the
## parts' faces (0x414668), not their boxes: the hull's box holds the turrets, so it stopped them.
## Run: godot --headless --audio-driver Dummy --path . -s tests/big_ship_test.gd
extends SceneTree

const LEVEL := 8
const ARENA := "GUNT_1"
const SHIP := "XBSHIP"
## On the floor, every turret in sight once the ship hovers at (62, 680, 207).
const KURT_SPOT := Vector3(0.0, 160.0, 10.0)
const KURT_YAW := 90.0
const EYE_HEIGHT := 6.0
const BULLET := 0
const TURRETS := 0x7F
## The turrets' parts: T and a digit (set_weak_parts "T", 1).
const TURRET_PREFIX := "T"
## Physics frames (60 per second): the ship arrives after about 20 s.
const ARRIVE_FRAMES := 25 * 60
const SHOOT_FRAMES := 30 * 60
const CRASH_FRAMES := 20 * 60

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
	while _scripts.tick_count() == 0:
		await physics_frame
	_scripts.teleport_kurt(ARENA, KURT_SPOT, KURT_YAW)
	for i in ARRIVE_FRAMES:
		await physics_frame

	var ship: Node = _scripts.objects.filter(func(o): return o.type_name == SHIP)[0]
	var eye: Vector3 = _scripts.kurt_position + Vector3(0.0, 0.0, EYE_HEIGHT)

	# Bullets at each remaining turret in turn.
	var i := 0
	while i < SHOOT_FRAMES and ship.hidden_parts & TURRETS != TURRETS:
		var targets := _turret_centres(ship)
		var to: Vector3 = targets[i % targets.size()] - eye
		var yaw := rad_to_deg(atan2(to.y, to.x))
		var pitch := -rad_to_deg(atan2(to.z, Vector2(to.x, to.y).length()))
		_scripts.sniper_rounds.fire(BULLET, eye, yaw, pitch, null)
		await physics_frame
		i += 1
	_expect(ship.hidden_parts & TURRETS == TURRETS, "turrets left: %x" % (~ship.hidden_parts & TURRETS))

	i = 0
	# A dead ship's node goes.
	while i < CRASH_FRAMES and is_instance_valid(ship) and not ship.dead and ship.health > 0:
		await physics_frame
		i += 1
	_expect(not is_instance_valid(ship) or ship.dead or ship.health == 0, "ship alive")

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## The centres of the turrets still on the ship, as drawn (MDK space).
func _turret_centres(ship: Node) -> Array:
	var out := []
	var pose: Array = ship.get_pose()
	for p in pose.size():
		var vertices: PackedVector3Array = pose[p]
		if vertices.is_empty() or ship.hidden_parts & (1 << p) or not _is_turret(ship.model.parts[p].name):
			continue
		var centre := Vector3()
		for v in vertices:
			centre += v
		centre /= vertices.size()
		var world: Vector3 = ship.transform * MDKMeshBuilder.to_godot(centre)
		out.push_back(Vector3(world.x, -world.z, world.y))
	return out


func _is_turret(part_name: String) -> bool:
	return part_name.length() == 2 and part_name.begins_with(TURRET_PREFIX) and part_name[1].is_valid_int()


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

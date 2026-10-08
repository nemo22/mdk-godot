## Bug test: LEVEL8 GUNT_5's missile aliens XT (`set_height_offset` 8, a model centred on its
## origin) sank halfway into the floor after their move_to down to it. The original sweeps an
## object's vertical move with its box lowered to z - height offset (0x45e810), so it stops with its
## origin that high above the floor.
## Run: godot --headless --audio-driver Dummy --path . -s tests/height_offset_test.gd
extends SceneTree

const LEVEL := 8
const ARENA := "GUNT_5"
const ALIEN := "XT"
## Inside if_kurt_in_rect (-260, 1636)-(-252, 1773): spawns the XT pair.
const TRIGGER := Vector3(-256.0, 1700.0, -226.0)
## On the lower floor, where the first XT sees Kurt and moves to (-220, 1640, -226).
const IN_SIGHT := Vector3(-240.0, 1580.0, -226.0)
## Physics frames (60 per second): 25 s.
const MOVE_FRAMES := 1500
const FLOOR_REACH := 10.0
const FLOOR_TOLERANCE := 0.5
## `Level.RAY_LAYER` (the class needs autoloads not there when this script compiles).
const RAY_LAYER := 1

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
	scripts.teleport_kurt(ARENA, TRIGGER, 0.0)
	await physics_frame
	await physics_frame
	scripts.teleport_kurt(ARENA, IN_SIGHT, 0.0)
	for i in MOVE_FRAMES:
		await physics_frame

	var aliens: Array = scripts.objects.filter(func(o): return o.type_name == ALIEN and not o.dead)
	_expect(not aliens.is_empty(), "no %s" % ALIEN)
	for alien in aliens:
		_check_on_floor(alien)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## The alien stands on a floor, its lowest drawn point on it.
func _check_on_floor(alien: Node3D) -> void:
	var from: Vector3 = MDKMeshBuilder.to_godot(alien.mdk_position) + Vector3.UP * FLOOR_REACH
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_REACH * 2.0, RAY_LAYER)
	var hit := alien.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(not hit.is_empty(), "%s in the air at %s" % [ALIEN, alien.mdk_position])
	if hit.is_empty():
		return

	var lowest := INF
	for part: PackedVector3Array in alien.get_pose():
		for v in part:
			lowest = minf(lowest, (alien.global_transform * MDKMeshBuilder.to_godot(v)).y)
	var gap: float = lowest - hit.position.y
	_expect(absf(gap) <= FLOOR_TOLERANCE, "%s at %s: lowest point %.2f off the floor" % [ALIEN, alien.mdk_position, gap])


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

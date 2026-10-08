## LEVEL8's forklift puzzle (GUNT_2): the turret garage XPER's death brings a forklift with a
## driver (XFORK script 0x4bc6). Hits past 110 blow the driver and the canopy off; then each hit
## pushes it along the shot (push_hit_dir), its script giving it its health back. On the yellow pad
## (-435..-414, 547..568) it hides the glass (group 1) over the way down.
## Run: godot --headless --audio-driver Dummy --path . -s tests/forklift_test.gd
extends SceneTree

const LEVEL := 8
const ARENA := "GUNT_2"
const FORKLIFT := "XFORK"
const DRIVER := "XFK_HEAD"
const GLASS := 1
## Triangle flag of a hidden group (Level.TRIANGLE_HIDDEN).
const HIDDEN := 0x10
const BULLET := 0
## West of the garage, south of the pad: the forklift drives at him.
const KURT_SPOT := Vector3(-440.0, 548.0, 8.0)
const PAD_CENTER := Vector3(-424.5, 557.5, 8.0)
const PAD_MIN := Vector3(-435.0, 547.0, 7.0)
const PAD_MAX := Vector3(-414.0, 568.0, 9.0)
## Physics frames (60 per second).
const ARRIVE_FRAMES := 2 * 60
const SHOOT_FRAMES := 20 * 60
const FIRE_EVERY := 6
## Shots come from this far behind the forklift (or in front of a wall there), at its middle.
const SHOT_RANGE := 20.0
const WALL_GAP := 1.0
const AIM_HEIGHT := 4.0
const STILL := 0.5

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
	_scripts.teleport_kurt(ARENA, KURT_SPOT, 0.0)
	await _frames(ARRIVE_FRAMES)
	_scripts.kill(_scripts.find_object_named("XPER"))
	await _frames(ARRIVE_FRAMES)
	var forklifts: Array = _scripts.objects.filter(func(o): return o.type_name == FORKLIFT and not o.dead)
	var forklift: Node = forklifts[-1]

	# Shots from Kurt until the driver is gone.
	var driver: int = 1 << forklift.find_part(DRIVER)
	var i := 0
	while i < SHOOT_FRAMES and not forklift.dead and not forklift.hidden_parts & driver:
		if i % FIRE_EVERY == 0:
			_shoot(_scripts.kurt_position + Vector3(0.0, 0.0, AIM_HEIGHT), forklift)
		await physics_frame
		i += 1
	_expect(forklift.hidden_parts & driver != 0, "driver still on")

	# Then one shot at a time from the far side, each once it stands still.
	i = 0
	while i < SHOOT_FRAMES and not forklift.dead and not _on_pad(forklift):
		if Vector2(forklift.velocity.x, forklift.velocity.y).length() < STILL:
			var away: Vector3 = (forklift.mdk_position - PAD_CENTER)
			away.z = 0.0
			away = away.normalized()
			var middle: Vector3 = forklift.mdk_position + Vector3(0.0, 0.0, AIM_HEIGHT)
			var eye := middle + away * SHOT_RANGE
			var wall: Dictionary = _scripts.raycast(middle, eye)
			if not wall.is_empty():
				var point: Vector3 = wall.position
				eye = middle + away * (middle.distance_to(Vector3(point.x, -point.z, point.y)) - WALL_GAP)
			_shoot(eye, forklift)
		await physics_frame
		i += 1
	await _frames(2)

	_expect(not forklift.dead, "forklift dead")
	_expect(_on_pad(forklift), "forklift at %s" % forklift.mdk_position)
	var glass = _scripts.level.arena_groups[ARENA][GLASS]
	_expect(glass.flags & HIDDEN != 0, "glass shown")

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


## A bullet from `eye` at the forklift's middle.
func _shoot(eye: Vector3, forklift: Node) -> void:
	var to: Vector3 = forklift.mdk_position + Vector3(0.0, 0.0, AIM_HEIGHT) - eye
	var yaw := rad_to_deg(atan2(to.y, to.x))
	var pitch := -rad_to_deg(atan2(to.z, Vector2(to.x, to.y).length()))
	_scripts.sniper_rounds.fire(BULLET, eye, yaw, pitch, null)


func _on_pad(forklift: Node) -> bool:
	var p: Vector3 = forklift.mdk_position
	return p.clamp(PAD_MIN, PAD_MAX) == p


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test: LEVEL4's MEAT_5 never dropped its key. An alien XC ending its charge (XC_STOP) sank
## through the ice and lived on below it; the arena brings the tank carrying the key only once every
## XC is dead. The original adds an animation's root motion to the push (anim_step_frames 0x43ab70),
## moved with collisions on the next tick, not to the position.
## Run: godot --headless --audio-driver Dummy --path . -s tests/root_motion_test.gd
extends SceneTree

const LEVEL := 4
const ARENA := "MEAT_5"
const ALIEN := "XC"
const CHARGE_END := "XC_STOP"
## Where the charge ended, on the ice (z -1989).
const ON_THE_ICE := Vector3(-4.3, 13181.5, -1989.05)
const YAW := 315.0
const KURT_SPOT := Vector3(-288.0, 13559.0, -1989.0)
## Physics frames (60 per second): 4 s.
const FRAMES := 240
const TOLERANCE := 0.5
## `MDKObject.FLAG_GRAVITY | FLAG_COLLIDES` (the class needs autoloads not there when this compiles).
const WALKER_FLAGS := 0x2 | 0x4

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
	scripts.teleport_kurt(ARENA, KURT_SPOT, 0.0)
	await physics_frame
	await physics_frame

	# The charge's end, played once on the ice: the XC stays on it.
	var controller: Node = scripts.get_arena_state(ARENA).controller
	var alien: Node3D = scripts.spawn(controller, ALIEN, ON_THE_ICE, YAW, -1, 0, false)
	_expect(alien != null, "no %s" % ALIEN)
	if alien == null:
		_finish()
		return
	alien.flags = WALKER_FLAGS
	alien.restart_animation(scripts.find_arena_animation(ARENA, CHARGE_END), false)
	for i in FRAMES:
		await physics_frame

	var z: float = alien.mdk_position.z
	_expect(absf(z - ON_THE_ICE.z) <= TOLERANCE, "the XC left the ice: z %.2f" % z)
	_finish()


func _finish() -> void:
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

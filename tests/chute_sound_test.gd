## Bug test (playtest): dead under the open chute, Kurt's `CHUTEON` loop played on until the level
## ended. Every exit from the chute that doesn't close it (death, a teleport, a ride, the level's
## end) stops the loop, without `CHUTEIN`.
## Run: godot --headless --audio-driver Dummy --path . -s tests/chute_sound_test.gd
extends SceneTree

const LEVEL := 7
## High above LEVEL7's start (as `tests/chute_test.sh`), MDK coordinates.
const SKY := Vector3(0.0, 4.0, 300.0)
## Physics frames (60 per second): the chute opens and `CHUTEON` starts within this.
const OPEN_FRAMES := 30
const EXIT_FRAMES := 2

## Death last: Kurt stays dead.
enum Exit { TELEPORT, RIDE, LEVEL_END, DEATH }

var _failures := 0
var _kurt: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	_kurt = main.get_node("Kurt")
	while scripts.tick_count() == 0:
		await physics_frame

	for exit in Exit.values():
		await _check(exit)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Kurt under the open chute, `CHUTEON` flapping; then he leaves the chute by `exit`.
func _check(exit: Exit) -> void:
	var name: String = Exit.keys()[exit]
	_kurt.frozen = false
	_kurt.ride = Callable()
	_kurt.teleport(MDKMeshBuilder.to_godot(SKY), 0.0)
	_kurt.velocity.y = -20.0
	Input.action_press(&"jump")
	await _frames(OPEN_FRAMES)
	_expect(_kurt.mixer.is_playing("CHUTEON"), "%s: no CHUTEON under the chute" % name)
	Input.action_release(&"jump")
	_kurt.mixer.stop("CHUTEIN")

	match exit:
		Exit.DEATH:
			_kurt.fall_out()
		Exit.TELEPORT:
			_kurt.teleport(MDKMeshBuilder.to_godot(SKY), 0.0)
		Exit.RIDE:
			_kurt.ride = func(_delta: float) -> void: pass
		Exit.LEVEL_END:
			_kurt.frozen = true
	await _frames(EXIT_FRAMES)
	var on: bool = _kurt.mixer.is_playing("CHUTEON")
	var closed: bool = _kurt.mixer.is_playing("CHUTEIN")
	print("%s: CHUTEON %s, CHUTEIN %s" % [name, on, closed])
	_expect(not on, "%s: CHUTEON still plays" % name)
	_expect(not closed, "%s: CHUTEIN played" % name)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

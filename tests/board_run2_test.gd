## Bug test (found by playtest): LEVEL4's second board run (CMEAT_3 → MEAT_4 → CMEAT_4 → MEAT_5).
## 1. The slope under Kurt vanished: the board runs `group_state_near_player 2, 10, 31, 1, 2`, and
##    the original (0x453a1e) gives the groups near Kurt the opposite op (shown), the others the op.
## 2. The ride never ended: the board's script lets Kurt off in a box of MEAT_5, but MEAT_5's
##    `arena_show NONE` dropped CMEAT_4 before the board there followed Kurt in. The original runs
##    the arenas' own scripts after the objects (`game_frame`: 0x43c7dc, then 0x440bc8).
## Run: godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/board_run2_test.gd
extends SceneTree

const LEVEL := 4
const START := "CMEAT_3"
const END := "MEAT_5"
## Near the board (its path's first key is at 420, 4285).
const NEAR_BOARD := Vector3(420.0, 4280.0, -578.0)
const ABOVE_BOARD := Vector3(0.0, 0.0, 3.0)
const YAW := 90.0
const BOARD := "XSNOWB"
## Physics frames (60 per second). Without keys the ride reaches MEAT_5 after about 145 s.
const SECOND := 60
const BOARDING_SECONDS := 10
const SLOPE_SECONDS := 5
const RUN_SECONDS := 240
## `Kurt.invulnerable` for the whole run.
const UNHURT_SECONDS := 1000.0
## The scripts' random numbers: with some, MEAT_4 stops a rider without keys.
const SEED := 2
## `Level.TRIANGLE_HIDDEN`.
const TRIANGLE_HIDDEN := 0x10

var _failures := 0
var _scripts: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(SEED)
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	_scripts = main.get_node("Scripts")
	while _scripts.tick_count() == 0:
		await physics_frame

	# Onto the board.
	_scripts.teleport_kurt(START, NEAR_BOARD, YAW)
	await _frames(SECOND)
	var board: Node = _scripts.find_object_named(BOARD)
	_scripts.teleport_kurt(START, board.mdk_position + ABOVE_BOARD, YAW)
	for i in BOARDING_SECONDS * SECOND:
		if _scripts.rides.on_board():
			break
		await physics_frame
	_expect(_scripts.rides.on_board(), "not on the board")

	# The slope under Kurt is shown.
	await _frames(SLOPE_SECONDS * SECOND)
	var floor_group: int = _scripts.get_kurt_floor_group()
	var group = _scripts.level.arena_groups.get(START, {}).get(floor_group)
	_expect(group != null, "no floor group under Kurt")
	_expect(group == null or not group.flags & TRIANGLE_HIDDEN, "group %d under Kurt hidden" % floor_group)

	# Down the run, without keys and unhurt (MEAT_4's aliens shoot): the script lets him off in MEAT_5.
	_scripts.kurt.invulnerable = UNHURT_SECONDS
	for i in RUN_SECONDS * SECOND:
		if not _scripts.rides.on_board():
			break
		await physics_frame
	_expect(not _scripts.rides.on_board(), "still on the board in %s" % _scripts.current_arena)
	_expect(_scripts.current_arena == END, "Kurt in %s" % _scripts.current_arena)
	_expect(board.arena == END, "board in %s" % board.arena)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

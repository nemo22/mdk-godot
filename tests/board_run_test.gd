## Bug test (found by playtest): LEVEL4's first board run (MEAT_1 → CMEAT_1 → MEAT_3) never let
## Kurt off. The board's script waits for Kurt in a box of MEAT_3; the board stayed in MEAT_1, which
## stopped updating once Kurt left CMEAT_1. The original moves objects with flag 0x80000 (the ridden
## board, thrown items) into the arena whose connection their move crosses (0x45e810, 0x43ca00).
## Run: godot --headless --audio-driver Dummy --path . -s tests/board_run_test.gd
extends SceneTree

const LEVEL := 4
const START := "MEAT_1"
const END := "MEAT_3"
## Kurt lands on group 1 of MEAT_1 (its hit script spawns the board and XS); XS's death makes the
## board rideable.
const LANDING_GROUP := 1
const LANDING := Vector3(0.0, 0.0, 80.0)
const ABOVE_BOARD := Vector3(0.0, 0.0, 3.0)
const YAW := 90.0
const BOARD := "XSNOWB"
const GUARD := "XS"
## `MDKScriptRuntime.HIT_KURT`, `HIT_TYPE_KURT` (the class needs autoloads not there when this
## script compiles).
const HIT_KURT := 8
const HIT_TYPE_KURT := -11
## Physics frames (60 per second); the run takes about 45 s.
const SECOND := 60
const RUN_SECONDS := 60
const BOARDING_SECONDS := 10
## `MDKRides.FLAG_RIDEABLE`.
const FLAG_RIDEABLE := 0x2000000

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

	# The landing spawns the board and its guard; the guard's death makes it rideable.
	_scripts.teleport_kurt(START, LANDING, YAW)
	await _frames(SECOND / 2)
	_scripts.hit_group(START, LANDING_GROUP, 0, HIT_KURT, HIT_TYPE_KURT)
	await _frames(SECOND)
	_scripts.kill(_scripts.find_object_named(GUARD))
	var board: Node = _scripts.find_object_named(BOARD)
	for i in BOARDING_SECONDS * SECOND:
		if board.flags & FLAG_RIDEABLE:
			break
		await physics_frame

	# Onto the board.
	_scripts.teleport_kurt(START, board.mdk_position + ABOVE_BOARD, YAW)
	await _frames(SECOND)
	_expect(_scripts.rides.on_board(), "not on the board")

	# Down the run, without keys: the script lets him off in MEAT_3.
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

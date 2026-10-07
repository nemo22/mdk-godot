## Bug test: the snowboard read only the turn keys (the arrows), so with WASD and the mouse it could
## hardly be steered. The original's turn input (0x5014ec, `input_read_axes` 0x408334) is the
## larger of the turn and strafe keys × 4°/tick, or 4 × clamp(dx / dt, ±4) from the mouse when it
## moved (dx in the original's units: its walk turns 3° a unit).
## Run: godot --headless --audio-driver Dummy --path . -s tests/board_steer_test.gd
extends SceneTree

## Loaded at run time: the board uses autoloads, which a `-s` script can't name when it compiles.
const SNOWBOARD := "res://game/scripts/snowboard.gd"
const KEY_RATE := 4.0
const MOUSE_CAP := 16.0
## One tick, and a walking mouse turn of 1.5° (half an original unit) to the right.
const TICK := 1.0
const MOUSE_RIGHT := 1.5

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var board: GDScript = load(SNOWBOARD)
	_check(is_equal_approx(board.turn_input(0.0, 1.0, 0.0, TICK), KEY_RATE), "turn key right")
	_check(is_equal_approx(board.turn_input(0.0, 0.0, -1.0, TICK), -KEY_RATE), "strafe key left")
	_check(is_equal_approx(board.turn_input(0.0, 1.0, -1.0, TICK), -KEY_RATE), "strafe wins a tie")
	_check(is_equal_approx(board.turn_input(MOUSE_RIGHT, 0.0, -1.0, TICK), 2.0), "mouse wins over the keys")
	_check(is_equal_approx(board.turn_input(1000.0, 0.0, 0.0, TICK), MOUSE_CAP), "mouse capped at 4× the keys")
	_check(is_equal_approx(board.turn_input(-1000.0, 0.0, 0.0, TICK), -MOUSE_CAP), "mouse capped left")
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)

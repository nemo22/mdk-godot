## Bug test (playtest): LEVEL5's last nuke frees Bones; his cutscene (23 s, Kurt frozen) stayed
## white because the flashes only faded while Kurt moved. The original fades them by 4 a tick in
## cutscenes too (0x478704).
## Run: godot --headless --audio-driver Dummy --path . -s tests/frozen_flash_test.gd
extends SceneTree

const LEVEL := 3
const FLASH_MAX := 255.0
const FADE_PER_SECOND := 4.0 * 30.0
## Physics frames (60 per second): one second.
const FRAMES := 60
const TOLERANCE := 4.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	var kurt: Node = main.get_node("Kurt")
	while scripts.tick_count() == 0:
		await physics_frame

	kurt.white_flash = FLASH_MAX
	kurt.frozen = true
	for i in FRAMES:
		await physics_frame

	var expected := FLASH_MAX - FADE_PER_SECOND
	print("white flash after 1 s frozen: %.0f (expected %.0f)" % [kurt.white_flash, expected])
	var ok: bool = absf(kurt.white_flash - expected) <= TOLERANCE
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)

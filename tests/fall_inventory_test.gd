## Bug test: the fall's inventory stays on screen. The original's fall draws it every frame
## (0x4119ec); the port hid it 60 ticks after the slots last changed, as the level HUD once did.
## Run: godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/fall_inventory_test.gd
extends SceneTree

const LEVEL := 3
## Longer than the 60 ticks the port showed it for.
const SECONDS := 3.0
const FPS := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var fall: Node = load("res://game/fall/fall.tscn").instantiate()
	root.add_child(fall)

	# After the intro in space, a while into the fall.
	while fall._intro_left > 0:
		await process_frame
	for frame in int(SECONDS * FPS):
		await process_frame

	var shown: bool = fall.shows_inventory()
	print("inventory shown %s" % shown)
	print("PASSED" if shown else "FAILED")
	quit(0 if shown else 1)

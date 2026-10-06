## Bug test: the inventory stays on screen outside sniper mode. The original (0x46cce4) resets its
## display timer 0x574328 to 60 every frame unless Kurt snipes, so the super chain gun's slot shows
## its ticks counting down while Kurt fires. The port hid it 60 ticks after the last change.
## Run: godot --headless --audio-driver Dummy --path . -s tests/gatt_hud_test.gd
extends SceneTree

const LEVEL := 3
const PICKUP := "SW_GATT"
## Longer than the 60 ticks the port showed it for.
const SECONDS := 3.0
const FPS := 60.0


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
	var kurt: Node = main.kurt
	var hud: Node = main.hud
	kurt.inventory.collect(PICKUP, kurt)
	var start: int = kurt.inventory.super_chain_gun

	# Fire for a while: the ticks run down, the slot stays on screen.
	Input.action_press(&"fire")
	for frame in int(SECONDS * FPS):
		await physics_frame
	Input.action_release(&"fire")

	var left: int = kurt.inventory.super_chain_gun
	var shown: bool = hud.shows_inventory()
	print("super chain gun %d -> %d ticks, inventory shown %s" % [start, left, shown])
	var ok := shown and left < start
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)

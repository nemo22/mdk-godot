## Bug test (playtest): the enhanced look was veiled, as if in fog. The haze at 0.0007 per unit greyed
## whole rooms and the bloom on all colours lifted the blacks. A density of 0.0002 and glow only
## above the threshold keep the depth cue without the veil.
## Run: godot --headless --audio-driver Dummy --path . -s tests/enhanced_haze_test.gd
extends SceneTree

const LEVEL := 6
const HAZE := 0.0002
const BLOOM := 0.0

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Not saved: only this run uses the enhanced look.
	var settings: Node = root.get_node("Settings")
	settings.enhanced_graphics = true
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	var scripts: Node = main.get_node("Scripts")
	while scripts.tick_count() == 0:
		await physics_frame

	var environment: Environment = main.get_node("Level")._environment
	_expect(is_equal_approx(environment.fog_density, HAZE), "haze %.4f" % environment.fog_density)
	_expect(is_equal_approx(environment.glow_bloom, BLOOM), "bloom %.2f" % environment.glow_bloom)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test: a missile's explosion in the fall hid inside Kurt's model. The original sorts an
## explosion at camera z + 5, so it's drawn last, over Kurt and the rest (docs/gameplay.md, "Camera
## and projection"); the port depth-tested it like any model.
## Run: godot --headless --audio-driver Dummy --path . -s tests/fall_explosion_test.gd
extends SceneTree

const LEVEL := 3

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var fall: Node = load("res://game/fall/fall.tscn").instantiate()
	root.add_child(fall)
	while fall._intro_left > 0:
		await process_frame

	# A missile hits Kurt: every surface of its explosion skips the depth test, after the opaque pass.
	fall._launch_missile()
	fall._hit(fall._missiles[0])
	var node: MeshInstance3D = fall._explosions[0].node
	_expect(node.mesh.get_surface_count() > 0, "the explosion has no surfaces")
	for i in node.mesh.get_surface_count():
		var material := node.get_active_material(i)
		if material is ShaderMaterial:
			var code: String = material.shader.code
			_expect(code.contains("depth_test_disabled") and code.contains("ALPHA"), "surface %d is depth-tested" % i)
			_expect(material.get_shader_parameter(&"index_texture") != null, "surface %d lost its texture" % i)
		else:
			var standard := material as StandardMaterial3D
			_expect(standard.no_depth_test and standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "surface %d is depth-tested" % i)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## Bug test: LEVEL8's walls paint black with palette index 0 (`I2_WALL1`): drawn opaque, as the
## original uploads a texture with alpha only when bit 0 of its kind is set (0x474c9c; `EXPLODE`…).
## `GUNT_2`'s beams showed the sky through holes. Run: godot --headless --path . -s tests/opaque_texture_test.gd
extends SceneTree

const DIR := "C:/Games/MDK/TRAVERSE/LEVEL8/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var arena = load("res://mdk/formats/mdk_mto.gd").load_file(DIR + "LEVEL8O.MTO").get_arena("GUNT_2")
	var archive_script = load("res://mdk/formats/mdk_texture_archive.gd")
	var level = archive_script.load_file(DIR + "LEVEL8S.MTI", archive_script.Zero.BY_KIND)
	var checks := [
		["I2_WALL1 opaque", arena.textures.textures["I2_WALL1"].indices.has(0), false],
		["BULLET opaque", level.textures["BULLET"].indices.has(0), false],
		["EXPLODE keyed", level.textures["EXPLODE"].indices.has(0), true],
	]
	for check: Array in checks:
		var ok: bool = check[1] == check[2]
		print("%s: %s" % [check[0], "ok" if ok else "FAILED"])
		if not ok:
			failures += 1
	print("FAILED %d" % failures if failures else "PASSED")
	quit(1 if failures else 0)

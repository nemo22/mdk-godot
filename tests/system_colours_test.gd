## Bug test: a level keeps the system colours (`SYS_PAL`) at palette 0–63, as the original's level
## load copies only the DTI's 64–255 (0x41ba68: base palette + 0xc0 to 0x5736a4). LEVEL8's DTI has
## magenta and purple at 10–12: its aliens, shots and the grenade's icon showed them.
## Run: godot --headless --audio-driver Dummy --path . -s tests/system_colours_test.gd
extends SceneTree

const LEVEL := 8
const CHANGED := [10, 11, 12]
const FONT_FILE := "C:/Games/MDK/MISC/MDKFONT.FTI"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	var level: Node = main.get_node("Level")
	while level.dti == null:
		await process_frame
	var system: PackedByteArray = load("res://mdk/formats/mdk_fti.gd").load_file(FONT_FILE).get_bytes("SYS_PAL")
	var failures := 0
	for index: int in CHANGED:
		var expected := Color8(system[index * 3], system[index * 3 + 1], system[index * 3 + 2])
		var ok: bool = level.dti.palette.get_color(index) == expected
		print("colour %d: %s" % [index, "ok" if ok else "FAILED (%s)" % level.dti.palette.get_color(index)])
		if not ok:
			failures += 1
	print("FAILED %d" % failures if failures else "PASSED")
	quit(1 if failures else 0)

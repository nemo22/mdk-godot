## Test: LEVEL7's DANT_7 glass columns flag diagonals inside their panes (the editor gave fan
## triangles the edge flags of a quad's half), so thin lines cross the panes. The original (0x40b7f0)
## draws every flagged edge: the original look keeps them. The enhanced look skips flagged edges two
## coplanar triangles share, keeping the frames.
## Run: godot --headless --audio-driver Dummy --path . -s tests/glass_outline_test.gd
extends SceneTree

const MTO := "C:/Games/MDK/TRAVERSE/LEVEL7/LEVEL7O.MTO"
const ARENA := "DANT_7"
## `MDKMeshBuilder.OUTLINE`, `Look` (loaded at run time: the builder uses autoloads).
const OUTLINE := 1 << 23
const ORIGINAL := 0
const ENHANCED := 1

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mto = load("res://mdk/formats/mdk_mto.gd").load_file(MTO)
	var arena = mto.get_arena(ARENA)
	var builder = load("res://mdk/mdk_mesh_builder.gd")
	var outlined := PackedInt32Array()
	for tri in arena.triangle_flags.size():
		if arena.triangle_flags[tri] & OUTLINE:
			outlined.push_back(tri)

	var original := _line_count(builder, arena, outlined, ORIGINAL)
	var enhanced := _line_count(builder, arena, outlined, ENHANCED)
	print("outline lines: original %d, enhanced %d" % [original, enhanced])
	_expect(original > 0, "no outlines")
	_expect(enhanced < original, "the enhanced look keeps the diagonals")
	_expect(enhanced > 0, "the enhanced look drops the frames")

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _line_count(builder: GDScript, arena: Object, triangles: PackedInt32Array, look: int) -> int:
	var mesh := ArrayMesh.new()
	builder._add_outlines(mesh, arena, triangles, StandardMaterial3D.new(), look)
	if mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 2


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

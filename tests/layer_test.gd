## Bug test: depth layers of coplanar arena triangles (details drawn over the surfaces they lie on).
## The original draws back to front without a depth buffer; with one, coplanar triangles fight.
## A detail was lifted only when a bigger triangle held its centre, so partial overlaps (LEVEL6
## OLYM_7's mirror tiles on the floor, OLYM_5's hub rims on the glass) still fought. A triangle is
## now one layer above the highest bigger one it overlaps (by clipped area), at most 3.
## Run: godot --headless --audio-driver Dummy --path . -s tests/layer_test.gd
extends SceneTree

const MTO := "C:/Games/MDK/TRAVERSE/LEVEL6/LEVEL6O.MTO"
## OLYM_5: a hub's rim (159) lies half on the glass floor around it (115).
const HUBS := "OLYM_5"
const HUB_RIM := 159
const GLASS_FLOOR := 115
## OLYM_7: a dark floor triangle (2) half under a mirror tile (56).
const MIRRORS := "OLYM_7"
const DARK_FLOOR := 2
const MIRROR_TILE := 56
const WALL := [Vector2(0, 0), Vector2(0, 10), Vector2(10, 0)]

var _failures := 0
var _builder: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Loaded at run time: the builder uses autoloads, which a `-s` script can't name when it compiles.
	_builder = load("res://mdk/mdk_mesh_builder.gd")
	_check(_layers([WALL, [Vector2(1, 1), Vector2(1, 2), Vector2(2, 1)]]), [0, 1], "a poster on a wall")
	# Its centre (9, 1.3) is off the wall, a corner on it.
	_check(_layers([WALL, [Vector2(7, 1), Vector2(7, 2), Vector2(13, 1)]]), [0, 1], "a poster half on a wall")
	_check(_layers([WALL, [Vector2(0, 10), Vector2(10, 10), Vector2(10, 0)]]), [0, 0], "neighbours sharing an edge")
	_check(_layers([WALL, [Vector2(1, 1), Vector2(1, 5), Vector2(5, 1)], [Vector2(1.5, 1.5), Vector2(1.5, 2), Vector2(2, 1.5)]]),
			[0, 1, 2], "a poster on a poster")
	_check(_layers([WALL, WALL]), [0, 1], "of two equal ones, the later on top")

	var mto = load("res://mdk/formats/mdk_mto.gd").load_file(MTO)
	var hubs: PackedInt32Array = _builder.arena_layers(mto.get_arena(HUBS))
	_expect(hubs[HUB_RIM] > hubs[GLASS_FLOOR], "hub rim %d, glass %d" % [hubs[HUB_RIM], hubs[GLASS_FLOOR]])
	var mirrors: PackedInt32Array = _builder.arena_layers(mto.get_arena(MIRRORS))
	_expect(mirrors[DARK_FLOOR] > mirrors[MIRROR_TILE], "dark floor %d, mirror tile %d" % [mirrors[DARK_FLOOR], mirrors[MIRROR_TILE]])

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## The layers of triangles in z = 0 (MDK).
func _layers(triangles: Array) -> Array:
	var arena = load("res://mdk/formats/mdk_arena.gd").new()
	for corners: Array in triangles:
		for corner: Vector2 in corners:
			arena.triangle_indices.push_back(arena.vertices.size())
			arena.vertices.push_back(Vector3(corner.x, corner.y, 0.0))
		arena.triangle_materials.push_back(0)
		arena.triangle_flags.push_back(0)
	return Array(_builder.arena_layers(arena))


func _check(layers: Array, expected: Array, what: String) -> void:
	_expect(layers == expected, "%s: %s, not %s" % [what, layers, expected])


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)

## `LEVELnO.MTO`: the arenas of a level. Arenas are parsed on demand.
class_name MDKMto
extends RefCounted

var bytes := PackedByteArray()
## Arena name (`HMO_1`, …) to the file offset of the arena block.
var arena_offsets := {}

var _arenas := {}


static func load_file(path: String) -> MDKMto:
	var mto := MDKMto.new()
	mto.bytes = FileAccess.get_file_as_bytes(path)
	if mto.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(mto.bytes, 0x14)
	var count := r.u32()
	for i in count:
		var arena_name := r.name(8)
		mto.arena_offsets[arena_name] = r.u32()
	return mto


func get_arena_names() -> Array:
	return arena_offsets.keys()


func get_arena(arena_name: String) -> MDKArena:
	if not _arenas.has(arena_name):
		_arenas[arena_name] = MDKArena.parse(arena_name, bytes, arena_offsets[arena_name])
	return _arenas[arena_name]

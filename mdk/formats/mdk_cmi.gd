## `LEVELn.CMI` (internal name `LEVELn.CMD`): level scripts and global models.
##
## After the common header, 4 directories follow each other, each `u32 count`, then entries of
## `u8 length, char name[length], u32 offset` (offsets relative to file offset 4):
## 0. Alien instance scripts (`HMO_1$XG_0`: alien type `XG`, instance 0, in arena `HMO_1`).
## 1. Global models (aliens, bullets, pickups, effects; offset 0 = look it up in the arena).
## 2. Object type scripts per arena (`HMO_1$XH1_DOOR`).
## 3. Arenas (`HMO_1`, `CHMO_1`, …, and `C`): each entry points to a record of two pascal strings
##    (the first is usually `NONE` ❓, the second names the arena's music in `LEVELnO.SNI`) and a
##    `u32` script offset (0 = no script).
## The script bytecode follows. See `docs/scripts.md`.
class_name MDKCmi
extends RefCounted

var bytes := PackedByteArray()
## Name to offset (absolute file offset), per directory.
var alien_scripts := {}
var model_offsets := {}
var object_scripts := {}
var arena_scripts := {}
## Arena name to its music (a sound of `LEVELnO.SNI`, or `NONE`).
var arena_music := {}

var _models := {}


static func load_file(path: String) -> MDKCmi:
	var cmi := MDKCmi.new()
	cmi.bytes = FileAccess.get_file_as_bytes(path)
	if cmi.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(cmi.bytes, 0x14)
	for directory: Dictionary in [cmi.alien_scripts, cmi.model_offsets, cmi.object_scripts, cmi.arena_scripts]:
		var count := r.u32()
		for i in count:
			var entry_name := r.pascal_name()
			var offset := r.u32()
			directory[entry_name] = 4 + offset if offset != 0 else 0
	# Arena records: two pascal strings, then the script offset.
	for arena_name: String in cmi.arena_scripts:
		var record := BinReader.new(cmi.bytes, cmi.arena_scripts[arena_name])
		record.pascal_name()
		cmi.arena_music[arena_name] = record.pascal_name()
		var script := record.u32()
		cmi.arena_scripts[arena_name] = 4 + script if script != 0 else 0
	return cmi


## Returns a global model, or `null` if it doesn't exist or is an arena model (look it up in the arena).
func get_model(model_name: String) -> MDKModel:
	if not model_offsets.has(model_name) or model_offsets[model_name] == 0:
		return null
	if not _models.has(model_name):
		_models[model_name] = MDKModel.parse(model_name, bytes, model_offsets[model_name])
	return _models[model_name]

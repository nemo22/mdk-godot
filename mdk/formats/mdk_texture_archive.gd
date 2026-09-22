## A texture archive: an arena's `HMO_n.MAT` or a level's `LEVELnS.MTI`.
##
## Layout (offsets relative to `base`, the position of the internal file name):
##   char[12] name, u32 size, u32 count, then per entry:
##   char[8] name, u32 kind, u32 value, f32 ?, u32 offset
## `kind` is 0xFFFFFFFF for a palette color (`value` is the palette index, values ≥ 256 are special
## materials, see `MDKMaterials`), 0x10000/0x10001 for an animated sprite (❓ not parsed yet), and
## texture flags otherwise (0, or 2 for some floors ❓).
class_name MDKTextureArchive
extends RefCounted

const KIND_COLOR := 0xFFFFFFFF
const KIND_SPRITE_MASK := 0xFFFF0000

## Name to MDKTexture.
var textures := {}
## Name to palette index (or special value ≥ 256).
var colors := {}
## Names of animated sprites (not parsed yet).
var sprites: Array[String] = []


static func parse(bytes: PackedByteArray, base: int) -> MDKTextureArchive:
	var archive := MDKTextureArchive.new()
	var r := BinReader.new(bytes, base + 16)
	var count := r.u32()
	for i in count:
		var entry_name := r.name(8)
		var kind := r.u32()
		var value := r.u32()
		var _unknown := r.f32()
		var offset := r.u32()
		if kind == KIND_COLOR:
			archive.colors[entry_name] = value
		elif kind & KIND_SPRITE_MASK:
			archive.sprites.push_back(entry_name)
		else:
			archive.textures[entry_name] = MDKTexture.parse(entry_name, bytes, base + offset)
	return archive


static func load_file(path: String) -> MDKTextureArchive:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	return parse(bytes, 4)

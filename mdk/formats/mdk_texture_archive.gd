## A texture archive: an arena's `HMO_n.MAT` or a level's `LEVELnS.MTI`.
##
## Layout (offsets relative to `base`, the position of the internal file name):
##   char[12] name, u32 size, u32 count, then per entry:
##   char[8] name, u32 kind, u32 value, f32 ?, u32 offset
## `kind` is 0xFFFFFFFF for a palette color (`value` is the palette index, values ≥ 256 are special
## materials, see `MDKMeshBuilder`). If its high 16 bits are set (0x10000, 0x10001, 0x20000), the entry
## is an animated texture (see `MDKTexture.parse_animated()`). Otherwise it's a texture, and `kind`
## holds flags (0, or 2 for some floors ❓).
class_name MDKTextureArchive
extends RefCounted

const KIND_COLOR := 0xFFFFFFFF
const KIND_ANIMATED_MASK := 0xFFFF0000
## Uploaded with alpha: index 0 see-through (0x474c9c; the effects: `EXPLODE`, `TRAIL`…).
const KIND_KEYED := 1
## Palette black (`BLACK`), standing in for index 0 where it's opaque.
const OPAQUE_BLACK := 16

## Palette index 0: see-through everywhere, or only in textures of kind bit 0.
enum Zero { SEE_THROUGH, BY_KIND }

## Name to MDKTexture (including animated textures).
var textures := {}
## Name to palette index (or special value ≥ 256).
var colors := {}


## `header` is the size of the name and size before the count: 16, or 0 in the 1996 demo's
## archives (`MDKBeta`), whose names are in lower case.
static func parse(bytes: PackedByteArray, base: int, header := 16, zero := Zero.SEE_THROUGH) -> MDKTextureArchive:
	var archive := MDKTextureArchive.new()
	var r := BinReader.new(bytes, base + header)
	var count := r.u32()
	for i in count:
		var entry_name := r.name(8).to_upper()
		var kind := r.u32()
		var value := r.u32()
		var _unknown := r.f32()
		var offset := r.u32()
		if kind == KIND_COLOR:
			archive.colors[entry_name] = value
		elif kind & KIND_ANIMATED_MASK:
			archive.textures[entry_name] = MDKTexture.parse_animated(entry_name, bytes, base + offset, kind)
		else:
			var texture := MDKTexture.parse(entry_name, bytes, base + offset)
			archive.textures[entry_name] = texture
			# LEVEL8's walls paint black with index 0 (`I2_WALL1`): opaque unless keyed.
			if zero == Zero.BY_KIND and not kind & KIND_KEYED:
				_make_opaque(texture)
	return archive


static func _make_opaque(texture: MDKTexture) -> void:
	var at := texture.indices.find(0)
	while at >= 0:
		texture.indices[at] = OPAQUE_BLACK
		at = texture.indices.find(0, at + 1)


static func load_file(path: String, zero := Zero.SEE_THROUGH) -> MDKTextureArchive:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	return parse(bytes, 4, 16, zero)

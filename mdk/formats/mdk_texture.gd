## An 8-bit paletted texture: `u16 width, u16 height`, then `width × height` palette indices.
class_name MDKTexture
extends RefCounted

var name := ""
var width := 0
var height := 0
## Palette indices, row by row.
var indices := PackedByteArray()

var _index_texture: ImageTexture


static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = p_name
	texture.width = bytes.decode_u16(offset)
	texture.height = bytes.decode_u16(offset + 2)
	texture.indices = bytes.slice(offset + 4, offset + 4 + texture.width * texture.height)
	return texture


## Returns the palette indices as a single-channel texture, for use with `palette.gdshader`.
func get_index_texture() -> ImageTexture:
	if not _index_texture:
		var image := Image.create_from_data(width, height, false, Image.FORMAT_R8, indices)
		_index_texture = ImageTexture.create_from_image(image)
	return _index_texture

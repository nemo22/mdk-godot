## An 8-bit paletted texture: `u16 width, u16 height`, then `width × height` palette indices.
## Animated textures store `frame_count` frames of `width × height` one after another.
class_name MDKTexture
extends RefCounted

var name := ""
var width := 0
## Height of one frame.
var height := 0
var frame_count := 1
## Palette indices, row by row (all frames).
var indices := PackedByteArray()

var _index_texture: ImageTexture


static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = p_name
	texture.width = bytes.decode_u16(offset)
	texture.height = bytes.decode_u16(offset + 2)
	texture.indices = bytes.slice(offset + 4, offset + 4 + texture.width * texture.height)
	return texture


## Parses an animated texture: `u32 frame count, u16 width, u16 height`, then the frames.
static func parse_animated(p_name: String, bytes: PackedByteArray, offset: int) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = p_name
	texture.frame_count = bytes.decode_u32(offset)
	texture.width = bytes.decode_u16(offset + 4)
	texture.height = bytes.decode_u16(offset + 6)
	texture.indices = bytes.slice(offset + 8, offset + 8 + texture.width * texture.height * texture.frame_count)
	return texture


## Returns the palette indices as a single-channel texture, for use with `palette.gdshader`.
## Frames of animated textures are stacked vertically.
func get_index_texture() -> ImageTexture:
	if not _index_texture:
		var image := Image.create_from_data(width, height * frame_count, false, Image.FORMAT_R8, indices)
		_index_texture = ImageTexture.create_from_image(image)
	return _index_texture

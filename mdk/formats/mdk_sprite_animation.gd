## An RLE-compressed sprite animation, such as Kurt's `K_RUN` in `TRAVSPRT.BNI`.
##
## Layout: `u32 frame count`, `u32 frame offsets[count]` (relative to the frame count), then frames:
## `u16 width, u16 height, s16 hotspot x, s16 hotspot y`, then rows of commands:
## - `0x00–0x7F`: `n + 1` literal palette indices follow.
## - `0x80–0xFD`: the next palette index is repeated `n − 0x7C` times (so at least 4).
## - `0xFE`: end of row (the rest of the row is transparent).
## - `0xFF`: end of frame.
## Palette index 0 is transparent.
class_name MDKSpriteAnimation
extends RefCounted

var name := ""
var frame_count := 0

var _bytes: PackedByteArray
var _base := 0
var _frames := {}


static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKSpriteAnimation:
	var animation := MDKSpriteAnimation.new()
	animation.name = p_name
	animation._bytes = bytes
	animation._base = offset
	animation.frame_count = bytes.decode_u32(offset)
	return animation


## Returns frame `index` (decoded on first use). See `get_hotspot()` for its anchor point.
func get_frame(index: int) -> MDKTexture:
	if not _frames.has(index):
		_frames[index] = _decode(_base + _bytes.decode_u32(_base + 4 + index * 4))
	return _frames[index][0]


## Returns the hotspot of frame `index`, in pixels. For Kurt, the game draws the frame's top-left
## corner at (feet x − hotspot x, feet y − 101 − hotspot y) on a 600×360 view.
func get_hotspot(index: int) -> Vector2i:
	get_frame(index)
	return _frames[index][1]


func _decode(offset: int) -> Array:
	var texture := MDKTexture.new()
	texture.name = name
	texture.width = _bytes.decode_u16(offset)
	texture.height = _bytes.decode_u16(offset + 2)
	var hotspot := Vector2i(_bytes.decode_s16(offset + 4), _bytes.decode_s16(offset + 6))
	texture.indices.resize(texture.width * texture.height)
	var p := offset + 8
	for y in texture.height:
		var i := y * texture.width
		while true:
			var command := _bytes[p]
			p += 1
			if command >= 0xFE:
				break
			if command < 0x80:
				for k in command + 1:
					texture.indices[i] = _bytes[p]
					i += 1
					p += 1
			else:
				var value := _bytes[p]
				p += 1
				for k in command - 0x7C:
					texture.indices[i] = value
					i += 1
	return [texture, hotspot]

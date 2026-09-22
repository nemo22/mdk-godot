## A 256-color palette, as used by MDK's 8-bit textures.
class_name MDKPalette
extends RefCounted

## First palette index replaced by an arena's colors (see `with_arena_colors()`).
const ARENA_FIRST_INDEX := 64

## RGBA8 values, 4 bytes per palette index.
var rgba8 := PackedByteArray()

var _texture: ImageTexture


static func from_rgb(rgb: PackedByteArray) -> MDKPalette:
	var palette := MDKPalette.new()
	palette.rgba8.resize(256 * 4)
	for index in mini(256, rgb.size() / 3):
		palette.rgba8[index * 4] = rgb[index * 3]
		palette.rgba8[index * 4 + 1] = rgb[index * 3 + 1]
		palette.rgba8[index * 4 + 2] = rgb[index * 3 + 2]
		palette.rgba8[index * 4 + 3] = 255
	# The game forces index 0 to black; it's transparent in sprites.
	palette.rgba8[0] = 0
	palette.rgba8[1] = 0
	palette.rgba8[2] = 0
	return palette


## Returns a copy of this palette with an arena's 112 colors placed at indices 64–175.
func with_arena_colors(arena_rgb: PackedByteArray) -> MDKPalette:
	var palette := MDKPalette.new()
	palette.rgba8 = rgba8.duplicate()
	for i in arena_rgb.size() / 3:
		var index := ARENA_FIRST_INDEX + i
		palette.rgba8[index * 4] = arena_rgb[i * 3]
		palette.rgba8[index * 4 + 1] = arena_rgb[i * 3 + 1]
		palette.rgba8[index * 4 + 2] = arena_rgb[i * 3 + 2]
	return palette


func get_color(index: int) -> Color:
	return Color8(rgba8[index * 4], rgba8[index * 4 + 1], rgba8[index * 4 + 2])


## Returns the palette as a 256×1 texture, for use with `palette.gdshader`.
func get_texture() -> ImageTexture:
	if not _texture:
		_texture = ImageTexture.create_from_image(Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, rgba8))
	return _texture


## Converts 8-bit palette indices to an RGBA8 image (slow; prefer `palette.gdshader` for large textures).
## If `transparent_zero` is `true`, index 0 is fully transparent.
func make_image(width: int, height: int, indices: PackedByteArray, transparent_zero := false) -> Image:
	var pixel_count := width * height
	var data := PackedByteArray()
	data.resize(pixel_count * 4)
	for pixel in pixel_count:
		var src := indices[pixel] * 4
		var dst := pixel * 4
		data[dst] = rgba8[src]
		data[dst + 1] = rgba8[src + 1]
		data[dst + 2] = rgba8[src + 2]
		data[dst + 3] = 0 if transparent_zero and src == 0 else 255
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)

## A font of `MISC/MDKFONT.FTI` (`FONTBIG`, `FONTSML`), drawn like the original (0x415a20).
##
## Layout: 256 `u32` glyph offsets (relative to the font, 0 = no glyph), then per glyph
## `s8 ascent, s8 descent, u8 width` and `(ascent + descent + 1) × width` palette indices, row by
## row (0 is transparent). A glyph is drawn from `ascent` rows above the baseline to `descent` rows
## below it; a character without a glyph is a space (6 pixels in `FONTBIG`, 4 in `FONTSML`). The
## pixels use the first 64 colours of the palette, the same in every level (and `SYS_PAL`).
class_name MDKFont
extends RefCounted

var texture: ImageTexture
## Space width for characters without a glyph.
var space_width := 6
## Per character: `[ascent, descent, width, x in the texture]`, or null without a glyph.
var _glyphs: Array = []
var _max_ascent := 0


## Builds the font `font_name` of `fti` with the colours of `palette`.
static func load_font(fti: MDKFti, font_name: String, palette: MDKPalette, p_space_width: int) -> MDKFont:
	var font := MDKFont.new()
	font.space_width = p_space_width
	var data := fti.get_bytes(font_name)
	var glyph_offsets: Array[int] = []
	var total_width := 0
	var max_descent := 0
	for c in 256:
		var offset := data.decode_u32(c * 4)
		glyph_offsets.push_back(offset)
		if offset != 0:
			total_width += data[offset + 2] + 1
			font._max_ascent = maxi(font._max_ascent, data.decode_s8(offset))
			max_descent = maxi(max_descent, data.decode_s8(offset + 1))
	var height := font._max_ascent + max_descent + 1
	var image := Image.create_empty(maxi(total_width, 1), height, false, Image.FORMAT_RGBA8)
	var x := 0
	font._glyphs.resize(256)
	for c in 256:
		var offset := glyph_offsets[c]
		if offset == 0:
			continue
		var ascent := data.decode_s8(offset)
		var descent := data.decode_s8(offset + 1)
		var width: int = data[offset + 2]
		var top := font._max_ascent - ascent
		for row in ascent + descent + 1:
			for column in width:
				var index: int = data[offset + 3 + row * width + column]
				if index != 0:
					image.set_pixel(x + column, top + row, palette.get_color(index))
		font._glyphs[c] = [ascent, descent, width, x]
		x += width + 1
	font.texture = ImageTexture.create_from_image(image)
	return font


## Width of `text` in pixels (0x4159d4).
func get_width(text: PackedByteArray) -> int:
	var width := 0
	for c in text:
		width += _glyphs[c][2] if _glyphs[c] != null else space_width
	return width


## Draws `text` on `canvas` from `x` along the baseline `y`, scaled by `scale` about the baseline
## (0x415d8c). Returns the x after the text.
func draw(canvas: CanvasItem, text: PackedByteArray, x: float, y: float, scale := 1.0) -> float:
	for c in text:
		var glyph: Variant = _glyphs[c]
		if glyph == null:
			x += space_width * scale
			continue
		var ascent: int = glyph[0]
		var width: int = glyph[2]
		var height: int = ascent + glyph[1] + 1
		var source := Rect2(glyph[3], _max_ascent - ascent, width, height)
		canvas.draw_texture_rect_region(texture, Rect2(x, y - ascent * scale, width * scale, height * scale), source)
		x += width * scale
	return x

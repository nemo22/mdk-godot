## The loading screen (`level_load` 0x41b0c0, drawn by 0x422a10) on the 600×360 screen:
## `MISC/LOAD_n.LBB` (768-byte palette, `u16 width, height`, pixels; 200×200) centred at (200, 25),
## `LOAD_MSG` ("Loading") centred at y 260 and a progress bar from x 10 to 590, y 290 to 310.
class_name LoadingScreen
extends CanvasLayer

const VIEW := Vector2(600.0, 360.0)
const IMAGE_POSITION := Vector2(200.0, 25.0)
const TEXT_Y := 260.0
const BAR := Rect2(10.0, 290.0, 580.0, 20.0)

var progress := 0.0
var _canvas := Control.new()
var _image: Texture2D
var _font: MDKFont
var _text := PackedByteArray()
var _bar_fill := Color.WHITE
var _bar_frame := Color.WHITE


func setup(level_number: int, fti: MDKFti) -> void:
	layer = 20
	var bytes := FileAccess.get_file_as_bytes(MDKData.path("MISC/LOAD_%d.LBB" % level_number))
	if bytes.size() > 772:
		var palette := MDKPalette.from_rgb(bytes.slice(0, 768))
		var image := MDKTexture.parse("LOAD", bytes, 768)
		_image = ImageTexture.create_from_image(palette.make_image(image.width, image.height, image.indices))
		if fti:
			_font = MDKFont.load_font(fti, "FONTBIG", palette, 6)
			_text = fti.get_text_bytes("LOAD_MSG")
		_bar_fill = palette.get_color(3)
		_bar_frame = palette.get_color(4)
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	_canvas.queue_redraw()


func _draw_screen() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var scale := size.y / VIEW.y
	_canvas.draw_set_transform(Vector2((size.x - VIEW.x * scale) / 2.0, 0.0), 0.0, Vector2(scale, scale))
	if _image:
		_canvas.draw_texture(_image, IMAGE_POSITION)
	if _font and not _text.is_empty():
		_font.draw(_canvas, _text, (VIEW.x - _font.get_width(_text)) / 2.0, TEXT_Y)
	_canvas.draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * progress, BAR.size.y)), _bar_fill)
	_canvas.draw_rect(BAR, _bar_frame, false, 1.0)

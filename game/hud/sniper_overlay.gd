## Sniper mode's screen (HUD 0x41e128, 0x420830; `TRAVERSE/TRAVSPRT.BNI`), drawn over the whole
## 640×480 screen: the `SNIPERS1` frame around the 600×360 view at (20, 60), the `SNIPERS2` mask
## over the view (holes for the scope and the three round cameras at the top: 140×70 views from
## behind each round, 90° wide, then a colour or the `SNIPERGA` animation), the `CROSS` crosshair
## on the scope's centre, the zoom in percent with its `SNIP_RNG` gauge, and the ammo types (`SNIP_WEP`, `SNIP_Wn`, the selected one's
## `SNIP_Ln` and count). See `docs/gameplay.md` ("Sniper mode").
class_name SniperOverlay
extends RefCounted

const SCREEN := Vector2(640.0, 480.0)
## Where the 600×360 view sits on the screen.
const VIEW_ORIGIN := Vector2(20.0, 60.0)
## The scope window inside the view; its holes elsewhere are the round cameras.
const SCOPE := Rect2(107.0, 79.0, 384.0, 280.0)
const CROSSHAIR := Vector2(299.0, 219.0)
const ZOOM_DIGITS := Vector2(564.0, 155.0)
const GAUGE := Vector2(552.0, 176.0)
const GAUGE_HEIGHT := 88
## The gauge's shown height follows the zoom by 3 pixels per tick.
const GAUGE_SPEED := 3
const WEAPON := Vector2(112.0, 304.0)
const TYPE_ICONS := [Vector2(0, 256), Vector2(0, 280), Vector2(0, 300), Vector2(4, 320), Vector2(16, 336), Vector2(32, 344)]
const TYPE_LABELS := [Vector2(12, 268), Vector2(12, 288), Vector2(12, 308), Vector2(20, 320), Vector2(24, 328), Vector2(36, 336)]
const COUNT := Vector2(64.0, 315.0)
## The round cameras' windows in the view (0x461d80).
const ROUND_VIEWS := [Rect2(72, 10, 140, 70), Rect2(228, 0, 140, 70), Rect2(384, 10, 140, 70)]

var _frame: Texture2D
var _mask: Texture2D
var _cross: Texture2D
var _cross_hotspot := Vector2i()
var _gauge: Texture2D
var _weapon: Texture2D
var _icons: Array[Texture2D] = []
var _labels: Array[Texture2D] = []
var _gauge_shown := 0
var _palette: MDKPalette
var _miss: MDKSpriteAnimation
var _miss_frames: Array[Texture2D] = []
var _views: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []


func setup(sprites: MDKBni, palette: MDKPalette, parent: Node) -> void:
	_palette = palette
	_miss = sprites.get_animation("SNIPERGA")
	for i in _miss.frame_count:
		_miss_frames.push_back(HUD._make_texture(_miss.get_frame(i), palette))
	for rect: Rect2 in ROUND_VIEWS:
		var view := SubViewport.new()
		view.size = Vector2i(rect.size)
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var camera := Camera3D.new()
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 90.0
		camera.near = 0.5
		view.add_child(camera)
		parent.add_child(view)
		_views.push_back(view)
		_cameras.push_back(camera)
	_frame = ImageTexture.create_from_image(_frame_image(sprites, palette))
	_mask = ImageTexture.create_from_image(_mask_image(sprites, palette))
	var cross := sprites.get_animation("CROSS")
	_cross = HUD._make_texture(cross.get_frame(0), palette)
	_cross_hotspot = cross.get_hotspot(0)
	_gauge = HUD._make_texture(sprites.get_image("SNIP_RNG"), palette)
	_weapon = HUD._make_texture(sprites.get_image("SNIP_WEP"), palette)
	for i in range(1, 7):
		_icons.push_back(HUD._make_texture(sprites.get_image("SNIP_W%d" % i), palette))
		_labels.push_back(HUD._make_texture(sprites.get_image("SNIP_L%d" % i), palette))


## `SNIPERS1`: 640×480 palette indices without a header; the view's rectangle is cut out.
static func _frame_image(sprites: MDKBni, palette: MDKPalette) -> Image:
	var offset: int = sprites.entries["SNIPERS1"][0]
	var image := Image.create_empty(640, 480, false, Image.FORMAT_RGBA8)
	for y in 480:
		for x in 640:
			if x >= 20 and x < 620 and y >= 60 and y < 420:
				continue
			image.set_pixel(x, y, palette.get_color(sprites.bytes[offset + y * 640 + x]))
	return image


## `SNIPERS2`: `u32 size`, then u16 words over 600-pixel rows: below 0x8000, that many × 4 literal
## bytes follow; 0x8nnn skips `nnn` transparent pixels; 0xFFnn has `nn` literal bytes (1–3); 0xFF00
## ends.
static func _mask_image(sprites: MDKBni, palette: MDKPalette) -> Image:
	var bytes := sprites.bytes
	var offset: int = sprites.entries["SNIPERS2"][0] + 4
	var image := Image.create_empty(600, 360, false, Image.FORMAT_RGBA8)
	var pixel := 0
	while pixel < 600 * 360:
		var word := bytes.decode_u16(offset)
		offset += 2
		var count := 0
		if word == 0xFF00:
			break
		elif word & 0xFF00 == 0xFF00:
			count = word & 0xFF
		elif word & 0x8000:
			pixel += word & 0xFFF
			continue
		else:
			count = word * 4
		for i in count:
			if pixel < 600 * 360:
				image.set_pixel(pixel % 600, pixel / 600, palette.get_color(bytes[offset + i]))
			pixel += 1
		offset += count
	return image


## Draws the sniper screen on `canvas` (already scaled to 640×480 screen pixels).
func draw(canvas: HUD, kurt: Kurt, rounds: MDKSniperRounds) -> void:
	canvas.draw_texture(_frame, Vector2.ZERO)
	for i in ROUND_VIEWS.size():
		var rect: Rect2 = ROUND_VIEWS[i]
		rect.position += VIEW_ORIGIN
		var camera: Dictionary = rounds.get_camera(i) if rounds else {"fill": 0}
		if camera.has("transform"):
			_cameras[i].global_transform = camera.transform
			_views[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS
			canvas.draw_texture_rect(_views[i].get_texture(), rect, false)
			continue
		_views[i].render_target_update_mode = SubViewport.UPDATE_DISABLED
		if camera.fill >= 0:
			canvas.draw_rect(rect, _palette.get_color(camera.fill))
		else:
			# A miss: `SNIPERGA`, a frame every 2 ticks.
			canvas.draw_rect(rect, Color.BLACK)
			var frame := int((30.0 - camera.time) / 2.0) % _miss_frames.size()
			var texture := _miss_frames[frame]
			canvas.draw_texture(texture, rect.get_center() - texture.get_size() / 2.0)
	canvas.draw_texture(_mask, VIEW_ORIGIN)
	canvas.draw_texture(_cross, VIEW_ORIGIN + CROSSHAIR - Vector2(_cross_hotspot))
	# The zoom in percent: (1 − zoom)² × 1.05194 (59% at 4×), and the gauge showing as much of its
	# height.
	var fraction := clampf(pow(1.0 - kurt.zoom, 2.0) * 1.05194, 0.0, 1.0)
	var percent := roundi(100.0 * fraction)
	canvas._draw_number(percent, VIEW_ORIGIN + ZOOM_DIGITS)
	var goal := roundi(GAUGE_HEIGHT * fraction)
	_gauge_shown = clampi(goal, _gauge_shown - GAUGE_SPEED, _gauge_shown + GAUGE_SPEED)
	if _gauge_shown > 0:
		var top := GAUGE_HEIGHT - _gauge_shown
		canvas.draw_texture_rect_region(_gauge, Rect2(VIEW_ORIGIN + GAUGE + Vector2(0, top), Vector2(_gauge.get_width(), _gauge_shown)),
				Rect2(0, top, _gauge.get_width(), _gauge_shown))
	canvas.draw_texture(_weapon, VIEW_ORIGIN + WEAPON)
	var selected := kurt.inventory.selected_ammo
	for i in 6:
		if i == 0 or kurt.inventory.ammo[i - 1] > 0:
			canvas.draw_texture(_icons[i], VIEW_ORIGIN + TYPE_ICONS[i])
	canvas.draw_texture(_labels[selected], VIEW_ORIGIN + TYPE_LABELS[selected])
	if selected > 0:
		canvas._draw_number(kurt.inventory.ammo[selected - 1], VIEW_ORIGIN + COUNT)

## The in-game HUD, drawn like the original (`0x41e128`) on the 600×360 view, scaled to the window:
## Kurt's health in the `SC_STAT` panel (bottom right, digits from `SNIP_TXT`, blinking at 20 or
## less, 0x420830), and the inventory for 2 seconds after it changes (`PICKUPS` icons in 5 slots
## at the bottom left, 0x46cce4), messages (`HUDMessages`) and the health bar of the object Kurt
## shoots at (top left, 0x41e3c8). See `docs/gameplay.md` ("HUD").
class_name HUD
extends Control

const VIEW_HEIGHT := 360.0
## The inventory stays on screen this long after a change (`0x574328`, in ticks).
const INVENTORY_TICKS := 60
## The health bar: 500 pixels for 900 hit points, from y 4 to 10, filled with palette colour 3
## and framed (up to the maximum) with colour 4.
const BAR_SCALE := 500.0 / 900.0
const BAR_WIDTH := 500

var kurt: Kurt
var scripts: MDKScriptRuntime
var messages := HUDMessages.new()

var _panel: Texture2D
var _skull: Texture2D
var _digits: Texture2D
var _digit_height := 0
var _icons: Array[Texture2D] = []
var _icon_hotspots: Array[Vector2i] = []
var _inventory_ticks := 0
var _last_inventory := ""
var _blink := 0
var _bar_fill := Color()
var _bar_frame := Color()


func setup(p_kurt: Kurt, sprites: MDKBni, palette: MDKPalette, fti: MDKFti) -> void:
	kurt = p_kurt
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	messages.setup(fti, palette)
	kurt.inventory.picked_up.connect(func(text_name: String) -> void: messages.push(text_name, HUDMessages.FLAG_ZOOM, 2.0))
	_bar_fill = palette.get_color(3)
	_bar_frame = palette.get_color(4)
	_panel = _make_texture(sprites.get_image("SC_STAT"), palette)
	_skull = _make_texture(sprites.get_image("SKULL"), palette)
	var digits := sprites.get_image("SNIP_TXT")
	_digits = _make_texture(digits, palette)
	_digit_height = digits.height
	var pickups := sprites.get_animation("PICKUPS")
	for i in pickups.frame_count:
		_icons.push_back(_make_texture(pickups.get_frame(i), palette))
		_icon_hotspots.push_back(pickups.get_hotspot(i))


## Converts a paletted image to a texture (index 0 is transparent).
static func _make_texture(texture: MDKTexture, palette: MDKPalette) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(texture.indices.size() * 4)
	for i in texture.indices.size():
		var index := texture.indices[i]
		if index == 0:
			continue
		var color := palette.get_color(index)
		data[i * 4] = color.r8
		data[i * 4 + 1] = color.g8
		data[i * 4 + 2] = color.b8
		data[i * 4 + 3] = 255
	var image := Image.create_from_data(texture.width, texture.height * texture.frame_count, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(image)


func _physics_process(_delta: float) -> void:
	if not kurt:
		return
	_blink = (_blink + 1) & 31
	# Show the inventory for a while whenever it changes.
	var state := str(kurt.inventory.selected) + "|" + str(kurt.inventory.slots.map(func(s: KurtInventory.Slot) -> String: return "%d:%d" % [s.item, s.count]))
	if state != _last_inventory:
		_last_inventory = state
		_inventory_ticks = INVENTORY_TICKS
	elif _inventory_ticks > 0:
		_inventory_ticks -= 1
	queue_redraw()


func _process(delta: float) -> void:
	messages.update(delta)


## Scale from the original 600×360 view to the window.
func _scale() -> float:
	return size.y / VIEW_HEIGHT


func _draw() -> void:
	if not kurt or not _panel:
		return
	# Hits flash the screen red; when Kurt is dead the skull fades in instead.
	if kurt.state == Kurt.State.DEAD:
		var s0 := _scale()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s0, s0))
		var center := Vector2(size.x / s0 / 2.0, VIEW_HEIGHT / 2.0)
		draw_texture(_skull, center - _skull.get_size() / 2.0, Color(1, 1, 1, clampf(kurt.hurt_flash / 255.0, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kurt.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, kurt.hurt_flash / 255.0 * 0.4))
	if kurt.white_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, minf(kurt.white_flash / 255.0, 1.0)))
	var s := _scale()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var view := size / s
	# Health panel at the bottom right; the number blinks when health is low.
	var panel_position := Vector2(view.x - (_panel.get_width() + 16), VIEW_HEIGHT - (_panel.get_height() + 10))
	draw_texture(_panel, panel_position)
	if kurt.health > 20 or _blink < 16:
		var center := panel_position + Vector2(_panel.get_width() >> 1, (_panel.get_height() - _digit_height) >> 1)
		_draw_number(kurt.health, center)
	if _inventory_ticks > 0:
		_draw_inventory()
	if scripts:
		_draw_bar(scripts.get_bar())
	messages.draw(self, view.x)


func _draw_bar(bar: Vector2i) -> void:
	if bar.y <= 0:
		return
	var fill := clampi(roundi(bar.x * BAR_SCALE), 0, BAR_WIDTH)
	var frame := clampi(roundi(bar.y * BAR_SCALE), 0, BAR_WIDTH)
	draw_rect(Rect2(0, 4, fill + 1, 7), _bar_fill)
	draw_rect(Rect2(0.5, 4.5, frame, 6), _bar_frame, false, 1.0)


## Draws a number (at most 999) centred on `position.x`, with 8-pixel wide digits (0x420bd0).
func _draw_number(value: int, position: Vector2) -> void:
	var text := str(mini(value, 999))
	var x := position.x - 4 * text.length()
	for c in text:
		var digit := int(c)
		draw_texture_rect_region(_digits, Rect2(x, position.y, 8, _digit_height), Rect2(digit * 8, 0, 8, _digit_height))
		x += 8


func _draw_inventory() -> void:
	var inventory := kurt.inventory
	var selected := inventory.selected
	if selected < inventory.slots.size() and inventory.slots[selected].item != KurtInventory.Item.SUPER_CHAIN_GUN:
		var x := selected * 48
		draw_rect(Rect2(x + 9, 305, 45, 45), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x + 8, 304, 47, 47), Color(0.75, 0.75, 0.75), false, 1.0)
	for i in inventory.slots.size():
		var slot := inventory.slots[i]
		var frame: int = slot.item - 1
		if frame < 0 or frame >= _icons.size():
			continue
		var position := Vector2(32 + i * 48, 328)
		draw_texture(_icons[frame], position - Vector2(_icon_hotspots[frame]))
		var count := inventory.super_chain_gun if slot.item == KurtInventory.Item.SUPER_CHAIN_GUN else slot.count
		if count > 1:
			_draw_number(count, position - Vector2(0, 12))

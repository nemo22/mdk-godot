## On-screen messages: texts of `MISC/MDKFONT.FTI` queued by `hud_message` (opcode 247), pickups
## and a few events (0x425400), shown one after the other in the big font (0x425474).
##
## A message has one or two lines (split at the `\n` escape), centred on the 600×360 view with
## their baseline at y 120 (two lines: 105 and 135). With flag 1 it grows from nothing in half a
## second, and shrinks back once its time is up; without it, it just appears and disappears. Its
## time runs twice as fast while other messages wait. Flag 2 puts it at the front of the queue.
## A line too wide for the big font is drawn in the small one (0x415b30).
class_name HUDMessages
extends RefCounted

const FLAG_ZOOM := 1
const FLAG_FRONT := 2
## The queue has 4 entries (`0x57ecf0`, 12 bytes each: time, flags, text).
const QUEUE_SIZE := 4
## Seconds to grow or shrink (0.5 × 2 = full size).
const ZOOM_TIME := 0.5
const VIEW_WIDTH := 600.0
const BASELINE := 120.0
const LINE_OFFSET := 15.0


class Message:
	var lines: Array[PackedByteArray] = []
	var flags := 0
	var time := 0.0


var fti: MDKFti
var big_font: MDKFont
var small_font: MDKFont
var _queue: Array[Message] = []
var _current: Message
## Time the current message stays (`0x57ece0`) and its zoom timer (`0x57ece4`, 0–0.5).
var _time := 0.0
var _zoom := 0.0


func setup(p_fti: MDKFti, palette: MDKPalette) -> void:
	fti = p_fti
	big_font = MDKFont.load_font(fti, "FONTBIG", palette, 6)
	small_font = MDKFont.load_font(fti, "FONTSML", palette, 4)


## Queues the text `text_name` (0x425400). Returns false if the text doesn't exist.
func push(text_name: String, flags: int, time: float) -> bool:
	var text := fti.get_text_bytes(text_name) if fti else PackedByteArray()
	if text.is_empty():
		return false
	var message := Message.new()
	message.flags = flags
	message.time = time
	# At most two lines of 35 characters.
	var start := 0
	while message.lines.size() < 2:
		var end := _find_line_break(text, start)
		message.lines.push_back(text.slice(start, mini(end, start + 35)))
		if end >= text.size():
			break
		start = end + 2
	if flags & FLAG_FRONT:
		_queue.push_front(message)
	else:
		_queue.push_back(message)
	if _queue.size() > QUEUE_SIZE:
		_queue.pop_back()
	return true


static func _find_line_break(text: PackedByteArray, start: int) -> int:
	for i in range(start, text.size() - 1):
		if text[i] == 0x5C and text[i + 1] == 0x6E:  # `\n`
			return i
	return text.size()


## Advances the messages by `delta` seconds (0x425474, once per frame).
func update(delta: float) -> void:
	var step := delta * 2.0 if not _queue.is_empty() else delta
	if _time == 0.0:
		if _zoom == 0.0:
			_current = _queue.pop_front() if not _queue.is_empty() else null
			if _current:
				_time = _current.time
		else:
			_zoom = maxf(_zoom - delta, 0.0)
	elif not _current.flags & FLAG_ZOOM or _zoom == ZOOM_TIME:
		_time = maxf(_time - step, 0.0)
	else:
		_zoom = minf(_zoom + delta, ZOOM_TIME)


## Draws the current message on `canvas`, whose view is `view_width` wide (600 in the original).
func draw(canvas: CanvasItem, view_width: float) -> void:
	if not _current:
		return
	var full := _time > 0.0 and (not _current.flags & FLAG_ZOOM or _zoom == ZOOM_TIME)
	var scale := 1.0 if full else _zoom * 2.0
	if scale <= 0.0:
		return
	var center := view_width / 2.0
	var lines := _current.lines
	for i in lines.size():
		var y := BASELINE
		if lines.size() == 2:
			y += (LINE_OFFSET if i == 1 else -LINE_OFFSET) * scale
		var font := big_font
		if full and big_font.get_width(lines[i]) >= VIEW_WIDTH:
			font = small_font
		var x := roundf(center - font.get_width(lines[i]) * scale / 2.0)
		font.draw(canvas, lines[i], x, roundf(y), scale)

## The screens between levels (game state 6: 0x431b00, each frame 0x43200c). See
## docs/gameplay.md, "Statistics and briefing (state 6)".
##
## After a level: the intermission (`L1_INTRM`), the debriefing on the level's map, the
## Score-O-matic, then the briefing of the next level on its map. A new game shows only the
## briefing. Every page fades in (from white for the intermission, else from black) over 0.5 s,
## waits for a key once it's fully shown and fades out to black. Esc skips; holding Fire or Jump
## runs everything twice as fast (typing 4×). All on the 600×360 screen.
class_name StatsScreen
extends Control

enum Phase { SCORE = 1, INTERMISSION = 2, BRIEFING = 3, DEBRIEFING = 4 }

const VIEW := Vector2(600.0, 360.0)
const FADE_SPEED := 2.0
## Typing (0x4335c0): characters per second, and when fast.
const TYPE_RATE := 15.0
const TYPE_RATE_FAST := 60.0
const LINE_HEIGHT := 36.0
const DEBRIEF_Y := [64.0, 120.0, 300.0]
const BRIEF_Y := 32.0
## Debriefing texts by the town flags' bits 31–29 (`0x57440f`).
const DEBRIEF_RESULTS := ["S", "S", "F", "S", "SS", "SF", "FS", "FF"]
## Score-O-matic rows (tables 0x491b78 and 0x491bd8): label, start and end `x, y, bar width, scale`.
const ROWS := [
	["ST_SHF", Vector4(300, 85, 240, 256), Vector4(180, 75, 120, 128)],
	["ST_ACC", Vector4(300, 155, 240, 256), Vector4(420, 75, 120, 128)],
	["ST_SNF", Vector4(300, 155, 240, 256), Vector4(180, 125, 120, 128)],
	["ST_ACC", Vector4(300, 225, 240, 256), Vector4(420, 125, 120, 128)],
	["ST_KILL", Vector4(300, 225, 240, 256), Vector4(300, 175, 120, 128)],
]
const HEAD_LABEL := Vector2(300.0, 255.0)
const ROW_WAIT := 0.5
const BAR_COLOR := 63
const BAR_HEIGHT := 16.0
## The heads (0x433268): at most 16, spinning at 157°/s, seen from the origin along +y with a focal
## length of 250 pixels.
const HEAD_SPIN := 157.0
const HEAD_FOCAL := 250.0

## Set before the scene starts: only the briefing of `GameState.level` (a new game).
static var briefing_only := false

var _fti: MDKFti
var _bni: MDKBni
var _big: MDKFont
var _small: MDKFont
var _system_rgb := PackedByteArray()
var _canvas := Control.new()
var _phases: Array[Phase] = []
var _phase := Phase.INTERMISSION
var _index := 0
var _image: Texture2D
var _fade_in := 0.0
var _fade_out := -1.0
var _fade_color := Color.BLACK
var _fast := false
var _skip := false
var _pressed := false
var _ticks := 0.0
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _loop_player := AudioStreamPlayer.new()
var _teletype := AudioStreamPlayer.new()

# Typing: the texts of the page, their baselines, and the characters shown of the current one.
var _texts: Array[PackedByteArray] = []
var _text_y: Array[float] = []
var _current := 0
var _count := 0.0
var _shown := 0

# Score-O-matic.
var _row := 0
var _row_time := 0.0
var _row_stage := 0
var _values: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _targets: Array[int] = [0, 0, 0, 0, 0]
var _fulls: Array[int] = [0, 0, 0, 0, 0]
var _slides: Array[float] = [-1.0, -1.0, -1.0, -1.0, -1.0]
var _heads := 0
var _head_time := 0.0
var _head_view := SubViewport.new()
var _head_nodes: Array[MeshInstance3D] = []
var _head_mesh: ArrayMesh


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_fti = MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))
	_bni = MDKBni.load_file(MDKData.path("MISC/STATS.BNI"))
	_system_rgb = _fti.get_bytes("SYS_PAL").slice(0, 768)
	var system := MDKPalette.from_rgb(_system_rgb)
	_big = MDKFont.load_font(_fti, "FONTBIG", system, 6)
	_small = MDKFont.load_font(_fti, "FONTSML", system, 4)
	for sound_name in ["CGUN", "SNIPER", "RICO1", "RICO2", "RICO3", "ALDIE", "XGHEAD1", "XGHEAD2", "TELETYPE"]:
		var entry: Array = _bni.entries.get(sound_name, [])
		if not entry.is_empty():
			_sounds[sound_name] = MDKSound.load_wav(_bni.bytes.slice(entry[0], entry[0] + entry[1]), sound_name == "CGUN")
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = &"Effects"
		add_child(player)
		_players.push_back(player)
	_loop_player.bus = &"Effects"
	add_child(_loop_player)
	_teletype.bus = &"Effects"
	_teletype.stream = _sounds.get("TELETYPE")
	add_child(_teletype)
	_setup_heads()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)

	_index = maxi(GameState.index_of(GameState.level), 0)
	if briefing_only:
		_phases = [Phase.BRIEFING]
	else:
		_phases = [Phase.INTERMISSION, Phase.DEBRIEFING, Phase.SCORE, Phase.BRIEFING]
	_test_options()
	_start_phase(_phases.pop_front())


## Test options (see `main_menu.gd`): `--phase`, `--counts`, `--towns`, `--wait` and `--screenshot`.
func _test_options() -> void:
	var args := Args.get_all()
	if args.has("counts"):
		var counts: PackedFloat64Array = args.counts.split_floats(",")
		for i in mini(counts.size(), 7):
			GameState.stats[["shots", "shot_hits", "sniper_shots", "sniper_hits", "kills", "enemies", "head_shots"][i]] = int(counts[i])
	if args.has("towns"):
		GameState.town_flags = int(args.towns) << 29
	if args.has("phase"):
		while _phases.size() > 1 and _phases[0] != int(args.phase):
			_phases.pop_front()
	if args.has("screenshot"):
		await get_tree().create_timer(float(args.get("wait", "3"))).timeout
		Args.screenshot_and_quit(get_tree(), args.screenshot, 2)


## A page's palette: the system colours 0–63 and the image's 64–255.
func _palette(rgb: PackedByteArray) -> MDKPalette:
	var colors := _system_rgb.slice(0, 192)
	colors.append_array(rgb.slice(192, 768))
	return MDKPalette.from_rgb(colors)


## An image of `STATS.BNI`: a 768-byte palette, `u16 width, height`, pixels.
func _load_image(entry_name: String) -> Texture2D:
	var entry: Array = _bni.entries[entry_name]
	var palette := _palette(_bni.bytes.slice(entry[0], entry[0] + 768))
	var texture := MDKTexture.parse(entry_name, _bni.bytes, entry[0] + 768)
	return ImageTexture.create_from_image(palette.make_image(texture.width, texture.height, texture.indices))


func _start_phase(phase: Phase) -> void:
	_phase = phase
	_fade_in = 0.0
	_fade_out = -1.0
	_fade_color = Color.WHITE if phase == Phase.INTERMISSION else Color.BLACK
	_texts.clear()
	_text_y.clear()
	_current = 0
	_count = 1.0
	_shown = 0
	_image = null
	match phase:
		Phase.INTERMISSION:
			_image = _load_image("L1_INTRM")
		Phase.DEBRIEFING:
			_image = _load_image("L%d_MAP" % (_index + 1))
			var result: String = DEBRIEF_RESULTS[(GameState.town_flags >> 29) & 7]
			var text_name := "DEB%d%s" % [_index + 1, result]
			if not _fti.entries.has(text_name):
				text_name = "DEB%dS" % (_index + 1)
			for entry_name in ["DEBTOP", text_name, "DEBBOT"]:
				_texts.push_back(_fti.get_text_bytes(entry_name))
			_text_y.assign(DEBRIEF_Y)
		Phase.SCORE:
			_start_score()
		Phase.BRIEFING:
			# On entry the inventory is emptied and the health raised to 100 (the port starts every
			# level with both anyway).
			_image = _load_image("L%d_MAP" % (_index + 1))
			_texts.push_back(_fti.get_text_bytes("BRIEF%d" % (_index + 1)))
			_text_y.push_back(BRIEF_Y)


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			_skip = true
		_pressed = true
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_fast = _skip or Input.is_action_pressed(&"fire") or Input.is_action_pressed(&"jump")
	var speed := 2.0 if _fast else 1.0
	_ticks += delta * 30.0
	if _fade_out >= 0.0:
		_fade_out += FADE_SPEED * speed * delta
		if _fade_out >= 1.0:
			_next_phase()
		_canvas.queue_redraw()
		_skip = false
		_pressed = false
		return
	if _fade_in < 1.0:
		_fade_in = minf(_fade_in + FADE_SPEED * speed * delta, 1.0)
	elif _update_page(delta, speed) and (_pressed or _fast):
		_fade_out = 0.0
		_loop_player.stop()
	_update_heads(delta)
	_skip = false
	_pressed = false
	_canvas.queue_redraw()


## Advances the page; true once everything is shown.
func _update_page(delta: float, speed: float) -> bool:
	match _phase:
		Phase.INTERMISSION:
			return true
		Phase.DEBRIEFING, Phase.BRIEFING:
			return _update_typing(delta)
		Phase.SCORE:
			return _update_score(delta, speed)
	return true


func _next_phase() -> void:
	if _phase == Phase.SCORE:
		# The index moves on to the next level (the original then offers to save).
		_index = mini(_index + 1, GameState.ORDER.size() - 1)
		GameState.level = GameState.ORDER[_index]
	if _phases.is_empty():
		briefing_only = false
		get_tree().change_scene_to_file("res://game/main.tscn")
		return
	_start_phase(_phases.pop_front())


func _play(sound_name: String) -> void:
	var stream: AudioStream = _sounds.get(sound_name)
	if not stream:
		return
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.play()
			return
	_players[0].stream = stream
	_players[0].play()


# --- Typing ---------------------------------------------------------------------------------------

## Types the page's texts one after the other; Esc finishes the current one (the briefing: all).
func _update_typing(delta: float) -> bool:
	if _current >= _texts.size():
		return true
	var total := _typeset(_texts[_current], 0.0, -1, false)
	if _skip:
		if _phase == Phase.BRIEFING:
			_current = _texts.size()
			return false
		_count = total
	else:
		_count += (TYPE_RATE_FAST if _fast else TYPE_RATE) * delta
	var shown := mini(roundi(_count), total)
	if shown != _shown:
		_shown = shown
		_teletype.play()
	if _count >= total:
		_current += 1
		_count = 0.0
		_shown = 0
		return _current >= _texts.size()
	return false


## Lays out (and draws when `draw`) a text like 0x4335c0 with a budget of `budget` characters
## (−1: all). Returns the number of characters of the whole text.
func _typeset(text: PackedByteArray, y: float, budget: int, draw: bool) -> int:
	var x := 0.0
	var centred := false
	var line := PackedByteArray()
	var line_start := 0
	var count := 0
	var cost := true
	var i := 0
	var remaining := budget
	var lines := []
	while i < text.size():
		var c := text[i]
		i += 1
		if c != 0x5C:
			line.push_back(c)
			if cost:
				count += 1
			continue
		var j := i
		while j < text.size() and (text[j] >= 0x30 and text[j] <= 0x39 or text[j] == 0x2D):
			j += 1
		var has_number := j > i
		var number := text.slice(i, j).get_string_from_ascii().to_int() if has_number else 0
		var code := char(text[j]) if j < text.size() else ""
		i = j + 1
		match code:
			"c", "n", "x", "y":
				lines.push_back([line, x, y, centred, line_start])
				line_start = count
				line = PackedByteArray()
				match code:
					"c":
						x = float(number) if has_number else 300.0
						centred = true
					"x":
						x = float(number) if has_number else 0.0
						centred = false
					"n":
						x = 0.0
						centred = false
						y += LINE_HEIGHT + number
					"y":
						x = 0.0
						centred = false
						y += float(number) if has_number else LINE_HEIGHT
			"p":
				count += number
			"d":
				cost = true
			"i":
				cost = false
	lines.push_back([line, x, y, centred, line_start])
	if draw:
		if remaining < 0:
			remaining = count
		for n in lines.size():
			var entry: Array = lines[n]
			var full: PackedByteArray = entry[0]
			var start: int = entry[4]
			if start > remaining:
				break
			var part := full.slice(0, mini(full.size(), remaining - start))
			# The cursor follows the last line being typed.
			var last: bool = n + 1 == lines.size() or lines[n + 1][4] > remaining
			if last and remaining < count:
				part.push_back(0x5F if int(_ticks) & 31 <= 15 else 0x20)
			var left: float = entry[1]
			if entry[3]:
				# A centred line is placed by its whole width, so it doesn't move while typed.
				left -= _big.get_width(full) >> 1
			_big.draw(_canvas, part, left, entry[2])
	return count


# --- Score-O-matic ---------------------------------------------------------------------------------

func _start_score() -> void:
	var stats := GameState.stats
	_targets = [stats.shots, stats.shot_hits * 100 / stats.shots if stats.shots > 0 else 0,
			stats.sniper_shots, stats.sniper_hits * 100 / stats.sniper_shots if stats.sniper_shots > 0 else 0,
			stats.kills]
	_fulls = [stats.shots, 100, stats.sniper_shots, 100, stats.enemies]
	_values = [0.0, 0.0, 0.0, 0.0, 0.0]
	_slides = [-1.0, -1.0, -1.0, -1.0, -1.0]
	_row = 0
	_row_stage = 0
	_row_time = 0.0
	_heads = 0
	_head_time = 0.0
	for node in _head_nodes:
		node.visible = false


## The rows one at a time (0x4328a4): wait, show big (`SNIPER`), wait, count up (about 2 s), slide
## to the final place; then the heads.
func _update_score(delta: float, speed: float) -> bool:
	for i in _slides.size():
		if _slides[i] >= 0.0 and _slides[i] < 1.0:
			_slides[i] = 1.0 if _skip else minf(_slides[i] + 2.0 * speed * delta, 1.0)
	if _row < ROWS.size():
		_update_row(delta, speed)
		return false
	return _update_head_row(delta, speed)


func _update_row(delta: float, speed: float) -> void:
	_row_time += delta * speed
	match _row_stage:
		0:
			if _row_time >= ROW_WAIT or _skip:
				_row_stage = 1
				_row_time = 0.0
				# Shown big (t = 0) until the slide starts.
				_slides[_row] = -0.5
				_play("SNIPER")
		1:
			if _row_time >= ROW_WAIT or _skip:
				_row_stage = 2
		2:
			var target := _targets[_row]
			if _skip:
				_values[_row] = target
			else:
				_values[_row] = minf(_values[_row] + maxf(1.0, roundf(target * delta * 0.5)) * speed, target)
				var loop := "ALDIE" if _row == 4 else "CGUN"
				if _row == 4:
					if not _players.any(func(p: AudioStreamPlayer) -> bool: return p.playing and p.stream == _sounds.get("ALDIE")):
						_play("ALDIE")
				elif not _loop_player.playing:
					_loop_player.stream = _sounds.get(loop)
					_loop_player.play()
				if (_row == 1 or _row == 3) and randi() % 8 == 0:
					_play("RICO%d" % (randi() % 3 + 1))
			if _values[_row] >= target:
				_loop_player.stop()
				_slides[_row] = 0.0
				_row += 1
				_row_stage = 0
				_row_time = 0.0


## Head shots (0x433268): one spinning head a second (two a second when fast, all at once on Esc).
func _update_head_row(delta: float, speed: float) -> bool:
	var count: int = GameState.stats.head_shots
	if _row == ROWS.size():
		_row_time += delta * speed
		if _row_stage == 0 and (_row_time >= ROW_WAIT or _skip):
			_play("SNIPER")
			_row_stage = 1
			_row_time = 0.0
		elif _row_stage == 1 and (_row_time >= ROW_WAIT or _skip):
			_row += 1
			_head_time = 1.0
	if _row == ROWS.size():
		return false
	if _heads >= count:
		return true
	if _skip:
		_heads = count
	else:
		_head_time += delta * speed
		if _head_time < 1.0:
			return false
		_head_time = 0.0
		_heads += 1
		_play("XGHEAD%d" % (randi() % 2 + 1))
	_place_heads(count)
	return _heads >= count


func _setup_heads() -> void:
	_head_view.size = Vector2i(VIEW)
	_head_view.transparent_bg = true
	_head_view.own_world_3d = true
	_head_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_head_view)
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = rad_to_deg(2.0 * atan(VIEW.y * 0.5 / HEAD_FOCAL))
	camera.near = 0.5
	_head_view.add_child(camera)
	var entry: Array = _bni.entries.get("XGHEAD", [])
	if entry.is_empty():
		return
	var model := MDKModel.parse("XGHEAD", _bni.bytes, entry[0], false)
	var pal_entry: Array = _bni.entries["PAL"]
	var palette := _palette(_bni.bytes.slice(pal_entry[0], pal_entry[0] + 768))
	var archive := MDKTextureArchive.load_file(MDKData.path("MISC/STATS.MTI"))
	var archives: Array[MDKTextureArchive] = [archive]
	var resolver := MDKMeshBuilder.MaterialResolver.new(palette, archives)
	_head_mesh = MDKMeshBuilder.build_model_mesh(model, model.get_rest_pose(), resolver)
	for i in 16:
		var node := MeshInstance3D.new()
		node.mesh = _head_mesh
		node.scale = Vector3.ONE * 0.8
		node.visible = false
		_head_view.add_child(node)
		_head_nodes.push_back(node)


## Places the heads shown: one row below 5, else two rows of `(count + 1) / 2` (8 at most).
func _place_heads(count: int) -> void:
	var per_row := count if count < 5 else ((count + 1) / 2 if count <= 16 else 8)
	var shown := mini(_heads, per_row * 2)
	for i in _head_nodes.size():
		var node := _head_nodes[i]
		node.visible = i < shown
		if not node.visible:
			continue
		var row := i / per_row
		var k := i % per_row
		var m := mini(per_row, shown - row * per_row)
		var x := 20.0 * (k + 1) / (m + 1) - 10.0
		var z := -3.0 if row == 0 else -4.5
		node.position = MDKMeshBuilder.to_godot(Vector3(x, 8.0, z))


func _update_heads(delta: float) -> void:
	for node in _head_nodes:
		if node.visible:
			node.rotate_y(deg_to_rad(HEAD_SPIN) * delta)


# --- Drawing --------------------------------------------------------------------------------------

func _draw_screen() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var scale := minf(size.x / VIEW.x, size.y / VIEW.y)
	var origin := (size - VIEW * scale) / 2.0
	_canvas.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	if _image:
		_canvas.draw_texture(_image, Vector2.ZERO)
	var shown := _fade_in >= 1.0
	match _phase:
		Phase.DEBRIEFING, Phase.BRIEFING:
			if shown:
				for i in mini(_current + 1, _texts.size()):
					_typeset(_texts[i], _text_y[i], -1 if i < _current else roundi(_count), true)
		Phase.SCORE:
			_draw_score(shown)
	# Fades: the page is blended with white or black.
	var fade := 1.0 - _fade_in if _fade_out < 0.0 else _fade_out
	if fade > 0.0:
		var color := _fade_color if _fade_out < 0.0 else Color.BLACK
		color.a = fade
		_canvas.draw_rect(Rect2(Vector2.ZERO, VIEW), color)


func _draw_score(shown: bool) -> void:
	_canvas.draw_texture(_head_view.get_texture(), Vector2.ZERO)
	var title := _fti.get_text_bytes("ST_SCR")
	_big.draw(_canvas, title, 300 - (_big.get_width(title) >> 1), 28)
	var name := _fti.get_text_bytes("ST_DAMP")
	_small.draw(_canvas, name, 300 - (_small.get_width(name) >> 1), 48)
	if not shown:
		return
	var palette := MDKPalette.from_rgb(_system_rgb)
	for i in ROWS.size():
		if _slides[i] == -1.0:
			continue
		var t := clampf(_slides[i], 0.0, 1.0)
		var place: Vector4 = (ROWS[i][1] as Vector4).lerp(ROWS[i][2], t).round()
		var scale := place.w / 256.0
		var label := _fti.get_text_bytes(ROWS[i][0])
		_big.draw(_canvas, label, place.x - roundf(_big.get_width(label) * scale * 0.5), place.y, scale)
		var bar := Vector2(place.x - place.z / 2.0, roundf(place.y + 18.0 * scale))
		var value := int(_values[i])
		if _fulls[i] > 0 and value > 0:
			_canvas.draw_rect(Rect2(bar, Vector2(floorf(place.z * value / _fulls[i]), BAR_HEIGHT)), palette.get_color(BAR_COLOR))
		var text := ("%d/%d" % [value, _fulls[i]]) if i == 4 else ("%d%%" % value if i == 1 or i == 3 else "%d" % value)
		var bytes := text.to_ascii_buffer()
		_small.draw(_canvas, bytes, bar.x - _small.get_width(bytes) - 8, bar.y + 14)
	if _row >= ROWS.size():
		var label := _fti.get_text_bytes("ST_HEAD")
		_big.draw(_canvas, label, HEAD_LABEL.x - (_big.get_width(label) >> 1), HEAD_LABEL.y)

## The fall before a level (game state 2, `fall_3d.c`: init 0x410018, each frame 0x4114a4, the
## intro 0x41106c). See docs/gameplay.md, "The fall".
##
## Kurt falls from orbit onto the minecrawler: 5 seconds of intro in space, then 33 seconds of fall
## over the ground (`LEVELn` of `FALL3D_n.MTI`, drawn by `fall_ground.gdshader`) while radars look
## for him, missiles home on him and pickups fall with chutes. The camera looks straight down with a
## focal length of 250 pixels on the 600×360 view (wider windows see more on the sides). The health
## and the inventory go on to the level (`GameState.carry`); health at 0 is game over.
##
## Esc skips the fall (the port's addition). Test options (after `--`): `--fall=N` in the main menu
## starts the fall of LEVELn; `--wait=seconds` and `--screenshot=path.png`; `--god` (no damage).
class_name MDKFall
extends Control

const VIEW_HEIGHT := 360.0
const FOCAL := 250.0
const INTRO_TICKS := 150
## Kurt steers until 30 s, the view goes black from 31 s, the fall ends at 33 s.
const STEER_TIME := 30.0
const FADE_TIME := 31.0
const END_TIME := 33.0
const KURT_START_Z := 5270.0
const KURT_SPEED := 2000.0 / 30.0
## Steering (`vel_accel_dt`): 11.765 u/s per tick up to 117.65 u/s, within ±58.82 × ±35.29.
const STEER_STEP := 200.0 / 17.0
const STEER_MAX := 2000.0 / 17.0
const LIMIT := Vector2(1000.0 / 17.0, 600.0 / 17.0)
const KURT_BOX := Vector3(4.0, 4.0, 5.0)
## Kurt's angles (+0x4c yaw 90°, +0x13c pitch −90°): lying face down.
const KURT_YAW := 90.0
const KURT_PITCH := -90.0
const RADAR_EXTEND_SPEED := 3000.0
const RADAR_RETRACT_SPEED := 1500.0
const RADAR_RADIUS := 10.0
const RADAR_SEE := 15.0
## Radar colours −(0x405 + c): the palette blended towards green by these / 256 ❓.
const RADAR_ALPHA := [48, 64, 80, 96, 128]
const PICKUP_FALL_SPEED := 2 * KURT_SPEED
const PICKUP_CHUTE_SPEED := 50.0
const BONES_SPEED := 2000.0 / 27.0
const EXPLOSION_TICKS := 26
const ON_TOP_SHADER := preload("res://game/fall/fall_on_top.gdshader")
## Blend towards white of the haze tables 1–24 (0x490d1c, / 256).
const HAZE_BLEND := [0, 0, 0, 0, 0, 0, 0, 0, 3, 6, 12, 18, 24, 48, 72, 96, 120, 144, 168, 192, 215, 230, 245, 255]
const WIND_FULL := 0xC00
const HIT_SOUNDS := ["K_HIT1", "K_HIT2", "K_HIT3", "K_HIT4", "K_HIT5", "K_HIT6", "K_HIT7"]
## Models with named parts (bit 7 of the table 0x490ca4).
const NAMED_PARTS := ["KURT", "MISSILE", "CHUTE", "BONES", "SW_DUMMY", "SW_H150", "SW_THUMP", "SW_TWIST", "SW_INTER"]

enum RadarState { EXTEND, TRACK, RETRACT }


class Thing:
	var node: MeshInstance3D
	var position := Vector3()
	var velocity := Vector3()
	var ticks := 0.0


class Pickup extends Thing:
	var pickup_name := ""
	var fall_ticks := 0
	var chute: MeshInstance3D
	var yaw := 0.0


var index := 0
var difficulty := 1
var health := 100
var inventory := KurtInventory.new()

var _bni: MDKBni
var _mti: MDKTextureArchive
var _sni: MDKSni
var _fti: MDKFti
var _palette: MDKPalette
var _space_palette: MDKPalette
var _resolver: MDKMeshBuilder.MaterialResolver
var _models := {}
var _animations := {}
var _baked := {}
var _meshes := {}
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _wind_player := AudioStreamPlayer.new()
var _grind_player := AudioStreamPlayer.new()
var _messages := HUDMessages.new()

# Difficulty (0x410018).
var _beam_speed := 0.0
var _missiles_per_detection := 0
var _spread := 0.0
var _missile_gap := 0
var _radar_gap := 0

# Nodes: the ground, the sprites and images behind the models, the models, the HUD, the palette effects.
var _ground := ColorRect.new()
var _ground_material := ShaderMaterial.new()
var _back := Control.new()
var _view := SubViewport.new()
var _view_rect := TextureRect.new()
var _hud := Control.new()
var _screen := ColorRect.new()
var _screen_material := ShaderMaterial.new()
var _camera := Camera3D.new()
var _world := Node3D.new()

var _intro_left := INTRO_TICKS
var _time := 0.0
var _tick_fraction := 0.0
var _ended := false
var _god := false

var _kurt: Thing
var _kurt_animation := "KURTANIM"
var _kurt_frame := 0.0
var _kurt_finished := false
var _bones: Thing
var _bones_passed := false
var _camera_position := Vector3()
var _camera_speed := -KURT_SPEED
var _wind := 0

var _radar: MeshInstance3D
var _radar_mesh := ImmediateMesh.new()
var _radar_materials: Array[StandardMaterial3D] = []
var _radar_active := false
var _radar_state := RadarState.EXTEND
var _radar_spot := Vector3()
var _radar_target := Vector2()
var _radar_height := 0.0
var _radar_radius := 0.0
var _radar_velocity := Vector2()
var _radar_ticks := 0
var _radar_wait := 0

var _missiles: Array[FallMissile] = []
var _missile_queue := 0
var _missile_wait := 0
var _trails := MeshInstance3D.new()
var _trail_mesh := ImmediateMesh.new()
var _trail_material := StandardMaterial3D.new()
var _explosions: Array[Thing] = []

var _pickup_names: Array[String] = []
var _pickups: Array[Pickup] = []
var _pickup_wait := 0

# Palette effects (0x5209c8 and its target and rate).
var _brightness := 0.0
var _target := 1.0
var _rate := 0.5
var _dying := false
var _red := 0.0

# The ground and the minecrawler.
var _haze: Array[ImageTexture] = []
var _haze_frame := 0
var _crawler: Array[Texture2D] = []
var _crawler_frame := 0.0

# The HUD (0x420830, 0x46cce4).
var _health_box := HealthBox.new()
var _icons: Array[Texture2D] = []
var _icon_hotspots: Array[Vector2i] = []
var _skull: Texture2D
var _space: Texture2D
var _moon: Texture2D
var _earth: Texture2D
var _blink := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	index = clampi(GameState.index_of(GameState.level), 0, 4)
	difficulty = Settings.difficulty
	inventory.difficulty = difficulty
	var args := Args.get_all()
	_god = args.has("god")
	_load()
	_build_nodes()
	_set_difficulty()
	if args.has("screenshot"):
		await get_tree().create_timer(float(args.get("wait", "3"))).timeout
		Args.screenshot_and_quit(get_tree(), args.screenshot, 2)


## Loads the fall's files (0x410018).
func _load() -> void:
	var n := index + 1
	_bni = MDKBni.load_file(MDKData.path("FALL3D/FALL3D.BNI"))
	_mti = MDKTextureArchive.load_file(MDKData.path("FALL3D/FALL3D_%d.MTI" % n))
	_sni = MDKSni.load_file(MDKData.path("FALL3D/FALL3D.SNI"))
	_fti = MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))
	_palette = _load_palette("FALLP%d" % n)
	_space_palette = _load_palette("SPACEPAL")
	var archives: Array[MDKTextureArchive] = [_mti]
	_resolver = MDKMeshBuilder.MaterialResolver.new(_palette, archives)
	_resolver.double_sided = true
	for animation_name in ["KURTANIM", "KURT_HIT", "BONESANM"]:
		_animations[animation_name] = MDKModelAnimation.parse(animation_name, _bni.bytes, _bni.entries[animation_name][0])
	# The pickups (`FALLPU_n`): 12-byte names, ended by an empty one.
	var entry: Array = _bni.entries.get("FALLPU_%d" % n, [])
	if not entry.is_empty():
		var offset: int = entry[0]
		while offset + 12 <= entry[0] + entry[1] and _bni.bytes[offset] != 0:
			_pickup_names.push_back(_bni.bytes.slice(offset, offset + 12).get_string_from_ascii())
			offset += 12
	_messages.setup(_fti, _palette)
	_health_box.setup(_bni, _palette)
	var pickups := _bni.get_animation("PICKUPS")
	for i in pickups.frame_count:
		_icons.push_back(HUD._make_texture(pickups.get_frame(i), _palette))
		_icon_hotspots.push_back(pickups.get_hotspot(i))
	_skull = HUD._make_texture(_bni.get_image("SKULL"), _palette)
	_space = HUD._make_texture(_bni.get_image("SPACE"), _space_palette)
	_moon = HUD._make_texture(_bni.get_image("MOON"), _space_palette)
	_earth = HUD._make_texture(_bni.get_image("EARTH"), _space_palette)
	for i in 8:
		var frame: MDKTexture = _mti.textures.get("L%d_C%04d" % [n, i + 1])
		if frame:
			_crawler.push_back(HUD._make_texture(frame, _palette))
	for i in 16:
		_haze.push_back(_load_haze("ZOOM%04d" % i))
	for i in 8:
		var player := AudioStreamPlayer.new()
		player.bus = &"Effects"
		add_child(player)
		_players.push_back(player)
	for player: AudioStreamPlayer in [_wind_player, _grind_player]:
		player.bus = &"Effects"
		add_child(player)
	_wind_player.stream = _sound("WINDLOOP", true)
	_grind_player.stream = _sound("C_GRIND", true)


func _load_palette(entry_name: String) -> MDKPalette:
	var entry: Array = _bni.entries[entry_name]
	# `from_rgb` forces colour 0 to black, like the game.
	return MDKPalette.from_rgb(_bni.bytes.slice(entry[0], entry[0] + 768))


## A haze frame: `u32 size`, then per pair of screen rows `u32 nL, u8 left[4 nL], u32 nM, u32 nR,
## u8 right[4 nR]` (see docs/formats.md, "Fall files"), as a 600×180 image of the table offsets.
func _load_haze(entry_name: String) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(600 * 180)
	var r := BinReader.new(_bni.bytes, _bni.entries[entry_name][0] + 4)
	for row in 180:
		var left := r.u32()
		for i in left * 4:
			data[row * 600 + i] = r.u8()
		var middle := r.u32()
		var right := r.u32()
		var x := (left + middle) * 4
		for i in right * 4:
			data[row * 600 + x + i] = r.u8()
	return ImageTexture.create_from_image(Image.create_from_data(600, 180, false, Image.FORMAT_R8, data))


func _sound(sound_name: String, loop := false) -> AudioStreamWAV:
	var key := sound_name + ("|loop" if loop else "")
	if not _sounds.has(key):
		var entry: Array = _sni.entries.get(sound_name, [])
		_sounds[key] = MDKSound.load_wav(_sni.bytes.slice(entry[0], entry[0] + entry[1]), loop) if not entry.is_empty() else null
	return _sounds[key]


func _play(sound_name: String) -> void:
	var stream := _sound(sound_name)
	if not stream:
		return
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.play()
			return


func _build_nodes() -> void:
	var ground_texture: MDKTexture = _mti.textures["LEVEL%d" % (index + 1)]
	var track_texture: MDKTexture = _mti.textures["POD%d" % (index + 1)]
	_ground_material.shader = preload("res://game/fall/fall_ground.gdshader")
	_ground_material.set_shader_parameter(&"ground", ground_texture.get_index_texture())
	_ground_material.set_shader_parameter(&"track", track_texture.get_index_texture())
	_ground_material.set_shader_parameter(&"palette", _palette.get_texture())
	var blend := PackedFloat32Array()
	for value: int in HAZE_BLEND:
		blend.push_back(value / 256.0)
	_ground_material.set_shader_parameter(&"blend", blend)
	_ground.material = _ground_material
	_ground.color = Color.BLACK
	_screen_material.shader = preload("res://game/fall/fall_screen.gdshader")
	_screen.material = _screen_material
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in [_ground, _back, _view_rect, _hud, _screen]:
		control.set_anchors_preset(Control.PRESET_FULL_RECT)
		control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(control)
	_ground.visible = false
	_back.draw.connect(_draw_back)
	_hud.draw.connect(_draw_hud)

	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_view_rect.texture = _view.get_texture()
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# The viewport's colours are already multiplied by their alpha (the radar and the trails).
	var premultiplied := CanvasItemMaterial.new()
	premultiplied.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_view_rect.material = premultiplied
	_view.add_child(_world)
	# Moved every frame, not in physics ticks.
	_world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = rad_to_deg(2.0 * atan(VIEW_HEIGHT * 0.5 / FOCAL))
	_camera.near = 0.5
	_camera.far = 8000.0
	# Looking straight down: world +x is right and +y (MDK) up on the screen.
	_camera.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	_world.add_child(_camera)

	_kurt = Thing.new()
	_kurt.node = _make_node("KURT")
	_kurt.node.basis = Basis(Vector3.UP, deg_to_rad(KURT_YAW)) * Basis(Vector3.BACK, deg_to_rad(KURT_PITCH))
	_kurt.node.visible = false
	for alpha: int in RADAR_ALPHA:
		var material := MDKMeshBuilder.make_color_material(Color(0, 1, 0, alpha / 256.0), true)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_radar_materials.push_back(material)
	_radar = MeshInstance3D.new()
	_radar.mesh = _radar_mesh
	_world.add_child(_radar)
	_trail_material = MDKMeshBuilder.make_color_material(Color(0.8, 0.8, 0.8, 0.35), true)
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trails.mesh = _trail_mesh
	_world.add_child(_trails)


func _set_difficulty() -> void:
	var i := index
	_beam_speed = STEER_MAX * (1.0 + [0.1, 0.2, 1.0 / 3.0][difficulty] * i)
	_missiles_per_detection = 2 + i / [5, 3, 2][difficulty]
	_spread = [7.5, 6.5, 5.5][difficulty] - i
	_missile_gap = 32 - [1, 3, 5][difficulty] * i
	_radar_gap = 63 - [3, 7, 9][difficulty] * i
	_wind_player.volume_db = linear_to_db(0.0001)
	_wind_player.play()


func _get_model(model_name: String) -> MDKModel:
	if not _models.has(model_name):
		var entry: Array = _bni.entries.get(model_name, [])
		_models[model_name] = MDKModel.parse(model_name, _bni.bytes, entry[0], false, model_name in NAMED_PARTS) if not entry.is_empty() else null
	return _models[model_name]


## The mesh of a model in a frame of an animation (or at rest).
func _get_mesh(model_name: String, animation_name := "", frame := 0) -> Mesh:
	var key := "%s|%s|%d" % [model_name, animation_name, frame]
	if not _meshes.has(key):
		var model := _get_model(model_name)
		if not model:
			return null
		var pose: Array = model.get_rest_pose()
		if animation_name != "":
			if not _baked.has(animation_name):
				_baked[animation_name] = (_animations[animation_name] as MDKModelAnimation).bake(model)
			pose = _baked[animation_name][frame]
		_meshes[key] = MDKMeshBuilder.build_model_mesh(model, pose, _resolver)
	return _meshes[key]


func _make_node(model_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _get_mesh(model_name)
	_world.add_child(node)
	return node


## Draws a node over everything, as the original sorts explosions at camera z + 5 (0x411aa4).
func _draw_on_top(node: MeshInstance3D) -> void:
	for i in node.mesh.get_surface_count():
		var material := node.mesh.surface_get_material(i).duplicate() as Material
		if material is ShaderMaterial:
			(material as ShaderMaterial).shader = ON_TOP_SHADER
		else:
			var standard := material as StandardMaterial3D
			standard.no_depth_test = true
			standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.render_priority = Material.RENDER_PRIORITY_MAX
		node.set_surface_override_material(i, material)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _ended and not _dying:
		_finish()


func _process(delta: float) -> void:
	if _ended:
		return
	var dt := minf(delta, 0.1)
	_tick_fraction += dt * 30.0
	var ticks := int(_tick_fraction)
	_tick_fraction -= ticks
	var window_view := Vector2(size.x / size.y * VIEW_HEIGHT, VIEW_HEIGHT)
	if Vector2i(size) != _view.size:
		_view.size = Vector2i(size)
	if _intro_left > 0:
		_update_intro(dt, ticks)
	else:
		_update_fall(dt, ticks)
	_ground_material.set_shader_parameter(&"view_size", window_view)
	_back.queue_redraw()
	_hud.queue_redraw()


# --- The intro in space (0x41106c) ---

func _update_intro(dt: float, ticks: int) -> void:
	_intro_left -= ticks
	var left := maxi(_intro_left, 0)
	# Fade in from black, then plain, then fade to white.
	if left > 90:
		_set_screen(1.0, 1.0 - (left - 90) / 60.0)
	elif left < 60:
		_set_screen(1.0 - (60 - left) / 60.0, 1.0)
	else:
		_set_screen(1.0, 1.0)
	if left < 120:
		_wind = WIND_FULL if left < 61 else ((120 - left) * 12 / 60) << 8
		_haze_frame = (_haze_frame + ticks) % 16
	_update_wind_sound()
	_camera_position = Vector3.ZERO
	_camera.position = Vector3.ZERO
	if left < 90:
		_kurt.node.visible = true
		_animate_kurt(ticks)
		var f := 1.0 - (1.0 - minf((90 - left) / 60.0, 1.0)) ** 2
		_kurt.position = Vector3(30.0 * f - 30.0, 10.0 * f - 10.0, -10.0 * f)
		_kurt.node.position = MDKMeshBuilder.to_godot(_kurt.position)
	if _intro_left <= 0:
		_start_fall()


func _start_fall() -> void:
	_intro_left = 0
	_time = 0.0
	_ground.visible = true
	_radar_wait = (randi() & 15) + 7
	if not _pickup_names.is_empty():
		_pickup_wait = (randi() & 31) + 31
	_wind = WIND_FULL
	_kurt.position = Vector3(0, 0, KURT_START_Z)
	if index > 3:
		_bones = Thing.new()
		_bones.node = _make_node("BONES")
		_bones.node.basis = _kurt.node.basis
		_bones.position = Vector3(0, 0, KURT_START_Z + 20.0)
	if index == 0:
		_messages.push("FALL_T1", HUDMessages.FLAG_ZOOM, 3.0)
	_grind_player.play()


# --- The fall (0x4114a4) ---

func _update_fall(dt: float, ticks: int) -> void:
	_time += dt
	_update_kurt(dt, ticks)
	_update_camera(dt)
	_update_radar(dt, ticks)
	_update_missiles(dt, ticks)
	_update_explosions(ticks)
	_update_pickups(dt, ticks)
	_update_bones(dt, ticks)
	_update_palette(dt, ticks)
	_update_wind_sound()
	_grind_player.volume_db = linear_to_db((minf(_time / 30.0, 1.0) + 2.0) / 3.0)
	_messages.update(dt)
	_haze_frame = (_haze_frame + ticks) % 16
	_crawler_frame = fmod(_crawler_frame + ticks * 0.5, 8.0)
	_update_hud(ticks)

	# The ground (0x41357c).
	var centre_row := 824.0 - 624.0 * _time / 33.0
	_ground_material.set_shader_parameter(&"camera", _camera_position)
	_ground_material.set_shader_parameter(&"centre_row", centre_row)
	_ground_material.set_shader_parameter(&"track_row", roundi(centre_row - 108.0 * 80.0 / 256.0))
	_ground_material.set_shader_parameter(&"wind", _wind >> 8)
	_ground_material.set_shader_parameter(&"haze", _haze[_haze_frame])

	if _dying:
		return
	if _time > END_TIME:
		_finish()


func _update_kurt(dt: float, ticks: int) -> void:
	_animate_kurt(ticks)
	_kurt.position.z -= KURT_SPEED * dt
	var velocity := Vector2(_kurt.velocity.x, _kurt.velocity.y)
	if _time <= STEER_TIME and not _dying:
		var right := Input.get_action_strength(&"turn_right") + Input.get_action_strength(&"strafe_right") \
				- Input.get_action_strength(&"turn_left") - Input.get_action_strength(&"strafe_left")
		var up := Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back")
		velocity.x = _steer(velocity.x, signf(right), dt)
		velocity.y = _steer(velocity.y, signf(up), dt)
	elif _time > STEER_TIME:
		if not _kurt_finished:
			_kurt_finished = true
			_play("K_FINISH")
		# Pulled back to the centre.
		for i in ticks:
			velocity = (velocity - 2.0 * Vector2(_kurt.position.x, _kurt.position.y)) * 0.5
	var p := Vector2(_kurt.position.x, _kurt.position.y) + velocity * dt
	for axis in 2:
		if absf(p[axis]) > LIMIT[axis]:
			p[axis] = signf(p[axis]) * LIMIT[axis]
			velocity[axis] = 0.0
	_kurt.position = Vector3(p.x, p.y, _kurt.position.z)
	_kurt.velocity = Vector3(velocity.x, velocity.y, -KURT_SPEED)
	_kurt.node.position = MDKMeshBuilder.to_godot(_kurt.position)


## One axis of Kurt's steering (`vel_accel_dt` 0x409270 with a key, 0x4687a4 without).
func _steer(speed: float, direction: float, dt: float) -> float:
	var step := STEER_STEP * 30.0 * dt
	if direction == 0.0:
		return move_toward(speed, 0.0, step)
	if speed * direction < 0.0:
		return direction * STEER_STEP
	return clampf(speed + direction * step, -STEER_MAX, STEER_MAX)


## `KURTANIM` loops; a hit plays `KURT_HIT` once (looping `KURTANIM` forever once he's dead).
func _animate_kurt(ticks: int) -> void:
	var animation: MDKModelAnimation = _animations[_kurt_animation]
	_kurt_frame += ticks * animation.speed
	if _kurt_frame >= animation.frame_count:
		if _kurt_animation == "KURT_HIT" and not _dying:
			_kurt_animation = "KURTANIM"
			_kurt_frame = 0.0
			animation = _animations[_kurt_animation]
		else:
			_kurt_frame = fmod(_kurt_frame, animation.frame_count)
	_kurt.node.mesh = _get_mesh("KURT", _kurt_animation, int(_kurt_frame))


## The camera (0x413440): above Kurt until 30 s, then it brakes to a stop in 2 s.
func _update_camera(dt: float) -> void:
	var z := _kurt.position.z + 10.0
	if _time > STEER_TIME:
		_camera_speed = minf(_camera_speed + KURT_SPEED * 0.5 * dt, 0.0)
		z = _camera_position.z + _camera_speed * dt
		_wind = int(-_camera_speed * 0.015 * 3072.0)
	_camera_position = Vector3(0.85 * _kurt.position.x, 0.85 * _kurt.position.y, z)
	_camera.position = MDKMeshBuilder.to_godot(_camera_position)


func _update_wind_sound() -> void:
	var volume := _wind / float(WIND_FULL) * 0.625
	_wind_player.volume_db = linear_to_db(maxf(volume, 0.0001))


# --- Radars (0x4130ac, 0x412af8) ---

func _update_radar(dt: float, ticks: int) -> void:
	if not _radar_active:
		if _time > STEER_TIME:
			_radar_mesh.clear_surfaces()
			return
		_radar_wait -= ticks
		if _radar_wait <= 0:
			_radar_active = true
			_radar_state = RadarState.EXTEND
			_radar_target = _random_point()
			_radar_height = _kurt.position.z - 3.0
			_radar_spot = Vector3.ZERO
			_radar_velocity = Vector2.ZERO
			_play("R_START")
		else:
			_radar_mesh.clear_surfaces()
			return
	match _radar_state:
		RadarState.EXTEND:
			_radar_height = _kurt.position.z - 3.0
			var z := minf(_radar_spot.z + RADAR_EXTEND_SPEED * dt, _radar_height)
			var f := z / _radar_height
			_radar_spot = Vector3(_radar_target.x * f, _radar_target.y * f, z)
			_radar_radius = RADAR_RADIUS * f
			if z >= _radar_height:
				_radar_state = RadarState.TRACK
				_radar_target = _random_point()
				_radar_ticks = 0
		RadarState.TRACK:
			_radar_height = _kurt.position.z - 3.0
			_radar_radius = RADAR_RADIUS
			var spot := Vector2(_radar_spot.x, _radar_spot.y)
			for i in ticks:
				_radar_velocity = 0.75 * _radar_velocity + 0.25 * _beam_speed * (_radar_target - spot).normalized()
			spot += _radar_velocity * dt
			_radar_spot = Vector3(spot.x, spot.y, _radar_height)
			_radar_ticks += ticks
			var near := (_radar_target - spot).abs()
			if _radar_ticks >= 30 or (near.x < 2.94 and near.y < 2.94):
				_play("R_MOVE")
				_radar_target = _choose_target()
				_radar_ticks = 0
			var kurt := Vector2(_kurt.position.x, _kurt.position.y)
			if kurt.distance_to(spot) < RADAR_SEE and not _dying:
				_detected()
		RadarState.RETRACT:
			var z := _radar_spot.z - RADAR_RETRACT_SPEED * dt
			if z <= 0.0:
				_radar_active = false
				_radar_wait = _radar_gap + (randi() & 63)
				_radar_mesh.clear_surfaces()
				return
			_radar_radius = RADAR_RADIUS * z / _radar_height
			_radar_spot.z = z
	_build_radar()


## Kurt was seen (`K_SEEN`): the radar retracts, missiles are queued and the screen flashes.
func _detected() -> void:
	_play("K_SEEN")
	_radar_state = RadarState.RETRACT
	_missile_queue += _missiles_per_detection + (randi() & 1)
	_missile_wait = mini(_missile_wait, 1)
	_rate = 3.0
	_target = maxf(_target - 0.5, 0.75)


func _random_point() -> Vector2:
	return Vector2(randf_range(-LIMIT.x, LIMIT.x), randf_range(-LIMIT.y, LIMIT.y))


## The next point the radar goes to (0x412a38): Kurt, a falling pickup or a random point.
func _choose_target() -> Vector2:
	var choices: Array[Vector2] = [Vector2(_kurt.position.x, _kurt.position.y)]
	for pickup in _pickups:
		if choices.size() < 9:
			choices.push_back(Vector2(pickup.position.x, pickup.position.y))
	for i in 3:
		choices.push_back(_random_point())
	return choices[randi() % choices.size()]


## The radar's beam (0x412f94): a fan from its base to ring 1, rings 1–4 at `1 − 2^−k` of the way
## to the spot with radius `r (1 − 2^−k)`, and a cap on ring 4.
func _build_radar() -> void:
	var base := Vector3(-4.0 * _camera_position.x, -4.0 * _camera_position.y, 0.0)
	var rings: Array[PackedVector3Array] = []
	for k in range(1, 5):
		var f := 1.0 - pow(2.0, -k)
		var centre := base.lerp(_radar_spot, f)
		var ring := PackedVector3Array()
		for m in 6:
			var angle := deg_to_rad(60.0 + 60.0 * m)
			ring.push_back(MDKMeshBuilder.to_godot(centre + Vector3(cos(angle), sin(angle), 0.0) * _radar_radius * f))
		rings.push_back(ring)
	_radar_mesh.clear_surfaces()
	_radar_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _radar_materials[0])
	var apex := MDKMeshBuilder.to_godot(base)
	for m in 6:
		_radar_mesh.surface_add_vertex(apex)
		_radar_mesh.surface_add_vertex(rings[0][m])
		_radar_mesh.surface_add_vertex(rings[0][(m + 1) % 6])
	_radar_mesh.surface_end()
	for k in 3:
		_radar_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _radar_materials[k + 1])
		for m in 6:
			var a := rings[k][m]
			var b := rings[k][(m + 1) % 6]
			var c := rings[k + 1][m]
			var d := rings[k + 1][(m + 1) % 6]
			for v: Vector3 in [a, b, c, b, d, c]:
				_radar_mesh.surface_add_vertex(v)
		_radar_mesh.surface_end()
	_radar_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _radar_materials[4])
	for m in [1, 2, 3, 4]:
		_radar_mesh.surface_add_vertex(rings[3][0])
		_radar_mesh.surface_add_vertex(rings[3][m])
		_radar_mesh.surface_add_vertex(rings[3][m + 1])
	_radar_mesh.surface_end()


# --- Missiles (0x412568, 0x411ee8) ---

func _update_missiles(dt: float, ticks: int) -> void:
	if _missile_queue > 0:
		_missile_wait -= ticks
		if _missile_wait <= 0:
			_missile_queue -= 1
			_missile_wait = _missile_gap + (randi() & 31)
			_launch_missile()
	for missile: FallMissile in _missiles.duplicate():
		var previous := missile.position
		var event := missile.update(dt, ticks, _kurt.position)
		_orient(missile.node, missile.velocity)
		missile.node.position = MDKMeshBuilder.to_godot(missile.position)
		if event == FallMissile.Event.PASSED:
			_play("M_PASS")
		if event == FallMissile.Event.GONE:
			_remove_missile(missile)
			continue
		if _time <= STEER_TIME and not _dying and _crosses_kurt(previous, missile.position):
			_hit(missile)
	_build_trails()


func _launch_missile() -> void:
	_play("M_LNCH")
	_rate = 3.0
	_target = maxf(_target - 0.2, 0.5)
	var missile := FallMissile.new(_spread)
	missile.node = _make_node("MISSILE")
	_missiles.push_back(missile)


func _remove_missile(missile: FallMissile) -> void:
	missile.node.queue_free()
	_missiles.erase(missile)


## Points the model's +y along a direction, z up (0x4123e8).
func _orient(node: Node3D, direction: Vector3) -> void:
	var y := direction.normalized()
	var x := y.cross(Vector3(0, 0, 1)).normalized()
	if x.is_zero_approx():
		x = Vector3(1, 0, 0)
	var z := x.cross(y)
	node.basis = Basis(MDKMeshBuilder.to_godot(x), MDKMeshBuilder.to_godot(z), -MDKMeshBuilder.to_godot(y))


## Whether a move crosses Kurt's box (0x45ef80).
func _crosses_kurt(from: Vector3, to: Vector3) -> bool:
	var box := AABB(_kurt.position - KURT_BOX, KURT_BOX * 2.0)
	return box.has_point(to) or box.intersects_segment(from, to) != null


## A missile hits Kurt: an explosion, damage and a sound.
func _hit(missile: FallMissile) -> void:
	_play(["EXPLODE1", "EXPLODE2"][randi() & 1])
	_play(HIT_SOUNDS[randi() % HIT_SOUNDS.size()])
	var damage := 4
	if difficulty == 1:
		damage = 4 + (randi() & 7)
	elif difficulty == 2:
		damage = 2 * (4 + (randi() & 7))
	if not _god:
		health = maxi(health - damage, 0)
	_brightness = 3.0
	_kurt_animation = "KURT_HIT"
	_kurt_frame = 0.0
	var explosion := Thing.new()
	explosion.position = missile.position
	explosion.node = _make_node("EXPLODE")
	_draw_on_top(explosion.node)
	# A random yaw.
	explosion.velocity.x = randf() * TAU
	_explosions.push_back(explosion)
	_remove_missile(missile)
	if health <= 0:
		_dying = true
		_brightness = 3.0
		_kurt_animation = "KURTANIM"


func _update_explosions(ticks: int) -> void:
	for explosion: Thing in _explosions.duplicate():
		explosion.ticks += ticks
		if explosion.ticks >= EXPLOSION_TICKS:
			explosion.node.queue_free()
			_explosions.erase(explosion)
			continue
		# It follows Kurt down, grows and plays its texture's frames.
		explosion.position.z = _kurt.position.z
		explosion.node.position = MDKMeshBuilder.to_godot(explosion.position)
		var frame := int(explosion.ticks)
		explosion.node.basis = Basis(Vector3.UP, explosion.velocity.x).scaled(Vector3.ONE * maxf(2.0 * frame / EXPLOSION_TICKS, 0.01))
		explosion.node.set_instance_shader_parameter(&"frame_index", frame)


## The smoke trails (0x439454): a band along the last 32 points of each missile.
func _build_trails() -> void:
	_trail_mesh.clear_surfaces()
	var any := false
	for missile in _missiles:
		if missile.trail.size() < 2:
			continue
		if not any:
			_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_material)
			any = true
		var count := missile.trail.size()
		for i in count - 1:
			var a := missile.trail[i]
			var b := missile.trail[i + 1]
			var side := Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
			var wa := 0.5 + 1.5 * (count - i) / 32.0
			var wb := 0.5 + 1.5 * (count - i - 1) / 32.0
			var quad := [a - side * wa, a + side * wa, b + side * wb, b - side * wb]
			for k: int in [0, 1, 2, 0, 2, 3]:
				_trail_mesh.surface_add_vertex(MDKMeshBuilder.to_godot(quad[k]))
	if any:
		_trail_mesh.surface_end()


# --- Pickups (0x4128fc, 0x41275c) ---

func _update_pickups(dt: float, ticks: int) -> void:
	if not _pickup_names.is_empty() and _time <= STEER_TIME:
		_pickup_wait -= ticks
		if _pickup_wait <= 0:
			_pickup_wait = 31 + (randi() & 127)
			_spawn_pickup(_pickup_names.pop_back())
	for pickup: Pickup in _pickups.duplicate():
		var previous := pickup.position
		pickup.ticks += ticks
		if pickup.chute == null and pickup.ticks >= pickup.fall_ticks:
			_play("P_CHUTE")
			pickup.chute = _make_node("CHUTE")
		if pickup.chute:
			# Brakes to 50 u/s and spins at 30°/s.
			pickup.velocity.z = minf(pickup.velocity.z + KURT_SPEED * dt, -PICKUP_CHUTE_SPEED)
			pickup.yaw += 30.0 * dt
		pickup.position += pickup.velocity * dt
		var basis := Basis(Vector3.UP, deg_to_rad(pickup.yaw))
		pickup.node.basis = basis
		pickup.node.position = MDKMeshBuilder.to_godot(pickup.position)
		if pickup.chute:
			pickup.chute.basis = basis
			pickup.chute.position = MDKMeshBuilder.to_godot(pickup.position + Vector3(0, 0, 2))
		# Only under its chute (0x41275c): dropped above the camera, it would go at once.
		if not pickup.chute:
			continue
		if not _dying and _time <= STEER_TIME and _crosses_kurt(previous, pickup.position):
			_play("P_COLL")
			_play(["K_COLL1", "K_COLL2"][randi() & 1])
			inventory.collect(pickup.pickup_name, null)
			_remove_pickup(pickup)
		elif pickup.position.z > _camera_position.z:
			_remove_pickup(pickup)


func _spawn_pickup(pickup_name: String) -> void:
	_play("P_FALL")
	var pickup := Pickup.new()
	pickup.pickup_name = pickup_name
	pickup.position = Vector3(randf_range(-0.95, 0.95) * LIMIT.x, randf_range(-0.95, 0.95) * LIMIT.y, _kurt.position.z + 15.0)
	pickup.velocity = Vector3(0, 0, -PICKUP_FALL_SPEED)
	pickup.fall_ticks = 30 + (randi() & 63)
	pickup.node = _make_node(pickup_name)
	_pickups.push_back(pickup)


func _remove_pickup(pickup: Pickup) -> void:
	pickup.node.queue_free()
	if pickup.chute:
		pickup.chute.queue_free()
	_pickups.erase(pickup)


# --- Bones (0x4133b8) ---

func _update_bones(dt: float, ticks: int) -> void:
	if not _bones:
		return
	_bones.ticks += ticks
	var animation: MDKModelAnimation = _animations["BONESANM"]
	var frame := int(fmod(_bones.ticks * animation.speed, animation.frame_count))
	_bones.node.mesh = _get_mesh("BONES", "BONESANM", frame)
	_bones.position.z -= BONES_SPEED * dt
	_bones.node.position = MDKMeshBuilder.to_godot(_bones.position)
	if not _bones_passed and _bones.position.z < _kurt.position.z:
		_bones_passed = true
		_play("BONES")


# --- Palette effects (0x5209c8, 0x410cc0, 0x410c28) ---

func _update_palette(dt: float, ticks: int) -> void:
	if _dying:
		# Red with the skull growing, then black; at 0 it's game over.
		if _brightness >= 1.0:
			_red = minf(_red + ticks * 5.0 / 255.0, 1.0)
		_brightness -= dt
		_set_screen(1.0, clampf(_brightness, 0.0, 1.0))
		if _brightness <= 0.0:
			_game_over()
		return
	if _time < 1.0:
		_brightness = _time
	elif not is_equal_approx(_brightness, _target):
		_brightness = move_toward(_brightness, _target, _rate * dt)
	elif _target < 1.0:
		_target = 1.0
		_rate = 0.5
	else:
		for i in ticks:
			if randi() & 31 == 0:
				_target = 0.9
				_rate = 0.5
				break
	var dark := 1.0
	if _time > FADE_TIME:
		dark = maxf(1.0 - (_time - FADE_TIME) / 2.0, 0.0)
	_set_screen(clampf(_brightness, 0.0, 1.0), dark)


func _set_screen(whiten: float, dark: float) -> void:
	_screen_material.set_shader_parameter(&"whiten", whiten)
	_screen_material.set_shader_parameter(&"dark", dark)
	_screen_material.set_shader_parameter(&"red", _red)


# --- The end ---

## The level follows with Kurt's health and inventory (0x410b80, then 0x41ba68).
func _finish() -> void:
	_ended = true
	GameState.carry = {health = health, inventory = inventory}
	get_tree().change_scene_to_file("res://game/main.tscn")


func _game_over() -> void:
	_ended = true
	get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")


# --- Drawing ---

## Behind the models: the intro's space, moon and earth, or the minecrawler on the ground.
func _draw_back() -> void:
	var s := _back.size.y / VIEW_HEIGHT
	var width := _back.size.x / s
	var origin := Vector2((width - 600.0) * 0.5, 0.0)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	if _intro_left > 0:
		_back.draw_rect(Rect2(0, 0, width, VIEW_HEIGHT), Color.BLACK)
		var f := 1.0 - maxf(_intro_left, 0) / float(INTRO_TICKS)
		_back.draw_texture(_space, origin)
		_draw_scaled(_moon, origin + Vector2(300.0, 270.0 - 90.0 * f), Vector2.ONE * (64.0 + 256.0 * f) / 256.0)
		_draw_scaled(_earth, origin + Vector2(300.0, 488.0 - 224.0 * f), Vector2((300.0 + 128.0 * f) / 256.0, (100.0 + 42.0 * f) / 256.0))
		return
	if _crawler.is_empty():
		return
	var scale := _camera_position.z / 5280.0
	var centre := Vector2(width * 0.5 - 0.36 * _camera_position.x / scale, 180.0 + 0.36 * _camera_position.y / scale)
	_draw_scaled(_crawler[int(_crawler_frame) % _crawler.size()], centre, Vector2.ONE * 0.75 / scale)


func _draw_scaled(texture: Texture2D, centre: Vector2, scale: Vector2) -> void:
	var extent := texture.get_size() * scale
	_back.draw_texture_rect(texture, Rect2(centre - extent * 0.5, extent), false)


func _update_hud(ticks: int) -> void:
	_blink = (_blink + ticks) & 31


## Whether the inventory is drawn (tests read it too): always, as the fall draws it every frame
## (0x4119ec); there is no sniper mode to hide it.
func shows_inventory() -> bool:
	return true


## The HUD over the fall, as in the level: messages, the health panel and the inventory; the skull
## when Kurt dies.
func _draw_hud() -> void:
	if _intro_left > 0:
		return
	var s := _hud.size.y / VIEW_HEIGHT
	var width := _hud.size.x / s
	_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	if _dying:
		var extent := _skull.get_size() * minf(_red * 255.0 / 256.0, 1.0)
		_hud.draw_texture_rect(_skull, Rect2(Vector2(width * 0.5, 180.0) - extent * 0.5, extent), false)
	_messages.draw(_hud, width)
	_health_box.draw(_hud, width, health, _blink)
	if shows_inventory():
		for i in inventory.slots.size():
			var slot := inventory.slots[i]
			var frame: int = slot.item - 1
			if frame < 0 or frame >= _icons.size():
				continue
			var position := Vector2(32 + i * 48, 328)
			_hud.draw_texture(_icons[frame], position - Vector2(_icon_hotspots[frame]))
			var count := inventory.super_chain_gun if slot.item == KurtInventory.Item.SUPER_CHAIN_GUN else slot.count
			if count > 1:
				_health_box.draw_number(_hud, count, position - Vector2(0, 12))


## Player settings (`user://settings.cfg`): sound volumes, the music filter, the mouse, the window,
## the difficulty and the key bindings (one key or mouse button per action, replacing the defaults
## of the project's input map). Applied at start and whenever they change.
##
## Sounds go through two buses under `Master`: `Music` (the arena and menu music) and `Effects`
## (everything else; players created on `Master` are moved there). `Master` has a limiter so that
## many sounds at once don't clip. The music is 8-bit mono at 14–20 kHz, which hisses at full
## volume: the music filter (on by default) cuts it above 6 kHz.
extends Node

const PATH := "user://settings.cfg"
const MUSIC_FILTER_CUTOFF := 6000.0

## Volumes from 0 to 100.
var master_volume := 80
var music_volume := 50
var effects_volume := 70
var music_filter := true
## Mouse sensitivity multiplier (0.25–3) and inverted vertical look.
var mouse_sensitivity := 1.0
var invert_mouse := false
var fullscreen := false
## 0 easy, 1 normal, 2 hard.
var difficulty := 1
## The game's actions in the order the controls screen lists them, with their names.
const ACTIONS := {
	&"move_forward": "Forward", &"move_back": "Back", &"turn_left": "Turn left", &"turn_right": "Turn right",
	&"strafe_left": "Strafe left", &"strafe_right": "Strafe right", &"jump": "Jump", &"turbo": "Run",
	&"fire": "Fire", &"sniper_mode": "Sniper mode", &"zoom_in": "Zoom in", &"zoom_out": "Zoom out",
	&"item_use": "Use item", &"item_next": "Next item", &"item_prev": "Previous item",
}
## Rebound actions: action → the event (as saved: `{"key": physical keycode}` or `{"mouse": button}`).
var bindings := {}

var _music_bus := -1
var _effects_bus := -1


func _ready() -> void:
	_load()
	_create_buses()
	apply()
	apply_bindings()
	get_tree().node_added.connect(_on_node_added)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	master_volume = config.get_value("audio", "master", master_volume)
	music_volume = config.get_value("audio", "music", music_volume)
	effects_volume = config.get_value("audio", "effects", effects_volume)
	music_filter = config.get_value("audio", "music_filter", music_filter)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_mouse = config.get_value("controls", "invert_mouse", invert_mouse)
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	difficulty = config.get_value("game", "difficulty", difficulty)
	bindings = config.get_value("controls", "bindings", {})


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "music_filter", music_filter)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_mouse", invert_mouse)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("game", "difficulty", difficulty)
	config.set_value("controls", "bindings", bindings)
	config.save(PATH)


func _create_buses() -> void:
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)
	_music_bus = _add_bus(&"Music")
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = MUSIC_FILTER_CUTOFF
	AudioServer.add_bus_effect(_music_bus, filter)
	_effects_bus = _add_bus(&"Effects")


func _add_bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")
	return index


## Applies the settings (volumes, filter, window).
func apply() -> void:
	AudioServer.set_bus_volume_db(0, _volume_db(master_volume))
	AudioServer.set_bus_volume_db(_music_bus, _volume_db(music_volume))
	AudioServer.set_bus_volume_db(_effects_bus, _volume_db(effects_volume))
	AudioServer.set_bus_effect_enabled(_music_bus, 0, music_filter)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Binds an action to an event (a key or a mouse button), replacing its bindings.
func bind(action: StringName, event: InputEvent) -> void:
	if event is InputEventKey:
		bindings[action] = {"key": event.physical_keycode if event.physical_keycode else event.keycode}
	elif event is InputEventMouseButton:
		bindings[action] = {"mouse": event.button_index}
	apply_bindings()


## Back to the project's default bindings.
func reset_bindings() -> void:
	bindings = {}
	InputMap.load_from_project_settings()


func apply_bindings() -> void:
	for action: StringName in bindings:
		if not InputMap.has_action(action):
			continue
		var saved: Dictionary = bindings[action]
		var event: InputEvent
		if saved.has("key"):
			event = InputEventKey.new()
			event.physical_keycode = saved.key
		else:
			event = InputEventMouseButton.new()
			event.button_index = saved.mouse
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## A readable name of an action's first binding.
static func describe(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "-"
	var event := events[0]
	if event is InputEventKey:
		var keycode: Key = event.keycode if event.keycode else DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
		return OS.get_keycode_string(keycode)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel down"
		return "Mouse %d" % event.button_index
	return event.as_text()


## 0–100 to decibels (silent at 0).
static func _volume_db(volume: int) -> float:
	return linear_to_db(volume / 100.0) if volume > 0 else -80.0


## Sound players left on `Master` play effects.
func _on_node_added(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.bus == &"Master":
		node.bus = &"Effects"

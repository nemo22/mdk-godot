## Player settings (`user://settings.cfg`): sound volumes, the music filter, the mouse, the window
## and the difficulty. Applied at start and whenever they change.
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

var _music_bus := -1
var _effects_bus := -1


func _ready() -> void:
	_load()
	_create_buses()
	apply()
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


## 0–100 to decibels (silent at 0).
static func _volume_db(volume: int) -> float:
	return linear_to_db(volume / 100.0) if volume > 0 else -80.0


## Sound players left on `Master` play effects.
func _on_node_added(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.bus == &"Master":
		node.bus = &"Effects"

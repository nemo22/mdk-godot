## Plays the music of the arena Kurt is in (cross-fading between arenas; `NONE` is silence).
class_name LevelAudio
extends Node

const FADE_TIME := 1.5

@export var level: Level
@export var target: Node3D

var arena := ""
var _players: Array[AudioStreamPlayer] = []
var _current := 0


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		player.volume_db = -80.0
		add_child(player)
		_players.push_back(player)


func _process(delta: float) -> void:
	if not level.cmi or not target:
		return
	var current_arena := level.get_arena_at(target.global_position)
	# Corridors have no music of their own: the previous arena's music keeps playing.
	if not current_arena.is_empty() and current_arena != arena and not level.cmi.arena_music.get(current_arena, "").is_empty():
		arena = current_arena
		var music := level.get_arena_music(arena)
		if music != _players[_current].stream:
			_current = 1 - _current
			_players[_current].stream = music
			if music:
				music.loop_mode = AudioStreamWAV.LOOP_FORWARD
				music.loop_end = int(music.get_length() * music.mix_rate)
				_players[_current].play()
	for i in _players.size():
		var target_db := 0.0 if i == _current and _players[i].stream else -80.0
		_players[i].volume_db = move_toward(_players[i].volume_db, target_db, 80.0 * delta / FADE_TIME)
		if _players[i].volume_db <= -79.0 and i != _current:
			_players[i].stop()

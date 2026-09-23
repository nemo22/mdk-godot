## Global game state shared between scenes, and the saved games.
##
## The port keeps the original's light saves (see docs/gameplay.md, "Saving and loading"): a level,
## its kind (3 = at the level's entry point, 6 = before the level), the health and the deaths, in
## `user://saves/<NAME>.sav` (JSON). Dying writes `LASTGAME` and goes back to the main menu, whose
## "Continue" starts the level again; `LASTGAME` only lasts for the session.
extends Node

const SAVE_DIR := "user://saves"
const LAST_GAME := "LASTGAME"
const KIND_LEVEL_START := 3
const KIND_BEFORE_LEVEL := 6
## The order the levels are played in (`0x490030`): the level index (`0x574268`, 0–5) picks the
## `TRAVERSE/LEVELn` directory. Gunter's level, LEVEL5, is the last.
const ORDER := [7, 6, 3, 4, 8, 5]

## Level to play (the LEVELn number, 3–8; see `ORDER`).
var level := 7
## Deaths so far (`0x574407`).
var deaths := 0
## The one air strike of the last two levels was used (`0x57440b`).
var strike_used := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# The original deletes `LASTGAME.SAV` when it quits.
	DirAccess.remove_absolute(_path(LAST_GAME))


static func _path(save_name: String) -> String:
	return "%s/%s.sav" % [SAVE_DIR, save_name]


## Saves the current level (a light save).
func save_game(save_name: String, kind := KIND_LEVEL_START) -> bool:
	var file := FileAccess.open(_path(save_name), FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"type": kind, "level": level, "health": 100, "deaths": deaths,
			"strike_used": strike_used, "time": Time.get_datetime_string_from_system()}))
	return true


## Reads a saved game's header, or an empty dictionary when it's missing or invalid.
func read_game(save_name: String) -> Dictionary:
	if not FileAccess.file_exists(_path(save_name)):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(save_name)))
	if not data is Dictionary or not data.has("level") or int(data.level) < 3 or int(data.level) > 8:
		return {}
	return data


## Loads a saved game: the level starts again from its beginning. Returns false when it's invalid.
func load_game(save_name: String) -> bool:
	var data := read_game(save_name)
	if data.is_empty():
		return false
	level = int(data.level)
	deaths = int(data.get("deaths", 0))
	strike_used = bool(data.get("strike_used", false))
	return true


## The saved games, sorted by name.
func list_games() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(SAVE_DIR):
		if file.get_extension() == "sav":
			names.push_back(file.get_basename())
	names.sort()
	return names


## The index (0–5) of a LEVELn number in the order of play.
static func index_of(level_number: int) -> int:
	return ORDER.find(level_number)


func has_last_game() -> bool:
	return not read_game(LAST_GAME).is_empty()

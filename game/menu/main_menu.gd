## The main menu: original background, texts and music. The original font isn't decoded yet.
##
## Game command line options (`--level`, `--viewer`, `--screenshot`, …) skip the menu,
## unless `--menu` is given; `--options` and `--controls` open those screens.
extends Control


var fti: MDKFti
var level_index := 0

@onready var background: TextureRect = $Background
@onready var items: MenuItems = $Items
@onready var music: AudioStreamPlayer = $Music
@onready var click: AudioStreamPlayer = $Click


func _ready() -> void:
	var args := Args.get_all()
	if args.has("level") or args.has("viewer") or args.has("models") or (args.has("screenshot") and not args.has("menu")):
		get_tree().change_scene_to_file.call_deferred("res://game/main.tscn")
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fti = MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))
	var options := MDKBni.load_file(MDKData.path("MISC/OPTIONS.BNI"))

	# `MDKOPT`: a 768-byte palette, then a 600×360 image.
	var entry: Array = options.entries["MDKOPT"]
	var palette := MDKPalette.from_rgb(options.bytes.slice(entry[0], entry[0] + 768))
	var image := MDKTexture.parse("MDKOPT", options.bytes, entry[0] + 768)
	background.texture = ImageTexture.create_from_image(palette.make_image(image.width, image.height, image.indices))

	var song: Array = options.entries["MAINSONG"]
	music.bus = &"Music"
	music.stream = MDKSound.load_wav(options.bytes.slice(song[0], song[0] + song[1]), true)
	music.play()
	click.stream = MDKSound.load_wav(fti.get_bytes("SND_PUSH"))
	items.click = click

	level_index = maxi(GameState.index_of(GameState.level), 0)
	_show_main()
	if args.has("options"):
		_show_options()
	if args.has("controls"):
		items.show_controls(_show_options)

	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot)


func _show_main() -> void:
	items.clear()
	# "Continue" plays the level Kurt last died in (`LASTGAME`).
	if GameState.has_last_game():
		items.add_item(fti.get_text("OPT0", "Continue"), _load.bind(GameState.LAST_GAME))
	items.add_item(fti.get_text("OPT1", "New Game"), _on_new_game)
	items.add_item("", _on_level).name = "Level"
	items.add_item(fti.get_text("OPT2", "Saved Game"), _show_saves)
	items.add_item(fti.get_text("OPT3", "Options"), _show_options)
	items.add_item(fti.get_text("OPT4", "Quit"), get_tree().quit)
	_update_level_text()
	items.get_child(0).grab_focus()


## The saved games (`SVOPT1`, or `SVOPT3` when there are none), with their level.
func _show_saves() -> void:
	items.clear()
	var names := GameState.list_games()
	var title := items.add_item(fti.get_text("SVOPT1" if not names.is_empty() else "SVOPT3", "Saved games").split("
")[0], Callable())
	title.disabled = true
	for save_name in names:
		var data := GameState.read_game(save_name)
		var text := "%s  (%s)" % [save_name, "Level %d" % (GameState.index_of(int(data.level)) + 1) if not data.is_empty() else fti.get_text("SVBAD", "Invalid")]
		var button := items.add_item(text, _load.bind(save_name))
		button.disabled = data.is_empty()
	items.add_item("Back", _show_main)
	items.get_child(mini(1, items.get_child_count() - 1)).grab_focus()


func _load(save_name: String) -> void:
	if GameState.load_game(save_name):
		get_tree().change_scene_to_file("res://game/main.tscn")


func _show_options() -> void:
	items.show_options(_show_main)


func _update_level_text() -> void:
	items.get_node(^"Level").text = "Level: %d" % (level_index + 1)


func _on_new_game() -> void:
	GameState.level = GameState.ORDER[level_index]
	GameState.deaths = 0
	GameState.strike_used = false
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_level() -> void:
	level_index = (level_index + 1) % GameState.ORDER.size()
	_update_level_text()

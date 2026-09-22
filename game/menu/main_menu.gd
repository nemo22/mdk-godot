## The main menu: original background, texts and music. The original font isn't decoded yet.
##
## Game command line options (`--level`, `--viewer`, `--screenshot`, …) skip the menu,
## unless `--menu` is given; `--options` opens the options.
extends Control

const LEVELS := [3, 4, 5, 6, 7, 8]

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

	level_index = LEVELS.find(GameState.level)
	_show_main()
	if args.has("options"):
		_show_options()

	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot)


func _show_main() -> void:
	items.clear()
	items.add_item(fti.get_text("OPT1", "New Game"), _on_new_game)
	items.add_item("", _on_level).name = "Level"
	items.add_item(fti.get_text("OPT3", "Options"), _show_options)
	items.add_item(fti.get_text("OPT4", "Quit"), get_tree().quit)
	_update_level_text()
	items.get_child(0).grab_focus()


func _show_options() -> void:
	items.show_options(_show_main)


func _update_level_text() -> void:
	items.get_node(^"Level").text = "Level: %d" % (LEVELS[level_index] - 2)


func _on_new_game() -> void:
	GameState.level = LEVELS[level_index]
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_level() -> void:
	level_index = (level_index + 1) % LEVELS.size()
	_update_level_text()

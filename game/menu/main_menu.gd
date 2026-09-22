## The main menu: original background, texts and music. The original font isn't decoded yet.
##
## Game command line options (`--level`, `--viewer`, `--screenshot`, …) skip the menu,
## unless `--menu` is given.
extends Control

const LEVELS := [3, 4, 5, 6, 7, 8]
const TEXT_COLOR := Color(0.95, 0.8, 0.45)
const HOVER_COLOR := Color(1.0, 1.0, 0.8)

var fti: MDKFti
var level_index := 0

@onready var background: TextureRect = $Background
@onready var items: VBoxContainer = $Items
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
	music.stream = MDKSound.load_wav(options.bytes.slice(song[0], song[0] + song[1]), true)
	music.play()
	click.stream = MDKSound.load_wav(fti.get_bytes("SND_PUSH"))

	level_index = LEVELS.find(GameState.level)
	_add_item(fti.get_text("OPT1", "New Game"), _on_new_game)
	_add_item("", _on_level).name = "Level"
	_add_item(fti.get_text("OPT3", "Options"), Callable()).disabled = true
	_add_item(fti.get_text("OPT4", "Quit"), get_tree().quit)
	_update_level_text()
	items.get_child(0).grab_focus()

	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot)


func _add_item(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override(&"font_size", 22)
	button.add_theme_constant_override(&"outline_size", 6)
	button.add_theme_color_override(&"font_outline_color", Color.BLACK)
	button.add_theme_color_override(&"font_color", TEXT_COLOR)
	for state in [&"font_hover_color", &"font_focus_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(state, HOVER_COLOR)
	button.add_theme_color_override(&"font_disabled_color", Color(0.5, 0.45, 0.4))
	# The focused item is shown by its color only.
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	if callback.is_valid():
		button.pressed.connect(func() -> void:
			click.play()
			callback.call())
	button.focus_entered.connect(click.play)
	items.add_child(button)
	return button


func _update_level_text() -> void:
	items.get_node(^"Level").text = "Level: %d" % (LEVELS[level_index] - 2)


func _on_new_game() -> void:
	GameState.level = LEVELS[level_index]
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_level() -> void:
	level_index = (level_index + 1) % LEVELS.size()
	_update_level_text()

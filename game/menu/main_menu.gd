## The main menu: original background, texts and music. The original font isn't decoded yet.
##
## Game command line options (`--level`, `--viewer`, `--screenshot`, …) skip the menu,
## unless `--menu` is given; `--options` opens the options.
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
	music.bus = &"Music"
	music.stream = MDKSound.load_wav(options.bytes.slice(song[0], song[0] + song[1]), true)
	music.play()
	click.stream = MDKSound.load_wav(fti.get_bytes("SND_PUSH"))

	level_index = LEVELS.find(GameState.level)
	_show_main()
	if args.has("options"):
		_show_options()

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


func _clear_items() -> void:
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()


func _show_main() -> void:
	_clear_items()
	_add_item(fti.get_text("OPT1", "New Game"), _on_new_game)
	_add_item("", _on_level).name = "Level"
	_add_item(fti.get_text("OPT3", "Options"), _show_options)
	_add_item(fti.get_text("OPT4", "Quit"), get_tree().quit)
	_update_level_text()
	items.get_child(0).grab_focus()


## The options: each item changes its setting by a step on a click or the right arrow (back with a
## right click or the left arrow). Saved when leaving.
func _show_options() -> void:
	_clear_items()
	var volume := func(value: int, step: int) -> int: return wrapi(value + step * 10, 0, 110)
	var sensitivities := [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
	var on_off := func(value: bool) -> String: return "On" if value else "Off"
	_add_option(func() -> String: return "Master volume: %d" % Settings.master_volume,
			func(step: int) -> void: Settings.master_volume = volume.call(Settings.master_volume, step))
	_add_option(func() -> String: return "Music volume: %d" % Settings.music_volume,
			func(step: int) -> void: Settings.music_volume = volume.call(Settings.music_volume, step))
	_add_option(func() -> String: return "Effects volume: %d" % Settings.effects_volume,
			func(step: int) -> void: Settings.effects_volume = volume.call(Settings.effects_volume, step))
	_add_option(func() -> String: return "Music filter: %s" % on_off.call(Settings.music_filter),
			func(_step: int) -> void: Settings.music_filter = not Settings.music_filter)
	_add_option(func() -> String: return "Mouse sensitivity: %.2f" % Settings.mouse_sensitivity,
			func(step: int) -> void:
				var index := sensitivities.find(Settings.mouse_sensitivity)
				Settings.mouse_sensitivity = sensitivities[wrapi((index if index >= 0 else 3) + step, 0, sensitivities.size())])
	_add_option(func() -> String: return "Invert mouse: %s" % on_off.call(Settings.invert_mouse),
			func(_step: int) -> void: Settings.invert_mouse = not Settings.invert_mouse)
	_add_option(func() -> String: return "Fullscreen: %s" % on_off.call(Settings.fullscreen),
			func(_step: int) -> void: Settings.fullscreen = not Settings.fullscreen)
	_add_option(func() -> String: return "Difficulty: %s" % ["Easy", "Normal", "Hard"][Settings.difficulty],
			func(step: int) -> void: Settings.difficulty = wrapi(Settings.difficulty + step, 0, 3))
	_add_item("Back", func() -> void:
		Settings.save()
		_show_main())
	items.get_child(0).grab_focus()


func _add_option(text: Callable, change: Callable) -> void:
	var button := _add_item(text.call(), Callable())
	var apply := func(step: int) -> void:
		change.call(step)
		Settings.apply()
		button.text = text.call()
		click.play()
	button.pressed.connect(apply.bind(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			apply.call(-1)
		elif event.is_action_pressed(&"ui_right"):
			apply.call(1)
			button.accept_event()
		elif event.is_action_pressed(&"ui_left"):
			apply.call(-1)
			button.accept_event())


func _update_level_text() -> void:
	items.get_node(^"Level").text = "Level: %d" % (LEVELS[level_index] - 2)


func _on_new_game() -> void:
	GameState.level = LEVELS[level_index]
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_level() -> void:
	level_index = (level_index + 1) % LEVELS.size()
	_update_level_text()

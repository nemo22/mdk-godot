## A list of menu items in the style of the main menu (flat buttons, gold text with a black outline,
## a click on focus and press), and the options screen shared by the main menu and the pause menu.
class_name MenuItems
extends VBoxContainer

const TEXT_COLOR := Color(0.95, 0.8, 0.45)
const HOVER_COLOR := Color(1.0, 1.0, 0.8)
const SENSITIVITIES := [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]

var click: AudioStreamPlayer


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func add_item(text: String, callback: Callable) -> Button:
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
			_click()
			callback.call())
	button.focus_entered.connect(_click)
	add_child(button)
	return button


## An item that changes a setting by a step on a click or the right arrow (back with a right click
## or the left arrow); `text` gives its label.
func add_option(text: Callable, change: Callable) -> Button:
	var button := add_item(text.call(), Callable())
	var apply := func(step: int) -> void:
		change.call(step)
		Settings.apply()
		button.text = text.call()
		_click()
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
	return button


## The options (see `Settings`); saved when leaving with "Back".
func show_options(on_back: Callable) -> void:
	clear()
	add_option(func() -> String: return "Master volume: %d" % Settings.master_volume,
			func(step: int) -> void: Settings.master_volume = _volume_step(Settings.master_volume, step))
	add_option(func() -> String: return "Music volume: %d" % Settings.music_volume,
			func(step: int) -> void: Settings.music_volume = _volume_step(Settings.music_volume, step))
	add_option(func() -> String: return "Effects volume: %d" % Settings.effects_volume,
			func(step: int) -> void: Settings.effects_volume = _volume_step(Settings.effects_volume, step))
	add_option(func() -> String: return "Music filter: %s" % _on_off(Settings.music_filter),
			func(_step: int) -> void: Settings.music_filter = not Settings.music_filter)
	add_option(func() -> String: return "Mouse sensitivity: %.2f" % Settings.mouse_sensitivity,
			func(step: int) -> void: Settings.mouse_sensitivity = _sensitivity_step(Settings.mouse_sensitivity, step))
	add_option(func() -> String: return "Invert mouse: %s" % _on_off(Settings.invert_mouse),
			func(_step: int) -> void: Settings.invert_mouse = not Settings.invert_mouse)
	add_option(func() -> String: return "Fullscreen: %s" % _on_off(Settings.fullscreen),
			func(_step: int) -> void: Settings.fullscreen = not Settings.fullscreen)
	add_option(func() -> String: return "Difficulty: %s" % ["Easy", "Normal", "Hard"][Settings.difficulty],
			func(step: int) -> void: Settings.difficulty = wrapi(Settings.difficulty + step, 0, 3))
	add_item("Back", func() -> void:
		Settings.save()
		on_back.call())
	get_child(0).grab_focus()


func _click() -> void:
	if click:
		click.play()


static func _volume_step(value: int, step: int) -> int:
	return wrapi(value + step * 10, 0, 110)


static func _sensitivity_step(value: float, step: int) -> float:
	var index := SENSITIVITIES.find(value)
	return SENSITIVITIES[wrapi((index if index >= 0 else 3) + step, 0, SENSITIVITIES.size())]


static func _on_off(value: bool) -> String:
	return "On" if value else "Off"

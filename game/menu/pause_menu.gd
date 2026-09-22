## The pause menu (Esc during the game): resume, options, back to the main menu, quit. The game is
## paused while it's open.
class_name PauseMenu
extends CanvasLayer

var _items := MenuItems.new()
var _click := AudioStreamPlayer.new()


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_items.set_anchors_preset(Control.PRESET_CENTER)
	_items.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_items.grow_vertical = Control.GROW_DIRECTION_BOTH
	_items.alignment = BoxContainer.ALIGNMENT_CENTER
	_items.add_theme_constant_override(&"separation", 0)
	add_child(_items)
	var fti := MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))
	if fti:
		_click.stream = MDKSound.load_wav(fti.get_bytes("SND_PUSH"))
	_click.volume_db = -6.0
	add_child(_click)
	_items.click = _click


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if visible:
			_resume()
		else:
			_open()


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main()


func _show_main() -> void:
	_items.clear()
	_items.add_item("Resume", _resume)
	_items.add_item("Options", func() -> void: _items.show_options(_show_main))
	_items.add_item("Main menu", func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://game/menu/main_menu.tscn"))
	_items.add_item("Quit", get_tree().quit)
	_items.get_child(0).grab_focus()


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

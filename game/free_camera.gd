## A free-flying debug camera: WASD to move, Q/E down/up, mouse to look (click to capture), Shift to go faster.
extends Camera3D

const MOUSE_SENSITIVITY := 0.003

@export var speed := 60.0

var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	yaw = rotation.y
	pitch = rotation.x


func look_at_point(target: Vector3) -> void:
	var dir := (target - global_position).normalized()
	yaw = atan2(-dir.x, -dir.z)
	pitch = asin(clampf(dir.y, -1.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.screen_relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.screen_relative.y * MOUSE_SENSITIVITY, -PI / 2, PI / 2)
		rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	var input := Vector3(
			Input.get_axis(&"ui_left", &"ui_right") + float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
			Input.get_axis(&"ui_up", &"ui_down") + float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var velocity := basis * Vector3(input.x, 0.0, input.z) + Vector3.UP * input.y
	var multiplier := 5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	global_position += velocity * speed * multiplier * delta

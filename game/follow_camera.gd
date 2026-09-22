## Third person camera behind Kurt, following the original `camera_update`.
##
## The pitch (positive looks down) is the current arena's pitch (from the DTI), plus the look
## up/down offset, plus a tilt while airborne. Unlike the original, which pushes Kurt away from walls
## so the camera never gets closer, this camera moves closer when something is in the way.
class_name FollowCamera
extends Camera3D

const DISTANCE := 8.0
const HEIGHT := 4.5
const MOUSE_SENSITIVITY := 0.15
## Limits of the total pitch, in degrees.
const MIN_PITCH := -60.0
const MAX_PITCH := 90.0
const AIR_PITCH_RATE := 0.667 * 30.0
const AIR_PITCH_MAX := 40.0
const AIR_PITCH_DECAY := 40.0
## Kurt's head height, from which the camera's line of sight is checked.
const HEAD_HEIGHT := 5.5

@export var target: Kurt
@export var level: Level

var arena_pitch := 4.0
var look_offset := 0.0
var air_pitch := 0.0
var air_time := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_offset += event.screen_relative.y * MOUSE_SENSITIVITY


func _process(delta: float) -> void:
	var feet := target.get_global_transform_interpolated().origin
	# The arena pitch eases towards the pitch of the arena Kurt is in (0.85·old + 0.15·new per tick).
	arena_pitch = lerpf(level.get_camera_pitch(feet), arena_pitch, pow(0.85, delta * 30.0))
	if target.is_on_floor():
		air_time = 0.0
		air_pitch = move_toward(air_pitch, 0.0, AIR_PITCH_DECAY * delta)
	else:
		air_time += delta
		air_pitch = maxf(air_pitch, minf(air_time * AIR_PITCH_RATE, AIR_PITCH_MAX))
	look_offset = clampf(look_offset, MIN_PITCH - arena_pitch - air_pitch, MAX_PITCH - arena_pitch - air_pitch)
	var pitch := deg_to_rad(arena_pitch + look_offset + air_pitch)

	var facing := target.get_facing()
	var distance := DISTANCE
	var back := -distance * cos(pitch)
	if pitch > 0.0:
		back += 5.0 * (1.0 - cos(pitch))
	elif pitch < deg_to_rad(-20.0):
		distance = DISTANCE * (rad_to_deg(pitch) + 100.0) / 80.0
		back = -distance * cos(pitch)
	var position := feet + facing * back + Vector3.UP * (HEIGHT + distance * sin(pitch))

	# Keep walls from getting between Kurt and the camera.
	var head := feet + Vector3.UP * HEAD_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(head, position)
	query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		position = hit.position + (head - position).normalized() * 0.3

	var look := facing * cos(pitch) - Vector3.UP * sin(pitch)
	global_transform = Transform3D(Basis.looking_at(look, Vector3.UP), position)

## A scripted object (alien, door, pickup…) or an arena's script controller.
##
## State follows the original object structure (see `docs/scripts/notes_part1.md`): positions and
## angles are kept in MDK coordinates (Z up, degrees, yaw 0 = +X, 90 = +Y) and mirrored to the node.
class_name MDKObject
extends Node3D

const ANIMATION_FPS := 30.0
## Flags (`obj+0x148`…`obj+0x14b` as one integer) used by the engine.
const FLAG_GRAVITY := 0x2
const FLAG_COLLIDES := 0x4
const FLAG_LOOP := 0x8
const FLAG_NO_BANKING := 0x80
const FLAG_NO_TURNING := 0x10000
const FLAG_PATH_PUSHES := 0x8000000
const FLAG_BOUNCES := 0x20000000
const FLAG_PATH_ONCE := 0x400
## Contact flags (`obj+0x14c`), set by the movement code each frame.
const CONTACT_COLLIDED := 0x1
const CONTACT_FLOOR := 0x2
const CONTACT_TOUCHED_KURT := 0x4
const CONTACT_STUCK := 0x8
## `anim_end_frame` value meaning the animation has ended (`obj+0x118` = 0xFF00).
const ANIMATION_ENDED := -256

var type_name := ""
## Instance number (`obj+0x146`).
var instance_id := -1
## Arena the object belongs to (the arena name, e.g. `HMO_1`).
var arena := ""
var model: MDKModel

## MDK position and angles (degrees): yaw `obj+0x4c`, pitch `obj+0x13c`, roll `obj+0x54`.
var mdk_position := Vector3()
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
## Model scale (`obj+0x58`).
var model_scale := 1.0
var spawn_position := Vector3()
## Position at the end of the previous frame (`obj+0x180`).
var previous_position := Vector3()

var health := 100
var indestructible := false
var flags := 0
## Script flag word `obj+0x244`.
var script_flags := 0
## Contact flags (`obj+0x14c`).
var contact_flags := 0
## Script variables (`obj+0x234`).
var variables := [0.0, 0.0, 0.0, 0.0]
## Linked object (`obj+0x2b8`, variable kind "other").
var linked: MDKObject
## Leader / commanding object (`obj+0x138`).
var leader: MDKObject
var dead := false
## Mask of hidden model parts (`obj+0x2c8`).
var hidden_parts := 0

# Script state.
## Restart point (absolute file offset in the CMI, 0 = no script).
var restart := 0
var wait_time := 0.0
var wait_resume := 0
var death_script := 0
## Script target last set by a command (`obj+0x10c`).
var command_target := 0
var gosub_returns: Array[int] = []
var gosub_restarts: Array[int] = []
## Per gosub level frame counters (in ticks), used by timer conditions.
var level_timers := [0.0, 0.0, 0.0, 0.0, 0.0]
## Hit event of this frame (`obj+0x21e`): > 0 = hit on part index + 1, < 0 = other hits.
var hit_event := 0
## Command priority and obey level (`obj+0x11a`, `obj+0x11b`).
var priority := 0
var obey_level := 0

# Movement state.
## Movement command (`obj+0x11e`): 0 idle, 1 formation, 6 chase the target, 43/78 go to the
## destination, 61 projectile, 88 move forward, … and its parameter (`obj+0x11f`).
var move_command := 0
var move_parameter := 0
var move_destination := Vector3()
## Current waypoint (`obj+0x12c`, also the formation offset for command 1).
var waypoint := Vector3()
## Reference points `a` (own) and `b` (of the leader) of an attachment (`attach_to`).
var attach_points := Vector2i()
## Height offset added to targets (`obj+0x5c`).
var height_offset := 0.0
var speed := 0.0
var max_speed := 50.0
var acceleration := 10.0
var deceleration := 15.0
## Friction (`obj+0x44`) and gravity (`obj+0x48`), in units/s².
var friction := 64.0
var gravity := 32.0
var velocity := Vector3()
## Velocity added for this frame only (`obj+0x294`), set by walking and pushes.
var push := Vector3()
## Per kind parameter (`obj+0x302`): projectile lifetime, jump flight time… and its timer (`obj+0x306`).
var parameter := 0.0
var parameter_timer := 0.0

# Path state (`obj+0xe6`…`obj+0x100`).
var path := 0
var path_time := 0.0
var path_speed := 1.0
var path_stop := -1
var path_origin := Vector3()
var path_yaw_offset := 0.0

# Animation state.
var animation: MDKModelAnimation
var animation_time := 0.0
var animation_frame := 0
## Hold frame (`obj+0x118`): the animation stops there; `ANIMATION_ENDED` once a non looping
## animation has ended, -1 = none.
var animation_end_frame := ANIMATION_ENDED

var _mesh_instance: MeshInstance3D
var _resolver: MDKMeshBuilder.MaterialResolver
## Shared cache of built meshes: `"model|animation|frame|hidden parts"` to ArrayMesh.
static var _mesh_cache := {}
static var _baked := {}


func setup(p_type_name: String, p_model: MDKModel, resolver: MDKMeshBuilder.MaterialResolver) -> void:
	type_name = p_type_name
	name = p_type_name
	model = p_model
	_resolver = resolver
	if model:
		_mesh_instance = MeshInstance3D.new()
		add_child(_mesh_instance)
		_update_mesh()


func set_mdk_position(p_position: Vector3) -> void:
	mdk_position = p_position
	update_transform()


func set_yaw(degrees: float) -> void:
	yaw = fposmod(degrees, 360.0)
	update_transform()


func update_transform() -> void:
	position = MDKMeshBuilder.to_godot(mdk_position)
	# Model space is MDK space: yaw turns around Z (MDK) = Y (Godot), pitch raises the nose (+X
	# towards +Z) and roll turns around the forward axis.
	basis = Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.BACK, deg_to_rad(pitch)) \
			* Basis(Vector3.RIGHT, deg_to_rad(roll)) * Basis.from_scale(Vector3.ONE * model_scale)


## Starts an animation (`anim_loop` / `anim_once`). Restarting the current animation does nothing
## unless it has ended, as in the original.
func play_animation(p_animation: MDKModelAnimation, loop: bool) -> void:
	if loop:
		flags |= FLAG_LOOP
	else:
		flags &= ~FLAG_LOOP
	if p_animation == animation and animation_end_frame != ANIMATION_ENDED:
		if animation_end_frame >= 0:
			animation_end_frame = -1
		return
	animation = p_animation
	animation_time = 0.0
	animation_frame = 0
	animation_end_frame = -1 if animation else ANIMATION_ENDED
	_update_mesh()


func is_animation_done() -> bool:
	return animation == null or animation_end_frame == ANIMATION_ENDED


## Advances the animation (`object_anim_update`), moving the object by the animation's root motion.
func advance_animation(delta: float) -> void:
	if not animation or animation_end_frame == ANIMATION_ENDED:
		return
	if animation_end_frame >= 0 and animation_frame == animation_end_frame:
		return
	var frame_count := animation.frame_count
	animation_time += delta * ANIMATION_FPS * animation.speed
	if animation_end_frame >= 0 and animation_frame < animation_end_frame and roundi(animation_time) >= animation_end_frame:
		animation_time = animation_end_frame
	if animation_time >= frame_count - 1:
		if flags & FLAG_LOOP:
			if animation_time >= frame_count:
				animation_time -= frame_count
		else:
			animation_time = frame_count - 1
	var frame := roundi(animation_time) % frame_count
	if frame != animation_frame:
		# Root motion: the object moves by the animation's motion of each frame (model space).
		var step := frame - animation_frame if frame > animation_frame else frame + frame_count - animation_frame
		for i in step:
			var f := (animation_frame + 1 + i) % frame_count
			mdk_position += animation.root_motion[f].rotated(Vector3.BACK, deg_to_rad(yaw))
		animation_frame = frame
		_update_mesh()
	if animation_frame == frame_count - 1 and not flags & FLAG_LOOP and animation_frame != animation_end_frame:
		animation_end_frame = ANIMATION_ENDED


## Hides the model parts of a mask (`set_parts_mask`).
func set_hidden_parts(mask: int) -> void:
	if mask != hidden_parts:
		hidden_parts = mask
		_update_mesh()


func _update_mesh() -> void:
	if not _mesh_instance:
		return
	var key := "%s|%s|%d|%d" % [model.get_instance_id(), animation.get_instance_id() if animation else 0, animation_frame, hidden_parts]
	if not _mesh_cache.has(key):
		var pose: Array
		if animation:
			var bake_key := "%s|%s" % [model.get_instance_id(), animation.get_instance_id()]
			if not _baked.has(bake_key):
				_baked[bake_key] = animation.bake(model)
			pose = _baked[bake_key][animation_frame]
		else:
			pose = model.get_rest_pose()
		if hidden_parts:
			pose = pose.duplicate()
			for i in pose.size():
				if hidden_parts & (1 << i):
					pose[i] = PackedVector3Array()
		_mesh_cache[key] = MDKMeshBuilder.build_model_mesh(model, pose, _resolver)
	_mesh_instance.mesh = _mesh_cache[key]


## Index of the model part named `part_name`, or -1.
func find_part(part_name: String) -> int:
	if model:
		for i in model.parts.size():
			if model.parts[i].name.to_upper() == part_name.to_upper():
				return i
	return -1


## World position (MDK) of a model reference point (the attachment points `obj+0x1b0`).
func get_reference_point(index: int) -> Vector3:
	if not model or index >= model.reference_points.size():
		return mdk_position
	return mdk_position + (model.reference_points[index] * model_scale).rotated(Vector3.BACK, deg_to_rad(yaw))


## World position (MDK) of the centre of a model part (rest pose).
func get_part_center(part: int) -> Vector3:
	if part < 0 or not model:
		return mdk_position
	var center := model.parts[part].bounds.get_center() * model_scale
	return mdk_position + center.rotated(Vector3.BACK, deg_to_rad(yaw))


## Distance to a point, in MDK coordinates.
func distance_to(point: Vector3) -> float:
	return mdk_position.distance_to(point)


## Direction (degrees, MDK convention) from this object to a point.
func yaw_to(point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(point.y - mdk_position.y, point.x - mdk_position.x)), 360.0)

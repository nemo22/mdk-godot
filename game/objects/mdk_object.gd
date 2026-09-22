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
## Kurt goes through the object (with 0x800).
const FLAG_NOT_SOLID := 0x10
## The chain gun doesn't aim at the object.
const FLAG_NOT_TARGET := 0x20
const FLAG_NO_BANKING := 0x80
const FLAG_NOT_SOLID_2 := 0x800
## Some parts take damage separately (`set_weak_parts`).
const FLAG_WEAK_PARTS := 0x2000
const FLAG_NO_TURNING := 0x10000
## A pickup that has landed.
const FLAG_LANDED := 0x20000
## A pickup Kurt has taken (it vanishes).
const FLAG_COLLECTED := 0x40000
const FLAG_DOOR := 0x100000
const FLAG_PICKUP := 0x200000
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
## The health set last by `set_health` (`obj+0x2a2`), the maximum of the health bar.
var max_health := 0
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
## Parts blown off (`obj+0x2cc`, opcode 129): `clear_parts_mask` doesn't show them again.
var locked_parts := 0

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
## Hit event of this frame (`obj+0x21e`): > 0 = hit on part index + 1 (or a weak part destroyed),
## -1 chain gun, -2 other hits, -3 blasts.
var hit_event := 0
## What caused the last hit (`obj+0x21d`: -1 chain gun, -2 super chain gun, 1–4 Kurt's projectiles)
## and its direction (`obj+0x224`, degrees).
var hit_type := 0
var hit_direction := 0.0
## Weak parts (`set_weak_parts`): parts named `prefix` followed by a digit at `prefix_length` take
## damage separately; hit points per part index.
var weak_prefix := ""
var weak_prefix_length := 0
var part_health: Array[int] = []
var part_max_health: Array[int] = []
## Command priority and obey level (`obj+0x11a`, `obj+0x11b`).
var priority := 0
## Target mode (`obj+7`, opcode 251): 1 the aliens' target, 2 always targets Kurt.
var target_mode := 0
## Values of opcodes 210 and 199 (`obj+0x2c0`, `obj+0x104`), not identified.
var value_2c0 := 0.0
var value_104 := 0.0
var obey_level := 0

# Movement state.
## Movement command (`obj+0x11e`): 0 idle, 1 formation, 6 chase the target, 43/78 go to the
## destination, 61 projectile, 88 move forward, … and its parameter (`obj+0x11f`).
var move_command := 0
var move_parameter := 0
var move_destination := Vector3()
## Frames the movement code found the object stuck (`obj+0x2a0`; not computed yet).
var stuck_count := 0
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
## Frames per second of the animation (`obj+0xe0`, `anim_fps`).
var animation_fps := ANIMATION_FPS
## Sound played when the animation reaches a frame (`set_id_and_name`: `obj+0x140`, `obj+0x144`).
var frame_sound := ""
var frame_sound_frame := 0
## Effects (explosions) last this many ticks, showing texture frame `effect_time`, then vanish.
var effect_frames := 0
var effect_time := 0.0
## Kurt's thrown item (`obj+0x30a`: `KurtInventory.Item`), and its time left in ticks (`obj+0x30e`).
var thrown_kind := 0
var item_ticks := 0
## Blasts farther than this don't hurt the object (`obj+0x2c4`, opcode 177).
var blast_range := 1000.0
## Object carried along (a pickup's chute).
var attached: MDKObject

# Doors (`obj+0x306`…`obj+0x32a`, see `MDKObjectBehaviors`).
## CMI offsets of the opening and closing animations.
var door_animations := [0, 0]
var door_state := 0
## Kurt opens the door when he's closer than this.
var door_distance := 20.0
## Sounds when the door starts opening, starts closing, is open, is closed.
var door_sounds := ["", "", "", ""]
## Masks of the parts named `LOCK` and `HC…`.
var lock_parts := 0
var hatch_parts := 0

## Arena on the other side of a connector (a door between two arenas, `spawn_connector`).
var connects := ""
## Sound tracked by `if_own_sound` (played by `play_sound` with flag 4) and the looping sound
## (`set_loop_sound`).
var tracked_sound := ""
var loop_sound: AudioStreamPlayer3D
## Strings set by opcodes 25 and 26 (`obj+0x154`, `obj+0x150`; their use isn't known).
var labels := ["", ""]
## Hold frame (`obj+0x118`): the animation stops there; `ANIMATION_ENDED` once a non looping
## animation has ended, -1 = none.
var animation_end_frame := ANIMATION_ENDED

var _mesh_instance: MeshInstance3D
var _resolver: MDKMeshBuilder.MaterialResolver
## Body that Kurt collides with: a box per model part in the current pose.
var _body: AnimatableBody3D
var _body_shapes: Array[CollisionShape3D] = []
## Pose the body's boxes were last built for.
var _body_key := ""
## Shared cache of built meshes: `"model|animation|frame|hidden parts"` to ArrayMesh.
static var _mesh_cache := {}
static var _baked := {}
## Shared cache of part bounds: `"model|animation|frame"` to an Array of AABB.
static var _bounds_cache := {}


func setup(p_type_name: String, p_model: MDKModel, resolver: MDKMeshBuilder.MaterialResolver) -> void:
	type_name = p_type_name
	name = p_type_name
	model = p_model
	_resolver = resolver
	# The model can change later (the nuke).
	if model:
		if not _mesh_instance:
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


## Starts an animation from its first frame, even if it's already playing.
func restart_animation(p_animation: MDKModelAnimation, loop: bool) -> void:
	animation = null
	play_animation(p_animation, loop)


func is_animation_done() -> bool:
	return animation == null or animation_end_frame == ANIMATION_ENDED


## Advances the animation (`object_anim_update`), moving the object by the animation's root motion.
func advance_animation(delta: float) -> void:
	if not animation or animation_end_frame == ANIMATION_ENDED:
		return
	if animation_end_frame >= 0 and animation_frame == animation_end_frame:
		return
	var frame_count := animation.frame_count
	animation_time += delta * animation_fps * animation.speed
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


## Shows frame `index` of the object's animated textures (instead of animating them by time).
func set_texture_frame(index: int) -> void:
	if _mesh_instance:
		_mesh_instance.set_instance_shader_parameter(&"frame_index", index)


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


## Bounds of each model part in the current pose (model space).
func get_part_bounds() -> Array:
	var key := "%s|%s|%d" % [model.get_instance_id(), animation.get_instance_id() if animation else 0, animation_frame]
	if not _bounds_cache.has(key):
		var pose: Array
		if animation:
			var bake_key := "%s|%s" % [model.get_instance_id(), animation.get_instance_id()]
			if not _baked.has(bake_key):
				_baked[bake_key] = animation.bake(model)
			pose = _baked[bake_key][animation_frame]
		else:
			pose = model.get_rest_pose()
		var bounds := []
		for vertices: PackedVector3Array in pose:
			var aabb := AABB(vertices[0], Vector3.ZERO) if not vertices.is_empty() else AABB()
			for v in vertices:
				aabb = aabb.expand(v)
			bounds.push_back(aabb)
		_bounds_cache[key] = bounds
	return _bounds_cache[key]


## Bounds of the visible parts in the current pose (model space).
func get_pose_bounds() -> AABB:
	var bounds := get_part_bounds()
	var out := AABB()
	var first := true
	for i in bounds.size():
		var aabb: AABB = bounds[i]
		if hidden_parts & (1 << i) or aabb.size == Vector3.ZERO and aabb.position == Vector3.ZERO:
			continue
		out = aabb if first else out.merge(aabb)
		first = false
	return out if not first else model.bounds


## Updates the body Kurt collides with (`damp_collide_move` tests Kurt against the boxes of the
## visible parts of objects that are alive and don't have flag 0x10 or 0x800; doors skip their
## `LOCK` parts). Kurt can stand on the boxes and moving ones carry him.
func update_body() -> void:
	var solid := model != null and not dead and health != 0 and not flags & (FLAG_NOT_SOLID | FLAG_NOT_SOLID_2)
	if not solid:
		if _body and not _body_key.is_empty():
			for shape in _body_shapes:
				shape.disabled = true
			_body_key = ""
		return
	if not _body:
		_body = AnimatableBody3D.new()
		_body.sync_to_physics = false
		_body.collision_layer = 2
		_body.collision_mask = 0
		add_child(_body)
		for part in model.parts:
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			_body.add_child(shape)
			_body_shapes.push_back(shape)
	var skipped := hidden_parts | (lock_parts if flags & FLAG_DOOR else 0)
	var key := "%d|%d|%d" % [animation.get_instance_id() if animation else 0, animation_frame, skipped]
	if key == _body_key:
		return
	_body_key = key
	var bounds := get_part_bounds()
	for i in _body_shapes.size():
		var shape := _body_shapes[i]
		var aabb: AABB = bounds[i]
		shape.disabled = skipped & (1 << i) != 0 or aabb.size == Vector3.ZERO
		if not shape.disabled:
			(shape.shape as BoxShape3D).size = MDKMeshBuilder.to_godot(aabb.size).abs().max(Vector3.ONE * 0.1)
			shape.position = MDKMeshBuilder.to_godot(aabb.get_center())


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

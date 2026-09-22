## Moves scripted objects each frame like the original's object update (0x47868c): spline paths
## (0x43c258), movement commands (0x45b6c8), gravity (0x45e74c), then friction and velocity with
## arena collisions (0x45e810). See `docs/engine.md`.
class_name MDKObjectMotion
extends RefCounted

## Turn speed (degrees per second) when walking towards a waypoint or chasing.
const TURN_SPEED := 180.0
const TERMINAL_VELOCITY := -220.0
## Walkers slow down to half speed when the waypoint is more than this angle away.
const SLOW_TURN_ANGLE := 80.0
## Objects falling this far below their arena's floor are killed.
const FALL_OUT_DEPTH := 200.0

var runtime: MDKScriptRuntime
var dt := 1.0 / 30.0
var ticks := 1.0

var _bytes: PackedByteArray
var _box := BoxShape3D.new()
var _probe := RID()
var _motion_parameters := PhysicsTestMotionParameters3D.new()
var _motion_result := PhysicsTestMotionResult3D.new()


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime
	_bytes = runtime.level.cmi.bytes


func update(obj: MDKObject) -> void:
	if obj.path:
		_update_path(obj)
	_update_command(obj)
	if obj.dead:
		return
	if obj.flags & MDKObject.FLAG_GRAVITY:
		obj.velocity.z = maxf(obj.velocity.z - obj.gravity * dt, TERMINAL_VELOCITY)
	_apply_velocity(obj)
	if obj.dead:
		return
	obj.advance_animation(dt)
	obj.previous_position = obj.mdk_position
	obj.update_transform()


# Spline paths: `u32 key count`, then keys of 40 bytes: `s32 frame`, position, in tangent and out
# tangent (3 floats each). Segments are cubic Hermite curves.

func path_key_count(path: int) -> int:
	return _bytes.decode_u32(path)


func path_key_frame(path: int, key: int) -> int:
	return _bytes.decode_s32(path + 4 + key * 40)


func _path_vector(path: int, key: int, field: int) -> Vector3:
	var offset := path + 8 + key * 40 + field * 12
	return Vector3(_bytes.decode_float(offset), _bytes.decode_float(offset + 4), _bytes.decode_float(offset + 8))


## Position on a path at `time` (in frames), relative to the path's origin (`spline_eval` 0x43c0f8).
func path_position(path: int, time: float) -> Vector3:
	var key := path_key_count(path) - 2
	while key > 0 and path_key_frame(path, key) >= time:
		key -= 1
	key = maxi(key, 0)
	var start := path_key_frame(path, key)
	var length := path_key_frame(path, key + 1) - start
	var u := (time - start) / length if length != 0 else 0.0
	var p0 := _path_vector(path, key, 0)
	var p1 := _path_vector(path, key + 1, 0)
	var m0 := _path_vector(path, key, 2)
	var m1 := _path_vector(path, key + 1, 1)
	var d := p1 - p0
	var a := m0 + m1 - d * 2.0
	var b := d * 3.0 - m0 * 2.0 - m1
	return ((a * u + b) * u + m0) * u + p0


func _update_path(obj: MDKObject) -> void:
	var path := obj.path
	if obj.path_stop >= 0 and roundi(obj.path_time) == obj.path_stop:
		return
	var step := ticks * obj.path_speed
	var last := path_key_frame(path, path_key_count(path) - 1)
	var stop := float(obj.path_stop)
	var once := obj.flags & MDKObject.FLAG_PATH_ONCE != 0
	if step < 0.0:
		if obj.path_stop < 0 or obj.path_time < stop or stop < obj.path_time + step:
			obj.path_time += step
		else:
			obj.path_time = stop
		if obj.path_time < 0.0:
			if once:
				obj.path = 0
				obj.path_time = 0.0
			else:
				obj.path_time += last - 1
	else:
		if obj.path_stop < 0 or stop < obj.path_time or obj.path_time + step < stop:
			obj.path_time += step
		else:
			obj.path_time = stop
		if once:
			if obj.path_time >= last - 2:
				obj.path = 0
				obj.path_time = last - 2
		elif obj.path_time >= last - 1:
			obj.path_time -= last - 1
	var old := obj.mdk_position
	var p := path_position(path, obj.path_time) + obj.path_origin
	if obj.flags & MDKObject.FLAG_PATH_PUSHES:
		p.z = old.z
	if not obj.flags & MDKObject.FLAG_NO_TURNING:
		if absf(p.x - old.x) + absf(p.y - old.y) > dt * 0.5:
			obj.yaw = fposmod(rad_to_deg(atan2(p.y - old.y, p.x - old.x)) + obj.path_yaw_offset, 360.0)
	if obj.flags & MDKObject.FLAG_PATH_PUSHES:
		# The path drives the horizontal velocity instead of the position.
		obj.push.x += (p.x - old.x) / dt
		obj.push.y += (p.y - old.y) / dt
	else:
		obj.mdk_position = p


## Starts following a path (`follow_path`): `time` in frames, `origin` = the path's offset.
func start_path(obj: MDKObject, path: int, time: float, origin: Vector3) -> void:
	obj.path = path
	obj.path_time = time
	obj.path_origin = origin
	obj.path_stop = -1
	obj.mdk_position = path_position(path, time) + origin


# Movement commands.

func _update_command(obj: MDKObject) -> void:
	match obj.move_command:
		1:
			_follow_formation(obj)
		6:
			var target := runtime.target_position
			_chase(obj, Vector3(target.x, target.y, target.z + 8.0))
		43, 78, 197:
			if obj.flags & MDKObject.FLAG_GRAVITY:
				_walk(obj)
			else:
				_fly(obj)
		61:
			_fly_projectile(obj)
		74:
			_follow_attachment(obj)
		88:
			_move_forward(obj)
		229:
			obj.parameter_timer += dt
			if obj.parameter_timer >= obj.parameter * 0.5 and obj.contact_flags & MDKObject.CONTACT_FLOOR:
				obj.move_command = 0
				obj.velocity = Vector3.ZERO


## Turns the object towards a point by at most `TURN_SPEED` × dt. Returns the angle that was
## left to turn (before turning).
func turn_towards(obj: MDKObject, point: Vector3) -> float:
	var target_yaw := obj.yaw
	if point.x != obj.mdk_position.x or point.y != obj.mdk_position.y:
		target_yaw = obj.yaw_to(point)
	var diff := wrapf(target_yaw - obj.yaw, -180.0, 180.0)
	var max_step := TURN_SPEED * dt
	obj.yaw = fposmod(obj.yaw + clampf(diff, -max_step, max_step), 360.0)
	return diff


func _accelerate(obj: MDKObject, target_speed: float) -> void:
	if obj.speed > target_speed:
		obj.speed = maxf(obj.speed - obj.deceleration * dt, target_speed)
	elif obj.speed < target_speed:
		obj.speed = minf(obj.speed + obj.acceleration * dt, target_speed)


func _stop(obj: MDKObject) -> void:
	obj.move_command = 0
	obj.speed = 0.0
	obj.contact_flags &= ~MDKObject.CONTACT_STUCK


## Walks on the ground towards the waypoint, then the destination (0x45a7d4).
func _walk(obj: MDKObject) -> void:
	var final := obj.waypoint == obj.move_destination
	if absf(obj.waypoint.x - obj.mdk_position.x) + absf(obj.waypoint.y - obj.mdk_position.y) < 5.0:
		if final:
			_stop(obj)
			return
		obj.waypoint = obj.move_destination
	var diff := turn_towards(obj, obj.waypoint)
	_accelerate(obj, obj.max_speed * (0.5 if absf(diff) > SLOW_TURN_ANGLE else 1.0))
	var direction := Vector2.from_angle(deg_to_rad(obj.yaw))
	obj.push.x += obj.speed * direction.x
	obj.push.y += obj.speed * direction.y


## Flies towards the waypoint, then the destination (0x45ae74).
func _fly(obj: MDKObject) -> void:
	var final := obj.waypoint == obj.move_destination
	var to_waypoint := obj.waypoint - obj.mdk_position
	var diff := 0.0
	var no_turning := obj.flags & MDKObject.FLAG_NO_TURNING != 0
	if not no_turning and absf(to_waypoint.x) + absf(to_waypoint.y) > 3.0:
		diff = turn_towards(obj, obj.waypoint)
	_accelerate(obj, obj.max_speed * (0.5 if absf(diff) > SLOW_TURN_ANGLE else 1.0))
	if not no_turning:
		var horizontal := Vector2(to_waypoint.x, to_waypoint.y).length()
		var vertical := absf(to_waypoint.z)
		var climb := vertical / (horizontal + vertical) if horizontal + vertical > 0.0 else 0.0
		var direction := Vector2.from_angle(deg_to_rad(obj.yaw)) * obj.speed * (1.0 - climb)
		obj.push += Vector3(direction.x, direction.y, obj.speed * climb * signf(to_waypoint.z))
		if horizontal < 4.0 and vertical < 3.0:
			if final:
				_stop(obj)
			else:
				obj.waypoint = obj.move_destination
		return
	var distance := absf(to_waypoint.x) + absf(to_waypoint.y) + absf(to_waypoint.z)
	if distance < 1.0:
		if final:
			obj.mdk_position = obj.waypoint
			_stop(obj)
			return
		obj.waypoint = obj.move_destination
	if distance <= 0.0:
		return
	var step := to_waypoint * (obj.speed * dt / distance)
	for axis in 3:
		if absf(step[axis]) > absf(to_waypoint[axis]):
			step[axis] = to_waypoint[axis]
	obj.push += step / dt


## Chases a point, flying at a speed in units per tick (movement command 6, 0x45e448).
func _chase(obj: MDKObject, point: Vector3) -> void:
	var target_yaw := obj.yaw
	if point.x != obj.mdk_position.x or point.y != obj.mdk_position.y:
		target_yaw = obj.yaw_to(point)
	var off_angle := absf(wrapf(obj.yaw - target_yaw, -180.0, 180.0))
	var chase_speed := obj.speed
	if off_angle < 90.0 or absf(obj.mdk_position.x - point.x) > 30.0 or absf(obj.mdk_position.y - point.y) > 30.0:
		turn_towards(obj, point)
		if off_angle <= 22.5:
			chase_speed = minf(chase_speed + (22.5 - off_angle) * ticks / 6.0 * 0.0444444, 2.3333333)
		else:
			chase_speed = maxf(chase_speed - ticks * 0.05, 0.3333333)
		obj.speed = chase_speed
	var step := chase_speed * ticks
	var direction := Vector2.from_angle(deg_to_rad(obj.yaw)) * step
	obj.mdk_position.x += direction.x
	obj.mdk_position.y += direction.y
	obj.mdk_position.z = move_toward(obj.mdk_position.z, point.z, step * 0.25)


## Keeps a formation position around the leader (movement command 1).
func _follow_formation(obj: MDKObject) -> void:
	var leader := obj.leader
	if not leader or leader.dead:
		obj.move_command = 0
		return
	var destination := formation_position(leader, obj.waypoint)
	obj.move_destination = destination
	var to_destination := destination - obj.mdk_position
	var max_step := obj.max_speed * dt
	if to_destination.length_squared() >= max_step * max_step:
		turn_towards(obj, destination)
		var direction := Vector2.from_angle(deg_to_rad(obj.yaw)) * obj.max_speed
		obj.push.x += direction.x
		obj.push.y += direction.y
		if obj.mdk_position.z <= destination.z - ticks:
			obj.push.z += ticks
		elif obj.mdk_position.z >= destination.z + ticks:
			obj.push.z -= ticks
		else:
			obj.push.z = destination.z - obj.mdk_position.z
		return
	obj.mdk_position = destination
	obj.yaw = move_toward(obj.yaw, leader.yaw, TURN_SPEED * dt)


## Position of a formation `offset` (`obj+0x12c`) around a leader.
static func formation_position(leader: MDKObject, offset: Vector3) -> Vector3:
	var s := sin(deg_to_rad(leader.yaw))
	var c := cos(deg_to_rad(leader.yaw))
	var p := leader.mdk_position
	return Vector3(p.x + offset.x * s - offset.y * c, p.y - offset.y * s - offset.x * c, p.z + offset.z)


## Moves along the yaw and pitch (movement command 88, `set_move_x`).
func _move_forward(obj: MDKObject) -> void:
	var target_speed := obj.max_speed if obj.move_parameter != 0 else 0.0
	_accelerate(obj, target_speed)
	var direction := Vector2.from_angle(deg_to_rad(obj.yaw))
	if obj.flags & MDKObject.FLAG_GRAVITY:
		obj.push.x += obj.speed * direction.x
		obj.push.y += obj.speed * direction.y
	else:
		var pitch := deg_to_rad(obj.pitch)
		obj.push += Vector3(direction.x * cos(pitch), direction.y * cos(pitch), sin(pitch)) * obj.speed
	if obj.move_parameter == 0 and obj.speed == target_speed:
		obj.move_command = 0


## Stays attached to another object (movement command 74, `attach_to`): reference point `a` of this
## object is kept on point `b` of the other one.
func _follow_attachment(obj: MDKObject) -> void:
	var other := obj.leader
	if not other or other.dead or other.health == 0:
		obj.move_command = 0
		return
	obj.mdk_position += other.get_reference_point(obj.attach_points.y) - obj.get_reference_point(obj.attach_points.x)
	obj.yaw = other.yaw
	obj.pitch = other.pitch


## Flies straight along the yaw and pitch until the lifetime (`obj+0x302`) runs out or something is
## hit (movement command 61, 0x45b6c8).
func _fly_projectile(obj: MDKObject) -> void:
	var old := obj.mdk_position
	var yaw := deg_to_rad(obj.yaw)
	var pitch := deg_to_rad(obj.pitch)
	obj.mdk_position += Vector3(cos(yaw) * cos(pitch), sin(yaw) * cos(pitch), sin(pitch)) * obj.speed * dt
	obj.parameter -= dt
	if obj.parameter <= 0.0:
		runtime.kill(obj)
		return
	var hit := runtime.raycast(old, obj.mdk_position)
	if not hit.is_empty():
		obj.mdk_position = MDKScriptRuntime.to_mdk(hit.position)
		runtime.kill(obj)
		return
	var kurt_box := runtime.get_kurt_box().grow(1.0)
	var touch: Variant = kurt_box.intersects_segment(old, obj.mdk_position)
	if touch != null:
		obj.contact_flags |= MDKObject.CONTACT_TOUCHED_KURT
		obj.mdk_position = touch
	else:
		obj.contact_flags &= ~MDKObject.CONTACT_TOUCHED_KURT


# Velocity.

## Applies friction, then moves by the velocity and this frame's push, colliding with the arena
## when the object has `FLAG_COLLIDES` (0x45e810).
func _apply_velocity(obj: MDKObject) -> void:
	obj.contact_flags &= ~(MDKObject.CONTACT_COLLIDED | MDKObject.CONTACT_FLOOR | 0x10)
	var gravity := obj.flags & MDKObject.FLAG_GRAVITY != 0
	var moving := obj.velocity if not gravity else Vector3(obj.velocity.x, obj.velocity.y, 0.0)
	var length := moving.length()
	if length > 0.0:
		var factor := maxf(length - obj.friction * dt, 0.0) / length
		obj.velocity.x *= factor
		obj.velocity.y *= factor
		if not gravity:
			obj.velocity.z *= factor
	var motion := (obj.velocity + obj.push) * dt
	obj.push = Vector3.ZERO
	if motion == Vector3.ZERO:
		return
	if not obj.flags & MDKObject.FLAG_COLLIDES:
		obj.mdk_position += motion
	else:
		var normal: Variant = _sweep(obj, motion)
		if normal != null:
			obj.contact_flags |= MDKObject.CONTACT_COLLIDED
			if motion.z <= 0.0:
				obj.contact_flags |= MDKObject.CONTACT_FLOOR
			if obj.flags & MDKObject.FLAG_BOUNCES:
				obj.velocity += normal * obj.velocity.dot(normal) * -1.8
			else:
				obj.velocity.z = 0.0
	if obj.mdk_position.z < runtime.get_arena_floor(obj.arena) - FALL_OUT_DEPTH:
		runtime.fall_out(obj)


## Moves the object's collision box by `motion` (MDK) against the arena geometry, sliding along
## what it hits. Returns the normal (MDK) of the first hit, or `null`.
func _sweep(obj: MDKObject, motion: Vector3) -> Variant:
	# The box is half as wide as the object's bounds and starts just above its origin (0x45fec4).
	var bounds := obj.model.bounds if obj.model else AABB(Vector3(-1, -1, 0), Vector3(2, 2, 4))
	var c := absf(cos(deg_to_rad(obj.yaw)))
	var s := absf(sin(deg_to_rad(obj.yaw)))
	var size := bounds.size * obj.model_scale
	var half := Vector3((c * size.x + s * size.y) * 0.25, (s * size.x + c * size.y) * 0.25, maxf(bounds.end.z * obj.model_scale, 0.5) * 0.5)
	var center := bounds.get_center().rotated(Vector3.BACK, deg_to_rad(obj.yaw)) * obj.model_scale
	center.z = half.z + (0.05 if motion.z != 0.0 else 0.5)
	_box.size = Vector3(half.x, half.z, half.y) * 2.0
	if not _probe.is_valid():
		_create_probe()
	# Godot's shape casts ignore shapes they start inside of (the whole arena is one shape), so the
	# motion is tested like a character body's: it recovers from overlaps and reports them.
	_motion_parameters.exclude_bodies = [runtime.kurt.get_rid()]
	var normal: Variant = null
	var remaining := motion
	for i in 2:
		_motion_parameters.from = Transform3D(Basis(), MDKMeshBuilder.to_godot(obj.mdk_position + center))
		_motion_parameters.motion = MDKMeshBuilder.to_godot(remaining)
		var hit := PhysicsServer3D.body_test_motion(_probe, _motion_parameters, _motion_result)
		obj.mdk_position += MDKScriptRuntime.to_mdk(_motion_result.get_travel())
		if not hit:
			break
		var hit_normal := MDKScriptRuntime.to_mdk(_motion_result.get_collision_normal())
		if normal == null:
			normal = hit_normal
		# Slide along what was hit.
		remaining = MDKScriptRuntime.to_mdk(_motion_result.get_remainder())
		remaining -= hit_normal * remaining.dot(hit_normal)
		if remaining.length_squared() < 1e-6:
			break
	return normal


## A body used to test object motions against the level (it collides with nothing itself).
func _create_probe() -> void:
	_probe = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_probe, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_add_shape(_probe, _box.get_rid())
	PhysicsServer3D.body_set_collision_layer(_probe, 0)
	PhysicsServer3D.body_set_collision_mask(_probe, 1)
	PhysicsServer3D.body_set_space(_probe, runtime.get_world_3d().space)
	_motion_parameters.margin = 0.01
	_motion_parameters.recovery_as_collision = true


func free_probe() -> void:
	if _probe.is_valid():
		PhysicsServer3D.free_rid(_probe)
		_probe = RID()

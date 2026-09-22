## Moves scripted objects each frame like the original object update (0x43c7dc): spline paths
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
	if obj.effect_frames > 0:
		# Effects only play their texture animation, one frame per tick (`object_anim_update`).
		obj.effect_time += ticks
		if obj.effect_time >= obj.effect_frames:
			runtime.remove(obj)
		else:
			obj.set_texture_frame(int(obj.effect_time))
		return
	if obj.path:
		if obj.flags & MDKObject.FLAG_PATH_SPEED_BY_KURT:
			_update_path_speed(obj)
		_update_path(obj)
	_update_command(obj)
	if obj.dead:
		return
	if obj.flags & MDKObject.FLAG_SWINGING:
		_swing(obj)
	if obj.flags & MDKObject.FLAG_GRAVITY:
		obj.velocity.z -= obj.gravity * dt
		_updraft(obj)
		obj.velocity.z = maxf(obj.velocity.z, TERMINAL_VELOCITY)
	_apply_velocity(obj)
	if obj.dead:
		return
	# Kurt's items and effects (0x1000), or else pickups (0x200000).
	if obj.thrown_kind > 0:
		runtime.items.update_thrown(obj)
		if obj.dead:
			return
	elif obj.flags & MDKObject.FLAG_PICKUP:
		runtime.behaviors.update_pickup(obj)
	var time := obj.animation_time
	obj.advance_animation(dt)
	if not obj.frame_sound.is_empty() and obj.animation and time < obj.frame_sound_frame 			and obj.frame_sound_frame <= time + dt * obj.animation_fps * obj.animation.speed:
		runtime.play_sound(obj, obj.frame_sound, 0, null)
		obj.frame_sound = ""
	if obj.flags & MDKObject.FLAG_ROLLING:
		_roll(obj)
	_bank(obj)
	obj.previous_position = obj.mdk_position
	obj.update_transform()
	obj.update_body()
	obj.update_ropes()


# Spline paths: `u32 key count`, then keys of 40 bytes: `s32 frame`, position, in tangent and out
# tangent (3 floats each). Segments are cubic Hermite curves.

func path_key_count(path: int) -> int:
	return _bytes.decode_u32(path)


func path_key_frame(path: int, key: int) -> int:
	return _bytes.decode_s32(path + 4 + key * 40)


func _path_vector(path: int, key: int, field: int) -> Vector3:
	var offset := path + 8 + key * 40 + field * 12
	return Vector3(_bytes.decode_float(offset), _bytes.decode_float(offset + 4), _bytes.decode_float(offset + 8))


## Fans lift objects with gravity (0x45e74c; not rolling objects in level 4); Kurt's thrown items
## (but the mortar) also lose most of their horizontal speed in them.
func _updraft(obj: MDKObject) -> void:
	if runtime.level.number == 4 and obj.flags & MDKObject.FLAG_ROLLING:
		return
	var vz := runtime.fans.query(obj.arena, obj.mdk_position, obj.velocity.z, MDKFans.MASK_OBJECTS, dt)
	if is_nan(vz):
		return
	obj.velocity.z = vz
	if obj.flags & 0x45000 == 0x1000 and obj.thrown_kind != KurtInventory.Item.MORTAR:
		obj.velocity.x *= 0.1
		obj.velocity.y *= 0.1


## `path_speed_by_kurt` (opcode 164, 0x43c258): the path speed goes towards the speed for Kurt
## being ahead of, around, or behind the set distance (measured along the object's heading), by
## `(near − far) × 0.5` per second.
func _update_path_speed(obj: MDKObject) -> void:
	var heading := Vector2.from_angle(deg_to_rad(obj.yaw))
	var ahead := (obj.mdk_position.x - runtime.kurt_position.x) * heading.x \
			+ (obj.mdk_position.y - runtime.kurt_position.y) * heading.y
	var distance: float = obj.path_speeds[0]
	var target: float = obj.path_speeds[1]
	if ahead <= distance + 5.0:
		target = obj.path_speeds[2] if ahead >= distance - 5.0 else obj.path_speeds[3]
	var step: float = (obj.path_speeds[3] - obj.path_speeds[1]) * dt * 0.5
	if obj.path_speed <= target:
		obj.path_speed = minf(obj.path_speed + step, target)
	else:
		obj.path_speed = maxf(obj.path_speed - step, target)


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
			var yaw := obj.yaw
			var walking := obj.flags & MDKObject.FLAG_GRAVITY != 0
			if walking:
				_walk(obj)
			else:
				_fly(obj)
			if obj.move_command:
				_detect_stuck(obj, walking)
				_handle_stuck(obj, absf(wrapf(obj.yaw - yaw, -180.0, 180.0)))
		61:
			_fly_projectile(obj)
		74:
			_follow_attachment(obj)
		88:
			_move_forward(obj)
		30:
			_update_chain(obj)
		15:
			# The alarm: `ALERT` every 32 ticks, and `if_alarm` holds for 10 ticks.
			if obj.arena == runtime.current_arena:
				if runtime.tick_count() & 31 == 0:
					runtime.play_sound_at("ALERT", obj.mdk_position)
				runtime.alarm_ticks = 10
		229:
			obj.parameter_timer += dt
			if obj.parameter_timer >= obj.parameter * 0.5 and obj.contact_flags & MDKObject.CONTACT_FLOOR:
				obj.move_command = 0
				obj.velocity = Vector3.ZERO


## Rolling (0x4602c8): the object turns by `distance / (2π × radius)` turns about the horizontal
## axis across its motion (the original builds the turn from two angles, which is close to this).
func _roll(obj: MDKObject) -> void:
	var moved := Vector2(obj.mdk_position.x - obj.previous_position.x, obj.mdk_position.y - obj.previous_position.y)
	var distance := moved.length()
	if distance <= 0.0:
		return
	var radius := obj.roll_radius if obj.roll_radius > 0.0 else 1.0
	var axis := MDKMeshBuilder.to_godot(Vector3(-moved.y, moved.x, 0.0) / distance)
	obj.rolling_basis = (Basis(axis, distance / radius) * obj.rolling_basis).orthonormalized()


## `turn_and_jump_to_dest` (opcode 229, 0x460d24): turns towards the destination by at most
## `rate` degrees per second; once facing it, jumps there (movement command 229). The top of the
## jump is 10 above the higher end and at least 30 above the lower one; the flight time allows for
## the friction slowing the object down.
func turn_and_jump(obj: MDKObject, rate: float) -> void:
	var heading := obj.yaw_to(obj.move_destination)
	var diff := wrapf(heading - obj.yaw, -180.0, 180.0)
	if absf(diff) > rate * dt:
		obj.yaw = fposmod(obj.yaw + signf(diff) * rate * dt, 360.0)
		return
	obj.yaw = heading
	obj.move_command = 229
	var z := obj.mdk_position.z
	var goal := obj.move_destination.z
	var top := maxf(z + 10.0, goal + 30.0) if goal < z else maxf(goal + 10.0, z + 30.0)
	var g := obj.gravity
	var up := sqrt((top - z) * 2.0 * g)
	var time := (up + sqrt(maxf(up * up + (z - goal) * g * 2.0, 0.0))) / g
	obj.parameter = time
	obj.parameter_timer = 0.0
	var offset := Vector2(obj.move_destination.x - obj.mdk_position.x, obj.move_destination.y - obj.mdk_position.y)
	var distance := offset.length()
	var speed := (obj.friction * 0.5 * time * time + distance) / time
	var direction := offset / distance if distance > 0.0 else Vector2.ZERO
	obj.velocity = Vector3(direction.x * speed, direction.y * speed, up)


## A chain link (movement command 30, `spawn_chain`): the links hang off the head object, each
## turned 90° more than the one before, with its first reference point on the previous one's
## second. Only the first link (id 0) places the whole chain; a link whose leader or any link
## before it is gone detaches and stops.
func _update_chain(link: MDKObject) -> void:
	var leader := link.leader
	if not leader or leader.dead:
		link.leader = null
		link.move_command = 0
		return
	var links: Array[MDKObject] = []
	for other in runtime.objects:
		if other.leader == leader and not other.dead:
			links.push_back(other)
	links.sort_custom(func(a: MDKObject, b: MDKObject) -> bool: return a.instance_id < b.instance_id)
	for i in link.instance_id:
		if i >= links.size() or links[i].instance_id != i:
			link.leader = null
			link.move_command = 0
			return
	if link.instance_id != 0:
		return
	var previous := leader
	for i in links.size():
		if links[i].instance_id != i:
			break
		var current := links[i]
		current.yaw = fposmod(leader.yaw + 90.0 * i, 360.0)
		current.mdk_position += previous.get_reference_point(1) - current.get_reference_point(0)
		previous = current


## A pendulum (0x43cfe8, flag 0x400000 set by `jump_to`): the pitch swings by
## `ω −= sin θ·k·t, θ += ω·k·t` (t in ticks) and the object hangs on its rope below the pivot, in the
## vertical plane of its yaw. At each turning point the plane turns towards Kurt by at most 15°
## (folded to ±90°: either side will do), at 10° per second.
func _swing(obj: MDKObject) -> void:
	var old_speed := obj.swing_speed
	obj.swing_speed -= sin(deg_to_rad(obj.pitch)) * obj.swing_gain * ticks
	obj.pitch += obj.swing_speed * obj.swing_gain * ticks
	var angle := deg_to_rad(obj.pitch)
	var heading := Vector2.from_angle(deg_to_rad(obj.yaw))
	obj.mdk_position = obj.swing_pivot + Vector3(heading.x * sin(angle), heading.y * sin(angle), -cos(angle)) * obj.swing_length
	if obj.swing_speed * old_speed <= 0.0:
		obj.yaw = fposmod(obj.yaw, 360.0)
		var diff := wrapf(obj.yaw_to(runtime.target_position) - obj.yaw, -180.0, 180.0)
		if diff < -90.0:
			diff += 180.0
		elif diff > 90.0:
			diff -= 180.0
		obj.swing_yaw = obj.yaw + clampf(diff, -15.0, 15.0)
	obj.yaw = move_toward(obj.yaw, obj.swing_yaw, 10.0 * dt)
	obj.rope_color = 1
	obj.rope_mask = 1
	obj.rope_points[0] = obj.mdk_position
	obj.rope_points[1] = obj.swing_pivot


## `plan_move` (0x45a1dc), when a walk or flight starts (`move_to`, `move_near_target`,
## `move_to_bomb`, `command_objects` 43): if the line from the object to the destination (both 8
## units up) is blocked, tries detour points on either side of its middle, 0.1 to 1.1 times its
## length away, and takes the first one seen from both ends. The original offsets them along
## `(sin a, cos a)` for a heading `a`, which is only sideways when the line runs along an axis.
func plan_move(obj: MDKObject) -> void:
	obj.waypoint = obj.move_destination
	obj.stuck_count = 0
	obj.stuck_ticks = 0.0
	obj.stuck_moved = Vector3.ZERO
	obj.contact_flags &= ~MDKObject.CONTACT_STUCK
	var a := obj.mdk_position + Vector3(0.0, 0.0, 8.0)
	var b := obj.move_destination + Vector3(0.0, 0.0, 8.0)
	if runtime.raycast(a, b).is_empty():
		return
	var middle := (a + b) * 0.5
	for i in 11:
		for side in [-1.0, 1.0]:
			var point := _detour(a, b, middle, 0.1 * (i + 1) * side)
			if _clear(a, point, b):
				obj.waypoint = point
				return


## The stuck replan (0x45a434): an object heading to a detour gives it up and heads for the
## destination again; one heading for the destination tries detours around the point 3/4 of the
## way there, then around itself (0.1 to 1.9 times the distance, both sides).
func _replan(obj: MDKObject) -> void:
	if obj.waypoint != obj.move_destination:
		obj.waypoint = obj.move_destination
		obj.stuck_ticks = 0.0
		obj.stuck_moved = Vector3.ZERO
		obj.contact_flags &= ~MDKObject.CONTACT_STUCK
		return
	var a := obj.mdk_position + Vector3(0.0, 0.0, 8.0)
	var b := obj.move_destination + Vector3(0.0, 0.0, 8.0)
	for base in [b * 0.75 + a * 0.25, a]:
		for i in 7:
			for side in [-1.0, 1.0]:
				var point := _detour(a, b, base, (0.1 + 0.3 * i) * side)
				if _clear(a, point, b):
					obj.waypoint = point
					return


func _detour(a: Vector3, b: Vector3, base: Vector3, amount: float) -> Vector3:
	var angle := atan2(b.y - a.y, b.x - a.x)
	return base + Vector3(sin(angle), cos(angle), 0.0) * amount * a.distance_to(b)


func _clear(a: Vector3, point: Vector3, b: Vector3) -> bool:
	return runtime.raycast(a, point).is_empty() and runtime.raycast(point, b).is_empty()


## Stuck detection after walking or flying (0x45a7d4, 0x45ae74). Walking with command 43, any
## collision counts as stuck. Otherwise an object that collides while faster than 2 is stuck when it
## has moved less than half its speed over a window of 16 ticks (9 walking with command 197).
func _detect_stuck(obj: MDKObject, walking: bool) -> void:
	var collided := obj.contact_flags & MDKObject.CONTACT_COLLIDED != 0
	if walking and obj.move_command == 43:
		if collided:
			obj.contact_flags |= MDKObject.CONTACT_STUCK
			obj.stuck_ticks = 30.0
		else:
			obj.stuck_count = 0
			obj.stuck_ticks = 0.0
			obj.stuck_moved = Vector3.ZERO
		return
	if not collided or obj.speed <= 2.0:
		obj.stuck_count = 0
		obj.stuck_ticks = 0.0
		obj.stuck_moved = Vector3.ZERO
		return
	var window := 9.0 if walking and obj.move_command == 197 else 16.0
	if obj.stuck_ticks < window:
		obj.stuck_moved += obj.mdk_position - obj.previous_position
		obj.stuck_ticks += ticks
		return
	if absf(obj.stuck_moved.x) + absf(obj.stuck_moved.y) + absf(obj.stuck_moved.z) >= obj.speed * 0.5:
		obj.stuck_ticks = 0.0
		obj.stuck_moved = Vector3.ZERO
	else:
		obj.contact_flags |= MDKObject.CONTACT_STUCK


## A stuck object that isn't turning (less than 3° this update, 0x45b6c8) replans once; after that
## `move_to` (78) slides straight to the waypoint through everything and the others give up
## (`if_move_idle_flag` sees `stuck_count`). Command 197 gives up at once.
func _handle_stuck(obj: MDKObject, turned: float) -> void:
	if not obj.contact_flags & MDKObject.CONTACT_STUCK or turned >= 3.0:
		return
	obj.stuck_count += 1
	if obj.move_command == 197:
		_stop(obj)
	elif obj.stuck_count < 3:
		_replan(obj)
		obj.stuck_count += 1
	elif obj.move_command == 78:
		var to_waypoint := obj.waypoint - obj.mdk_position
		var step := obj.speed * dt
		obj.mdk_position += Vector3(clampf(to_waypoint.x, -step, step), clampf(to_waypoint.y, -step, step), clampf(to_waypoint.z, -step, step))
	else:
		obj.move_command = 0
		obj.speed = 0.0


## Automatic banking (0x43b65c): objects lean into their turns, `roll = (roll − turn per tick) ×
## 0.95` within ±10° (the turn counted at most 2° per tick), unless flag 0x80 (`set_banking` 0) or
## flag 1 is set.
func _bank(obj: MDKObject) -> void:
	var turn := clampf(wrapf(obj.yaw - obj.banking_yaw, -180.0, 180.0) / ticks, -2.0, 2.0)
	obj.banking_yaw = obj.yaw
	if obj.flags & (MDKObject.FLAG_NO_BANKING | 1) or obj.thrown_kind > 0 or obj.flags & MDKObject.FLAG_ROLLING:
		return
	obj.roll = clampf((wrapf(obj.roll, -180.0, 180.0) - turn) * 0.95, -10.0, 10.0)


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
	var bounds := obj.get_pose_bounds() if obj.model else AABB(Vector3(-1, -1, 0), Vector3(2, 2, 4))
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

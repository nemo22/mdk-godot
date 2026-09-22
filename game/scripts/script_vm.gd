## Runs MDK object scripts, following the original interpreter (`script_run`). See `docs/scripts.md`.
## Opcodes that aren't implemented yet do nothing (their conditions are false), but they are always
## decoded, so scripts never lose sync.
class_name MDKScriptVM
extends RefCounted

const MAX_OPCODES_PER_FRAME := 1000
const GOSUB_DEPTH := 4
## Return value of handlers: stop running this object's script for this frame.
const YIELD := -1

var runtime: MDKScriptRuntime
var decoder: MDKScriptDecoder
## Opcodes seen that aren't implemented (opcode to count), for debugging.
var unimplemented := {}
## Frame time in seconds and in 30 Hz ticks.
var dt := 1.0 / 30.0
var ticks := 1.0
## Opcodes run so far in the current object's frame (`if_opcode_count`).
var _opcode_count := 0


func _init(p_runtime: MDKScriptRuntime, p_decoder: MDKScriptDecoder) -> void:
	runtime = p_runtime
	decoder = p_decoder


## Runs one frame of an object's script.
func run(obj: MDKObject) -> void:
	if obj.restart == 0 or obj.dead:
		return
	var pc := obj.restart
	if obj.wait_time > 0.0:
		obj.wait_time -= dt
		if obj.wait_time > 0.0:
			return
		obj.wait_time = 0.0
		pc = obj.wait_resume
	var count := 0
	while true:
		var ins := decoder.decode(pc)
		if ins == null:
			# Unknown opcode: the script stops (the original only writes to its debug log).
			obj.restart = 0
			return
		if ins.opcode == 0xFF:
			obj.hit_event = 0
			return
		count += 1
		_opcode_count = count
		if count > MAX_OPCODES_PER_FRAME:
			obj.restart = 0
			return
		pc = _execute(obj, ins)
		if pc == YIELD or obj.dead:
			return


## Applies a branch action when `condition` is true (or the else gosub when false). Returns the next pc.
func _branch(obj: MDKObject, ins: MDKScriptDecoder.Instruction, condition: bool) -> int:
	var action := ins.action
	if action.is_empty():
		return ins.next
	match action[0]:
		"goto":
			return _goto(obj, action[1]) if condition else ins.next
		"gosub":
			return _gosub(obj, ins.next, action[1]) if condition else ins.next
		"gosub_else":
			return _gosub(obj, ins.next, action[1] if condition else action[2])
		"return":
			return _return(obj) if condition else ins.next
	return ins.next


func _goto(obj: MDKObject, target: int) -> int:
	if target == 0:
		obj.restart = 0
		return YIELD
	obj.restart = target
	obj.level_timers[obj.gosub_returns.size()] = 0.0
	return target


func _gosub(obj: MDKObject, return_pc: int, target: int) -> int:
	if obj.gosub_returns.size() >= GOSUB_DEPTH or target == 0:
		obj.restart = 0
		return YIELD
	obj.gosub_returns.push_back(return_pc)
	obj.gosub_restarts.push_back(obj.restart)
	obj.restart = target
	obj.level_timers[obj.gosub_returns.size()] = 0.0
	return target


func _return(obj: MDKObject) -> int:
	if obj.gosub_returns.is_empty():
		obj.restart = 0
		return YIELD
	obj.restart = obj.gosub_restarts.pop_back()
	return obj.gosub_returns.pop_back()


## Reads a value operand (a float literal or `[kind, index]` of a variable).
func _value(obj: MDKObject, operand: Variant) -> float:
	if operand is float:
		return operand
	return _variables(obj, operand[0])[clampi(operand[1], 0, 3)]


## Variables of a source: 0 global, 1 arena, 2 own, other = linked object.
func _variables(obj: MDKObject, source: int) -> Array:
	match source:
		0:
			return runtime.global_variables
		1:
			return runtime.get_arena_state(obj.arena).variables
		2:
			return obj.variables
	return obj.linked.variables if obj.linked else [0.0, 0.0, 0.0, 0.0]


func _get_flags(obj: MDKObject, source: int) -> int:
	match source:
		0:
			return runtime.global_flags
		1:
			return runtime.get_arena_state(obj.arena).flags
		2:
			return obj.script_flags
	return obj.linked.script_flags if obj.linked else 0


func _set_flags(obj: MDKObject, source: int, value: int) -> void:
	match source:
		0:
			runtime.global_flags = value
		1:
			runtime.get_arena_state(obj.arena).flags = value
		2:
			obj.script_flags = value
		_:
			if obj.linked:
				obj.linked.script_flags = value


## Comparison operand `[op, a]` or `[op, a, b]` (`compare_values`).
static func _compare(value: float, cond: Array) -> bool:
	var a: float = cond[1]
	match cond[0]:
		1:
			return value < a
		2:
			return value > a
		3:
			return value < a + 0.05
		4:
			return value > a - 0.05
		5:
			return absf(value - a) < 0.05
		6:
			return absf(value - a) >= 0.05
		7:
			return value >= a and value <= cond[2]
		8:
			return value <= a or value >= cond[2]
	return false


## Reads a 16-bit value as signed.
static func _s16(value: int) -> int:
	return value - 0x10000 if value >= 0x8000 else value


## Picks a weighted random target (`[[weight, target], …]`).
static func _weighted_target(entries: Array) -> int:
	var total := 0
	for entry in entries:
		total += entry[0]
	var r := randi() % maxi(total, 1)
	for entry in entries:
		r -= entry[0]
		if r < 0:
			return entry[1]
	return 0


## Picks a random target of a `repeat` operand of code offsets (`[[target], …]`).
static func _random_target(entries: Array) -> int:
	if entries.is_empty():
		return 0
	return entries[randi() % entries.size()][0]


func _execute(obj: MDKObject, ins: MDKScriptDecoder.Instruction) -> int:
	var o := ins.operands
	match ins.opcode:
		1:  # set_restart
			obj.restart = ins.next
		9:  # stop_script
			obj.restart = 0
			obj.gosub_returns.clear()
			obj.gosub_restarts.clear()
			return YIELD
		12:  # goto (random target)
			return _goto(obj, _random_target(o[0]))
		94:  # goto_weighted
			return _goto(obj, _weighted_target(o[0]))
		252:  # gosub (random target)
			return _gosub(obj, ins.next, _random_target(o[0]))
		95:  # gosub_weighted
			return _gosub(obj, ins.next, _weighted_target(o[0]))
		253:  # return
			return _return(obj)
		125:  # clear_gosub_stack
			obj.gosub_returns.clear()
			obj.gosub_restarts.clear()
		64:  # wait
			obj.wait_time = maxf(_value(obj, o[0]), 1e-5)
			obj.wait_resume = ins.next
			return YIELD
		18:  # if_timer: the counter of the current gosub level counts ticks
			var level := obj.gosub_returns.size()
			if o[0] * 30.0 > obj.level_timers[level]:
				obj.level_timers[level] += ticks
				return _branch(obj, ins, false)
			obj.level_timers[level] = 0.0
			return _branch(obj, ins, true)

		# Spawning.
		86, 161:  # spawn, spawn_flagged
			runtime.spawn(obj, o[3], Vector3(o[0], o[1], o[2]), 0.0, -1, o[4], ins.opcode == 161)
		230:  # spawn_ex
			runtime.spawn(obj, o[5], Vector3(o[0], o[1], o[2]), o[3], o[4], o[6], false)
		113:  # spawn_relative
			var offset := Vector2(o[0], o[1]).rotated(deg_to_rad(obj.yaw))
			runtime.spawn(obj, o[3], obj.mdk_position + Vector3(offset.x, offset.y, o[2]), 0.0, -1, o[4], false)
		150:  # door_set_anims: opening and closing animations
			obj.door_animations = [o[0], o[1]]
		151:  # door_set_names: sounds when opening, closing, open, closed
			obj.door_sounds = [o[0], o[1], o[2], o[3]]
		152:  # door_set_flags (the low 4 bits are the engine's state)
			obj.door_state = (obj.door_state & 0xF) | (o[0] & ~0xF)
		153:  # door_set_param: distance at which the door opens
			obj.door_distance = o[0]
		100:  # arena_show (every arena is always drawn in the port)
			pass
		149:  # spawn_connector
			runtime.spawn_connector(obj, o[5], Vector3(o[0], o[1], o[2]), o[3], o[4], o[6], o[7])
		111:  # set_instance
			obj.instance_id = o[0] & 0xFFFF
		110:  # delete_self
			runtime.remove(obj)
			return YIELD
		76:  # set_death_script
			obj.death_script = o[0]
		16:  # set_health
			obj.health = o[0]
			obj.indestructible = o[0] >= 65000
			if o[0] == 0:
				runtime.kill(obj)
				return YIELD
		56:  # add_health
			if obj.health < 65000:
				obj.health += o[0]
				if obj.health <= 0:
					runtime.kill(obj)
					return YIELD

		# Animation.
		3, 59:  # anim_once, anim_loop
			obj.play_animation(runtime.get_animation(obj, o[0]), ins.opcode == 59)
		17:  # if_anim_done
			return _branch(obj, ins, obj.is_animation_done())
		92:  # if_anim_frame
			return _branch(obj, ins, obj.is_animation_done() or obj.animation_frame >= o[0] - 1)
		118:  # anim_end_frame (s16)
			obj.animation_end_frame = _s16((o[0] & 0xFFFF) - 1)
		24:  # set_id_and_name: a sound played when the animation reaches frame n - 1
			obj.frame_sound_frame = o[0] - 1
			obj.frame_sound = o[1]
		25, 26:  # set_string154, set_string150
			obj.labels[ins.opcode - 25] = o[0]
		19:  # anim_mark_ended
			obj.animation_end_frame = MDKObject.ANIMATION_ENDED
		31:  # set_parts_mask
			var mask := obj.hidden_parts
			for entry: Array in o[0]:
				var part_name: String = entry[0].to_upper()
				if obj.model:
					for i in obj.model.parts.size():
						if part_name == "ALL" or obj.model.parts[i].name.to_upper() == part_name:
							mask |= 1 << i
			obj.set_hidden_parts(mask)
		83:  # set_scale: a value, or `[target, rate]` to grow or shrink towards the target
			if o[0] is Array and o[0].size() == 2 and o[0][0] is float:
				var target: float = o[0][0]
				if obj.model_scale < target:
					obj.model_scale = minf(obj.model_scale * (1.0 + o[0][1] * dt), target)
				elif obj.model_scale > target:
					obj.model_scale = maxf(obj.model_scale * (1.0 - o[0][1] * dt * 0.5), target)
			else:
				obj.model_scale = _value(obj, o[0])

		# Hits.
		22:  # if_hit: any hit but blasts; the event is cleared when true
			var hit := obj.hit_event != 0 and obj.hit_event != -3
			if hit:
				obj.hit_event = 0
			return _branch(obj, ins, hit)
		212:  # if_hit_fd: a blast
			var hit := obj.hit_event == -3
			if hit:
				obj.hit_event = 0
			return _branch(obj, ins, hit)
		42:  # if_hit_part: `name` (cleared when true) or `["", name]` (not cleared); "ANY" = any part
			var part_name: String = o[0] if o[0] is String else o[0][1]
			var hit: bool = obj.model != null and obj.hit_event > 0 and obj.hit_event <= obj.model.parts.size() \
					and (part_name.to_upper() == "ANY" or obj.model.parts[obj.hit_event - 1].name.to_upper() == part_name.to_upper())
			if hit and o[0] is String:
				obj.hit_event = 0
			return _branch(obj, ins, hit)
		198:  # set_weak_parts
			obj.flags |= MDKObject.FLAG_WEAK_PARTS
			obj.weak_prefix = o[0]
			obj.weak_prefix_length = o[1]
			obj.part_health.resize(8)
			obj.part_health.fill(o[2] & 0xFFFF)
			obj.part_max_health = obj.part_health.duplicate()
		81:  # push_hit_dir: velocity along the direction of the last hit
			var speed: float = _value(obj, o[1]) * (dt if o[0] == 1 else 1.0)
			var direction := Vector2.from_angle(deg_to_rad(obj.hit_direction)) * speed
			obj.velocity.x += direction.x
			obj.velocity.y += direction.y
		108:  # if_touching_kurt
			if obj.move_command == 61:
				return _branch(obj, ins, obj.contact_flags & MDKObject.CONTACT_TOUCHED_KURT != 0)
			return _branch(obj, ins, runtime.get_world_bounds(obj).intersects(runtime.get_kurt_box()))
		109:  # hurt_kurt
			runtime.hurt_kurt(o[0])
		61:  # fire
			runtime.fire(obj, o[0], o[1], o[2])

		# Orientation.
		8:  # set_yaw
			obj.yaw = fposmod(o[0], 360.0)
		60:  # face_target
			obj.yaw = obj.yaw_to(runtime.target_position)
		40:  # turn_yaw
			obj.yaw = fposmod(obj.yaw + _value(obj, o[0]) * dt, 360.0)
		134:  # turn_roll
			obj.roll = fposmod(obj.roll + _value(obj, o[0]) * dt, 360.0)
		120:  # set_pitch
			obj.pitch = o[0]
		122:  # turn_pitch
			obj.pitch += clampf(wrapf(o[1] - obj.pitch, -180.0, 180.0), -o[0] * dt, o[0] * dt)
		97:  # set_banking (the automatic banking isn't implemented)
			if o[0] != 0:
				obj.flags &= ~MDKObject.FLAG_NO_BANKING
			else:
				obj.flags |= MDKObject.FLAG_NO_BANKING
				obj.roll = 0.0
		23:  # set_flag148_1
			if o[0] != 0:
				obj.flags |= 1
			else:
				obj.flags &= ~1
				obj.roll = 0.0
		207:  # turn_to_yaw
			var diff := wrapf(o[1] - obj.yaw, -180.0, 180.0)
			var step: float = o[0] * dt
			obj.yaw = fposmod(o[1] if absf(diff) <= step else obj.yaw + signf(diff) * step, 360.0)
			if ins.action[0] == "none":
				return ins.next
			return _branch(obj, ins, is_equal_approx(obj.yaw, fposmod(o[1], 360.0)))
		101:  # aim_target
			_aim(obj, 100.0, true)
		104:  # aim_target_inaccurate
			_aim(obj, o[0], false)
		235:  # turn_to_target_offset
			_turn_to_target(obj, o[0], o[1], o[2], o[3], null)
		105:  # turn_to_target_offset3d
			_turn_to_target(obj, o[0], o[1], o[2], o[3], o[4])
		62:  # if_target_angle
			var angle := absf(wrapf(obj.yaw_to(runtime.target_position) - obj.yaw, -180.0, 180.0))
			return _branch(obj, ins, _compare(angle, o[0]))
		193:  # face_mode
			var mode: int = o[0][0]
			if mode in [1, 2] and obj.velocity.x != 0.0 and obj.velocity.y != 0.0:
				obj.yaw = fposmod(rad_to_deg(atan2(obj.velocity.y, obj.velocity.x)), 360.0)
				if mode == 2 and obj.velocity.z != 0.0:
					obj.pitch = rad_to_deg(atan2(obj.velocity.z, Vector2(obj.velocity.x, obj.velocity.y).length()))
			elif mode == 3:
				for other in runtime.get_arena_objects(obj):
					if other.type_name.to_upper() == String(o[0][1]).to_upper():
						obj.yaw = other.yaw
						break

		# Movement.
		78:  # move_to
			_start_move(obj, 78, Vector3(o[0], o[1], o[2]))
		6:  # move_to_target
			obj.move_command = 6
		43:  # move_near_target (only in Kurt's arena)
			if obj.arena == runtime.current_arena:
				_start_move(obj, 43, runtime.near_target_destination(obj, o[0], o[1]))
		75:  # stop_motion
			obj.move_command = 0
		15:  # alarm
			obj.move_command = 15
		88:  # set_move_x
			obj.path = 0
			if o[0] != 2:
				obj.move_command = 88
				obj.move_parameter = o[0]
			else:
				obj.move_command = 0
				obj.speed = 0.0
		44:  # if_move_done
			return _branch(obj, ins, obj.move_command == 0)
		54:  # if_dest_dist (2D when on the floor)
			var to_destination := obj.move_destination - obj.mdk_position
			if obj.contact_flags & MDKObject.CONTACT_FLOOR:
				to_destination.z = 0.0
			return _branch(obj, ins, _compare(to_destination.length(), o[0]))
		50:  # set_max_speed
			obj.max_speed = _value(obj, o[0])
		51:  # set_accel
			obj.acceleration = _value(obj, o[0])
		52:  # set_decel
			obj.deceleration = _value(obj, o[0])
		53:  # set_speed
			obj.speed = _value(obj, o[0])
		82:  # set_friction (`set_param44`)
			obj.friction = _value(obj, o[0])
		55:  # set_gravity (`set_turn_rate`)
			obj.gravity = _value(obj, o[0])
		84:  # set_height_offset
			obj.height_offset = _value(obj, o[0])
		106:  # set_302: lifetime of projectiles, jump time…
			obj.parameter = o[0]
		39:  # push_forward
			var direction := Vector2.from_angle(deg_to_rad(obj.yaw)) * _value(obj, o[0])
			obj.push += Vector3(direction.x, direction.y, 0.0)
		201:  # push_dir
			var direction: Vector2 = Vector2.from_angle(deg_to_rad(obj.yaw + o[1])) * o[0]
			obj.push += Vector3(direction.x, direction.y, 0.0)
		80:  # add_vel_local
			var c := cos(deg_to_rad(obj.yaw))
			var s := sin(deg_to_rad(obj.yaw))
			obj.velocity += Vector3(-o[0] * c - o[1] * s, -o[1] * c - o[0] * s, o[2])
		211:  # stop_velocity
			obj.velocity = Vector3.ZERO
		38:  # if_vel_z
			return _branch(obj, ins, _compare(obj.velocity.z, o[0]))
		37:  # if_flag14c_2 (on the floor)
			return _branch(obj, ins, obj.contact_flags & MDKObject.CONTACT_FLOOR != 0)
		200:  # move_to_point
			var to_point := Vector3(o[1], o[2], o[3]) - obj.mdk_position
			if obj.flags & MDKObject.FLAG_COLLIDES:
				to_point.z = 0.0
			if absf(to_point.x) + absf(to_point.y) + absf(to_point.z) < 0.5:
				return _branch(obj, ins, true)
			obj.push += to_point.normalized() * minf(o[0], to_point.length() / dt)

		# Paths.
		2:  # follow_path
			_follow_path(obj, o)
		20:  # stop_path
			obj.path = 0
		21:  # path_stop_at (-2 = the current frame)
			obj.path_stop = _s16(o[0] & 0xFFFF)
			if obj.path_stop == -2:
				obj.path_stop = roundi(obj.path_time)
		124:  # path_yaw_offset
			obj.path_yaw_offset = o[0]
		102:  # if_path_done
			return _branch(obj, ins, obj.path == 0)

		# The World's Most Interesting Bomb (not implemented: there's never one).
		165:  # if_no_bomb
			return _branch(obj, ins, true)
		166:  # if_bomb_visible
			return _branch(obj, ins, false)
		167:  # move_to_bomb
			pass

		# Variables and flags.
		65:  # set_var
			_variables(obj, o[0])[clampi(o[1], 0, 3)] = o[2]
		66:  # add_var
			_variables(obj, o[0])[clampi(o[1], 0, 3)] += o[2]
		216:  # add_var_dt
			_variables(obj, o[0])[clampi(o[1], 0, 3)] += o[2] * dt
		67:  # if_var
			return _branch(obj, ins, _compare(_variables(obj, o[0])[clampi(o[1], 0, 3)], o[2]))
		68:  # set_flag
			_set_flags(obj, o[0], _get_flags(obj, o[0]) | (1 << (o[1] & 31)))
		69:  # clear_flag
			_set_flags(obj, o[0], _get_flags(obj, o[0]) & ~(1 << (o[1] & 31)))
		71:  # if_flag_set
			return _branch(obj, ins, _get_flags(obj, o[0]) & (1 << (o[1] & 31)) != 0)
		70:  # toggle_flag
			_set_flags(obj, o[0], _get_flags(obj, o[0]) ^ (1 << (o[1] & 31)))
		72:  # if_flag_clear
			return _branch(obj, ins, _get_flags(obj, o[0]) & (1 << (o[1] & 31)) == 0)
		176:  # if_flag_40000
			return _branch(obj, ins, obj.flags & 0x40000 != 0)
		116:  # flags_set
			obj.flags |= o[0]
		117:  # flags_clear
			obj.flags &= ~o[0]
		232:  # if_option (a cheat toggled option, 1 by default)
			return _branch(obj, ins, o[0] == runtime.option)
		35:  # set_flag148_4
			obj.flags = (obj.flags | 4) if o[0] != 0 else (obj.flags & ~4)
		36:  # set_flag148_2
			obj.flags = (obj.flags | 2) if o[0] != 0 else (obj.flags & ~2)

		# Other objects.
		4:  # command_objects
			_command_objects(obj, o)
		11:  # set_priority
			obj.priority = o[0]
		73:  # set_obey_level
			obj.obey_level = o[0]
		10:  # if_count_objects: objects of a type that this object may command
			var count := 0
			for other in runtime.get_arena_objects(obj):
				if other.type_name.to_upper() == o[0].to_upper() and runtime.may_command(obj, other):
					count += 1
			return _branch(obj, ins, count == o[1])
		119:  # if_count_alive
			var count := 0
			for other in runtime.get_arena_objects(obj):
				if other.type_name.to_upper() == o[0].to_upper() and other.health > 0:
					count += 1
			return _branch(obj, ins, _compare(count, o[1]))
		74:  # attach_to: the object named "<type>_<id>"
			var found: MDKObject = null
			for other in runtime.get_arena_objects(obj):
				if ("%s_%d" % [other.type_name, other.instance_id]).to_upper() == o[2].to_upper():
					found = other
			if found:
				obj.leader = found
				obj.attach_points = Vector2i(o[0], o[1])
				obj.move_command = 74

		175:  # if_inventory (Kurt's inventory isn't implemented: always empty)
			return _branch(obj, ins, _compare(0.0, [o[1], o[2], o[3] if o[3] != null else 0.0]))

		# Triangle groups of the arena.
		98:  # group_set_state
			runtime.level.set_group_state(obj.arena, o[0], o[1])
		140:  # group_set_texture
			runtime.level.set_group_texture(obj.arena, o[0], o[1])
		99:  # group_on_hit
			var state := runtime.get_arena_state(obj.arena)
			state.group_hit_masks[(o[1] - 1) & 15] = o[0]
			state.group_hit_scripts[(o[1] - 1) & 15] = o[2]
		168:  # group_set_hit_flags: 0x80 = destructible (hidden until hit)
			runtime.get_arena_state(obj.arena).group_hit_flags[(o[0] - 1) & 15] = o[1]
			if o[1] & 0x80:
				runtime.level.set_group_state(obj.arena, o[0], 2)
		162:  # arena_counter_set
			runtime.get_arena_state(obj.arena).group_counters[(o[0] - 1) & 15] = o[1]
		163:  # if_arena_counter
			return _branch(obj, ins, _compare(runtime.get_arena_state(obj.arena).group_counters[(o[0] - 1) & 15], o[1]))
		194:  # group_state_near_player: groups around the one under Kurt get the op, the others its opposite
			var floor_group := runtime.get_kurt_floor_group()
			if o[1] > 0 and floor_group >= o[1] and floor_group <= o[2]:
				for group in range(o[1], o[2] + 1):
					var near: bool = group >= floor_group - o[3] and group <= floor_group + o[4]
					var op: int = o[0] if near else o[0] ^ 1
					runtime.level.set_group_state(runtime.current_arena, group, op)

		# Conditions about Kurt, the arena and chance.
		123:  # if_not_in_player_arena
			return _branch(obj, ins, obj.arena != runtime.current_arena)
		222:  # if_opcode_count
			return _branch(obj, ins, _compare(_opcode_count, o[0]))
		231:  # if_move_idle_flag (the movement code's stuck detection isn't implemented)
			return _branch(obj, ins, obj.move_command == 0 and obj.stuck_count != 0)
		236:  # if_no_floor_at: no floor below a point in front of the object
			var offset := Vector2(o[0], o[1]).rotated(deg_to_rad(obj.yaw))
			var depth: float = o[2] if o[2] != 0.0 else 10.0
			var point := obj.mdk_position + Vector3(offset.x, offset.y, 1.0)
			return _branch(obj, ins, runtime.raycast(point, point - Vector3(0, 0, depth + 1.0)).is_empty())
		46:  # find_cover_spot
			runtime.find_cover_spot(obj)
			return _branch(obj, ins, obj.move_command == 43)
		103:  # if_kurt_in_box
			var box := AABB(Vector3(o[0], o[1], o[2]), Vector3(o[3] - o[0], o[4] - o[1], o[5] - o[2]))
			return _branch(obj, ins, box.has_point(runtime.kurt_position))
		115:  # if_wall
			var from := obj.mdk_position + Vector3(0, 0, 2.0 if obj.flags & MDKObject.FLAG_COLLIDES else 0.0)
			var direction: Vector2 = Vector2.from_angle(deg_to_rad(obj.yaw + o[0])) * o[1]
			return _branch(obj, ins, not runtime.raycast(from, from + Vector3(direction.x, direction.y, 0.0)).is_empty())
		121:  # if_floor_below
			return _branch(obj, ins, not runtime.raycast(obj.mdk_position, obj.mdk_position - Vector3(0, 0, o[0])).is_empty())
		96:  # if_kurt_in_rect
			var kurt := runtime.kurt_position
			return _branch(obj, ins, kurt.x >= o[0] and kurt.x <= o[2] and kurt.y >= o[1] and kurt.y <= o[3])
		14, 57:  # if_sees_kurt, if_not_sees_kurt
			var sees := runtime.can_see_kurt(obj, o[0], o[1])
			return _branch(obj, ins, sees if ins.opcode == 14 else not sees)
		45:  # if_target_dist
			return _branch(obj, ins, _compare(obj.distance_to(runtime.target_position), o[0]))
		47:  # if_chance
			return _branch(obj, ins, randi() % 10000 < o[0] * 100.0)
		48:  # if_chance_per_second
			return _branch(obj, ins, randi() % 10000 < dt / maxf(o[0], 0.001) * 10000.0)

		# Sounds.
		89:  # play_sound
			runtime.play_sound(obj, o[2], o[0], o[1])
		107:  # set_loop_sound
			runtime.set_loop_sound(obj, o[0])
		249:  # if_own_sound: mode 0 playing, 1 playing this sound, other: not playing
			var player := obj.get_node_or_null(NodePath("Sound_" + obj.tracked_sound)) as AudioStreamPlayer3D if not obj.tracked_sound.is_empty() else null
			var playing := player != null and player.playing
			var condition := playing
			if o[0] == 1:
				condition = playing and obj.tracked_sound.to_upper() == String(o[2]).to_upper()
			elif o[0] != 0:
				condition = not playing
			return _branch(obj, ins, condition)
		_:
			unimplemented[ins.opcode] = unimplemented.get(ins.opcode, 0) + 1
			if not ins.action.is_empty():
				return _branch(obj, ins, false)
	return ins.next


func _start_move(obj: MDKObject, command: int, destination: Vector3) -> void:
	obj.move_command = command
	obj.move_destination = destination
	# The original plans a detour waypoint around walls (0x45a1dc); objects go straight for now.
	obj.waypoint = destination
	obj.path = 0
	obj.contact_flags &= ~MDKObject.CONTACT_STUCK


## `follow_path`: operands `[path, flags1, flags2, start frame, relative, origin]`.
func _follow_path(obj: MDKObject, o: Array) -> void:
	var path: int = o[0]
	if path == 0:
		obj.path = 0
		return
	var motion := runtime.motion
	obj.flags = obj.flags | 0x200 if o[1] & 1 else obj.flags & ~0x200
	obj.flags = obj.flags | MDKObject.FLAG_PATH_PUSHES if o[1] & 2 else obj.flags & ~MDKObject.FLAG_PATH_PUSHES
	obj.flags = obj.flags | MDKObject.FLAG_PATH_ONCE if o[2] & 1 else obj.flags & ~MDKObject.FLAG_PATH_ONCE
	var time := float(o[3])
	if o[2] & 2:
		# Backwards: start frame 0 means the end of the path.
		obj.path_speed = -1.0
		if o[3] == 0:
			time = motion.path_key_frame(path, motion.path_key_count(path) - 1) - 1
	var origin: Vector3 = obj.mdk_position - motion.path_position(path, time) if o[4] != 0 else Vector3(o[5][0], o[5][1], o[5][2])
	motion.start_path(obj, path, time, origin)


## Aims the yaw and pitch at the target (`aim_target`, `aim_target_inaccurate`), with a random
## error unless `accuracy` is 100.
func _aim(obj: MDKObject, accuracy: float, check_distance: bool) -> void:
	var target := runtime.target_position
	var p := obj.mdk_position
	var horizontal := Vector2(target.x - p.x, target.y - p.y).length()
	if not check_distance or horizontal > 2.0:
		obj.yaw = obj.yaw_to(target)
	obj.pitch = rad_to_deg(atan2(target.z + 3.0 - p.z, horizontal))
	if accuracy != 100.0:
		var distance := obj.distance_to(target) + 0.1
		obj.yaw = fposmod(obj.yaw + (randi() % 20 - 10) * (100.0 - accuracy) / distance, 360.0)
		obj.pitch += (randi() % 20 - 10) * (100.0 - accuracy) / (distance * 4.0)


## Turns towards a point offset from the target in the target's frame (`turn_to_target_offset`,
## and with `z_offset` the pitch too: `turn_to_target_offset3d`).
func _turn_to_target(obj: MDKObject, rate: float, accuracy: float, a: float, b: float, z_offset: Variant) -> void:
	var target := runtime.target_position
	var target_yaw := deg_to_rad(runtime.target_yaw)
	var c := cos(target_yaw)
	var s := sin(target_yaw)
	var point := Vector3(target.x - (a * c + b * s), target.y - (b * c + a * s), target.z)
	var horizontal := Vector2(point.x - obj.mdk_position.x, point.y - obj.mdk_position.y).length()
	var yaw := obj.yaw_to(point)
	if accuracy != 100.0:
		yaw += (randi() % 20 - 10) * (100.0 - accuracy) / (1.0 + horizontal)
	var max_step := rate * dt
	obj.yaw = fposmod(obj.yaw + clampf(wrapf(yaw - obj.yaw, -180.0, 180.0), -max_step, max_step), 360.0)
	if z_offset == null:
		return
	point.z = target.z + z_offset
	var pitch := rad_to_deg(atan2(point.z - obj.mdk_position.z + obj.height_offset, horizontal))
	if accuracy != 100.0:
		pitch += (randi() % 20 - 10) * (100.0 - accuracy) / (1.0 + horizontal * 4.0)
	obj.pitch += clampf(wrapf(pitch - obj.pitch, -180.0, 180.0), -max_step, max_step)


## `command_objects`: operands `[command, command args, selector, selector args]`.
func _command_objects(obj: MDKObject, o: Array) -> void:
	var command: int = o[0]
	var selector: int = o[2]
	var args: Array = o[3]
	var target := 0
	var destination := Vector3()
	if command == 7:
		var action: Array = o[1]
		match action[0]:
			"gosub":
				command = 0xFC
				target = action[1]
			"goto", "gosub_else":
				target = action[1]
			_:
				return
	elif command == 43:
		destination = runtime.near_target_destination(obj, o[1][0], o[1][1])
	var k := 0
	var param := 0.0
	var type_name := ""
	var id := 0
	if selector in [6, 10]:
		param = args[k]
		k += 1
	if selector in [2, 4, 5, 6, 7, 10]:
		type_name = args[k]
		k += 1
	if selector == 5:
		id = args[k]
	runtime.command_objects(obj, command, target, destination, selector, type_name, param, id)

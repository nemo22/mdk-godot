## Runs the level's scripts: arena scripts (for the arena Kurt is in), the objects they spawn and the
## aliens placed by the DTI. Scripts run at the original's 30 ticks per second.
class_name MDKScriptRuntime
extends Node3D

const TICK := 1.0 / 30.0
## Flags of objects spawned by `spawn_flagged` and of projectiles (`fire`).
const SPAWN_FLAGGED_FLAGS := 0x2008A6
const PROJECTILE_FLAGS := 0x80820
## Flag of objects that keep running when Kurt is in another arena.
const FLAG_ALWAYS_ACTIVE := 0x200000


## Per arena script state (the arena's embedded object).
class ArenaState:
	var name := ""
	var controller: MDKObject
	var variables := [0.0, 0.0, 0.0, 0.0]
	var flags := 0
	var started := false


var level: Level
var kurt: Kurt
var vm: MDKScriptVM
var motion: MDKObjectMotion
var global_variables := [0.0, 0.0, 0.0, 0.0]
var global_flags := 0
## Kurt's position (MDK coordinates) and the target of alien scripts (Kurt, or a decoy).
var kurt_position := Vector3()
var target_position := Vector3()
## Yaw of the target (degrees, MDK convention).
var target_yaw := 0.0
## Option toggled by cheat codes (`if_option`, the original's `0x5742dc`), 1 by default.
var option := 1
var current_arena := ""
var objects: Array[MDKObject] = []

var _arenas := {}
var _animations := {}
var _resolvers := {}
var _next_instance := 1000
var _time := 0.0
var _tick_usec := 0
var _tick_count := 0


func setup(p_level: Level, p_kurt: Kurt) -> void:
	level = p_level
	kurt = p_kurt
	vm = MDKScriptVM.new(self, MDKScriptDecoder.new(level.cmi.bytes))
	motion = MDKObjectMotion.new(self)


func get_arena_state(arena_name: String) -> ArenaState:
	if not _arenas.has(arena_name):
		var state := ArenaState.new()
		state.name = arena_name
		state.controller = MDKObject.new()
		state.controller.name = "Arena_" + arena_name
		state.controller.arena = arena_name
		state.controller.restart = level.cmi.arena_scripts.get(arena_name, 0)
		_arenas[arena_name] = state
	return _arenas[arena_name]


func _exit_tree() -> void:
	if motion:
		motion.free_probe()


## Converts a Godot position to MDK coordinates.
static func to_mdk(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


func _physics_process(delta: float) -> void:
	if not level:
		return
	_time += delta
	while _time >= TICK:
		_time -= TICK
		var start := Time.get_ticks_usec()
		_tick()
		_tick_usec += Time.get_ticks_usec() - start
		_tick_count += 1


## Average duration of a script tick, in milliseconds (for profiling).
func average_tick_ms() -> float:
	if not vm:
		return 0.0
	return _tick_usec / 1000.0 / maxi(_tick_count, 1)


func _tick() -> void:
	kurt_position = to_mdk(kurt.global_position)
	target_position = kurt_position
	# Kurt's yaw 0 faces -Z (Godot) = +Y (MDK).
	target_yaw = fposmod(90.0 + rad_to_deg(kurt.yaw), 360.0)
	var arena_name := level.get_arena_at(kurt.global_position)
	if not arena_name.is_empty() and arena_name != current_arena:
		current_arena = arena_name
		var state := get_arena_state(arena_name)
		if not state.started:
			state.started = true
			_spawn_dti_aliens(arena_name)
	if not current_arena.is_empty():
		vm.run(get_arena_state(current_arena).controller)
	for obj in objects.duplicate():
		if obj.dead or (obj.arena != current_arena and not obj.flags & FLAG_ALWAYS_ACTIVE):
			continue
		vm.run(obj)
		if not obj.dead:
			motion.update(obj)


## Spawns the aliens placed by the DTI records of type 2 (`ARENA$TYPE_n` scripts).
func _spawn_dti_aliens(arena_name: String) -> void:
	for entry in level.dti.arenas:
		if entry.name != arena_name:
			continue
		for record: Dictionary in entry.records:
			if record.type != 2:
				continue
			var key := "%s$%s_%d" % [arena_name, record.name, record.id]
			var controller := get_arena_state(arena_name).controller
			spawn(controller, record.name, record.position, record.angle, record.id, level.cmi.alien_scripts.get(key, 0), false)


## Spawns an object of type `type_name` in `parent`'s arena. Returns `null` if the type is unknown.
func spawn(parent: MDKObject, type_name: String, mdk_position: Vector3, yaw: float, instance: int, script: int, flagged: bool) -> MDKObject:
	var model := _find_model(parent.arena, type_name)
	if not model:
		return null
	var obj := MDKObject.new()
	obj.arena = parent.arena
	obj.setup(type_name, model, _get_resolver(parent.arena))
	obj.instance_id = instance if instance >= 0 else _next_instance
	if instance < 0:
		_next_instance += 1
	obj.mdk_position = mdk_position
	obj.spawn_position = mdk_position
	obj.previous_position = mdk_position
	obj.yaw = fposmod(yaw, 360.0)
	obj.update_transform()
	if flagged:
		obj.flags = SPAWN_FLAGGED_FLAGS
	add_child(obj)
	objects.push_back(obj)
	# The object type's init script runs once at creation.
	var init_script: int = level.cmi.object_scripts.get("%s$%s" % [parent.arena, type_name], 0)
	if init_script:
		obj.restart = init_script
		vm.run(obj)
	obj.restart = script
	return obj


func remove(obj: MDKObject) -> void:
	obj.dead = true
	objects.erase(obj)
	obj.queue_free()


## Kills an object (`object_kill`): it switches to its death script if it has one, otherwise it's
## removed (the original explodes it).
func kill(obj: MDKObject) -> void:
	obj.health = 0
	if obj.death_script:
		obj.move_command = 0
		obj.restart = obj.death_script
		obj.wait_time = 0.0
		obj.wait_resume = obj.death_script
		obj.death_script = 0
	else:
		remove(obj)


## An object fell far below its arena (0x43d884): it switches to its death script, put back
## above the floor, or it's removed.
func fall_out(obj: MDKObject) -> void:
	if not obj.death_script:
		remove(obj)
		return
	kill(obj)
	obj.velocity.z = 0.0
	obj.mdk_position.z = get_arena_floor(obj.arena) - 150.0
	obj.flags &= ~MDKObject.FLAG_GRAVITY


## Fires a projectile (`fire`): the global model `bullet_name` starts at a reference point of `obj`
## (`origin` = `[0, index]`) or at the centre of one of its parts (`[1, name]`), flying along the
## object's yaw and pitch, and runs `script`.
func fire(obj: MDKObject, origin: Array, bullet_name: String, script: int) -> MDKObject:
	var start := obj.get_reference_point(origin[1]) if origin[0] == 0 else obj.get_part_center(obj.find_part(origin[1]))
	var bullet := spawn(obj, bullet_name, start, obj.yaw, -1, 0, false)
	if not bullet:
		return null
	bullet.move_command = 61
	bullet.flags |= PROJECTILE_FLAGS
	bullet.pitch = obj.pitch
	bullet.restart = script
	bullet.update_transform()
	return bullet


func hurt_kurt(damage: int) -> void:
	kurt.hurt(damage)


## Kurt's bounding box (MDK coordinates).
func get_kurt_box() -> AABB:
	return AABB(kurt_position - Vector3(0.6, 0.6, 0.0), Vector3(1.2, 1.2, 5.0))


## Lowest point (MDK Z) of an arena's geometry.
func get_arena_floor(arena_name: String) -> float:
	var bounds: Variant = level.arena_bounds.get(arena_name)
	return bounds.position.y if bounds else -1000.0


## Casts a ray against the level geometry (MDK coordinates). Returns the hit as by `intersect_ray`
## (Godot coordinates), or an empty dictionary.
func raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(MDKMeshBuilder.to_godot(from), MDKMeshBuilder.to_godot(to))
	query.exclude = [kurt.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Destination near the target (`move_near_target`): the target position offset by `forward` and
## `side` × 1% of the distance, in the frame of the direction from `obj` to the target.
func near_target_destination(obj: MDKObject, forward: float, side: float) -> Vector3:
	var p := obj.mdk_position
	var direction := Vector2(target_position.x - p.x, target_position.y - p.y).angle()
	var offset := Vector2(forward, side).rotated(direction) * 0.01 * obj.distance_to(target_position)
	return Vector3(target_position.x + offset.x, target_position.y + offset.y, target_position.z + obj.height_offset)


## Whether `sender` may command `receiver` (`command_objects`, `if_count_objects`): the receiver
## has no other leader of a higher priority, and obeys the sender's priority.
static func may_command(sender: MDKObject, receiver: MDKObject) -> bool:
	var leader := receiver.leader
	if leader and leader != sender and not leader.dead and sender.priority <= leader.priority:
		return false
	return receiver.obey_level >= sender.priority


## Sends a command to objects (`command_objects` 0x440384). Commands: 1 join a formation around the
## sender, 7 goto `target`, 0xFC gosub `target`, 43 go to `destination`. Selectors: 2 all of
## `type_name`, 3 all, 4 the first of `type_name`, 5 of `type_name` with instance `id`, 6 of
## `type_name` within `param` with a line of sight, 7 of `type_name` following the sender, 8 all
## following the sender, 9 the linked object, 10 of `type_name` with Y >= `param`.
func command_objects(sender: MDKObject, command: int, target: int, destination: Vector3, selector: int, type_name: String, param: float, id: int) -> void:
	var formation_index := 0
	if selector == 9:
		if sender.linked and not sender.linked.dead:
			_command_object(sender, sender.linked, command, target, destination, formation_index)
		return
	for receiver in get_arena_objects(sender):
		if selector not in [3, 8] and receiver.type_name.to_upper() != type_name.to_upper():
			continue
		if not may_command(sender, receiver):
			continue
		if selector in [7, 8] and receiver.leader != sender:
			continue
		if selector == 5 and receiver.instance_id != id:
			continue
		if selector == 6:
			if sender.distance_to(receiver.mdk_position) > param:
				continue
			if not raycast(sender.mdk_position + Vector3(0, 0, 8), receiver.mdk_position + Vector3(0, 0, 8)).is_empty():
				continue
		if selector == 10 and receiver.mdk_position.y < param:
			continue
		if (command == 7 and receiver.command_target == target) or receiver.health == 0:
			continue
		if _command_object(sender, receiver, command, target, destination, formation_index):
			formation_index += 1
		if selector == 4:
			return


## Applies a command to one object (0x4405d0). Returns true when it joined a formation.
func _command_object(sender: MDKObject, receiver: MDKObject, command: int, target: int, destination: Vector3, formation_index: int) -> bool:
	match command:
		1:
			# Formation places alternate left and right, 5 units apart (wider for XE).
			var wide := receiver.type_name.to_upper() == "XE"
			var spread := 4.0 if wide else 1.0
			var back := 2.5 if wide else 1.0
			var side := 1.0 if formation_index & 1 else -1.0
			receiver.waypoint = Vector3(side * (formation_index / 2 + 1) * 5.0 * spread, back * -4.0, 8.0)
			receiver.move_destination = MDKObjectMotion.formation_position(sender, receiver.waypoint)
			receiver.leader = sender
			receiver.move_command = 1
			receiver.path = 0
			return true
		7:
			receiver.wait_time = 0.0
			receiver.restart = target
			receiver.wait_resume = target
			receiver.leader = sender
			receiver.gosub_returns.clear()
			receiver.gosub_restarts.clear()
			receiver.level_timers[0] = 0.0
			receiver.command_target = target
		0xFC:
			if receiver.gosub_returns.size() < MDKScriptVM.GOSUB_DEPTH:
				receiver.gosub_returns.push_back(receiver.restart)
				receiver.gosub_restarts.push_back(receiver.restart)
				receiver.wait_time = 0.0
				receiver.restart = target
				receiver.wait_resume = target
				receiver.leader = sender
				receiver.level_timers[receiver.gosub_returns.size()] = 0.0
		43:
			if receiver.arena == current_arena:
				receiver.move_destination = destination
				receiver.waypoint = destination
				receiver.leader = sender
				receiver.move_command = 43
				receiver.path = 0
				receiver.contact_flags &= ~MDKObject.CONTACT_STUCK
	return false


## World bounds (MDK) of an object's model, turned by its yaw.
func get_world_bounds(obj: MDKObject) -> AABB:
	if not obj.model:
		return AABB(obj.mdk_position, Vector3.ZERO)
	var bounds := obj.model.bounds
	var out := AABB(obj.mdk_position, Vector3.ZERO)
	for i in 8:
		var corner := (bounds.get_endpoint(i) * obj.model_scale).rotated(Vector3.BACK, deg_to_rad(obj.yaw))
		out = out.expand(obj.mdk_position + corner)
	return out


## Objects of the arena of `obj`, alive, other than `obj` (for commands and counts).
func get_arena_objects(obj: MDKObject) -> Array[MDKObject]:
	var out: Array[MDKObject] = []
	for other in objects:
		if other != obj and not other.dead and other.arena == obj.arena:
			out.push_back(other)
	return out


## Returns the animation referenced by a script operand: an animation stored in the CMI file, or
## (when its first `u32` is 0) the arena animation named after it.
func get_animation(obj: MDKObject, offset: int) -> MDKModelAnimation:
	if offset == 0:
		return null
	var bytes := level.cmi.bytes
	if bytes.decode_u32(offset) == 0:
		var animation_name := bytes.slice(offset + 4, offset + 12).get_string_from_ascii()
		var arena := level.mto.get_arena(obj.arena) if level.mto.arena_offsets.has(obj.arena) else null
		return arena.animations.get(animation_name) if arena else null
	if not _animations.has(offset):
		_animations[offset] = MDKModelAnimation.parse("CMI_%x" % offset, bytes, offset)
	return _animations[offset]


func _find_model(arena_name: String, type_name: String) -> MDKModel:
	var model := level.cmi.get_model(type_name)
	if model:
		return model
	if level.mto.arena_offsets.has(arena_name):
		return level.mto.get_arena(arena_name).models.get(type_name)
	return null


func _get_resolver(arena_name: String) -> MDKMeshBuilder.MaterialResolver:
	if not _resolvers.has(arena_name):
		var arena := level.mto.get_arena(arena_name) if level.mto.arena_offsets.has(arena_name) else null
		var palette := level.dti.palette.with_arena_colors(arena.palette_rgb) if arena else level.dti.palette
		var archives: Array[MDKTextureArchive] = [level.level_textures]
		if arena:
			archives.push_front(arena.textures)
		_resolvers[arena_name] = MDKMeshBuilder.MaterialResolver.new(palette, archives)
	return _resolvers[arena_name]


## `can_see_kurt`: Kurt within `range`, inside a cone around the object's yaw, with a clear line of
## sight. The cone's exact formula isn't reverse engineered; `cone` is used as a half angle in degrees.
func can_see_kurt(obj: MDKObject, range: float, cone: float) -> bool:
	if obj.distance_to(kurt_position) > range:
		return false
	if cone < 180.0 and absf(wrapf(obj.yaw_to(kurt_position) - obj.yaw, -180.0, 180.0)) > maxf(cone, 10.0):
		return false
	return raycast(obj.mdk_position + Vector3(0, 0, 5), kurt_position + Vector3(0, 0, 4)).is_empty()


## `play_sound`: plays a sound at the object (3D) or without position (flag 0x80). `flags & 3`:
## 0 play, 1 restart, 2 play unless it's already playing, 3 stop.
func play_sound(obj: MDKObject, sound_name: String, flags: int, _position: Variant) -> void:
	var mode := flags & 3
	var existing := obj.get_node_or_null(NodePath("Sound_" + sound_name))
	if existing:
		if mode == 2 and existing.playing:
			return
		if mode == 3 or mode == 1:
			existing.stop()
			if mode == 3:
				return
		existing.play()
		return
	if mode == 3:
		return
	var stream := level.get_sound(sound_name)
	if not stream:
		return
	var player: Node
	if flags & 0x80:
		player = AudioStreamPlayer.new()
	else:
		player = AudioStreamPlayer3D.new()
		player.unit_size = 50.0
	player.name = "Sound_" + sound_name
	player.stream = stream
	obj.add_child(player)
	player.play()

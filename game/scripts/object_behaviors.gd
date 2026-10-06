## Built-in behaviours of some kinds of objects, run by the engine besides their scripts (the object
## update loop 0x43c7dc): doors (flag 0x100000, 0x43cc68) and pickups (flag 0x200000, 0x43daf4).
## See `docs/engine.md`.
class_name MDKObjectBehaviors
extends RefCounted

# Door states (`obj+0x312`): the low 4 bits are set by the engine, the others by `door_set_flags`.
const DOOR_OPEN := 0x1
const DOOR_OPENING := 0x2
const DOOR_CLOSING := 0x4
const DOOR_CLOSED := 0x8
## The door is not solid while open (object flag 0x10).
const DOOR_OPEN_NOT_SOLID := 0x10
const DOOR_STAYS_OPEN := 0x20
const DOOR_LOCKED := 0x40
const DOOR_LOCK_HIDDEN := 0x100
## A door moved to its other side turns around (0x43ca00).
const DOOR_TURN := 180.0
const FULL_TURN := 360.0

## Falling pickups open a chute at this speed.
const PICKUP_CHUTE_SPEED := -15.0
const PICKUP_TURN_SPEED := 180.0
## Pickups float this high once they've landed.
const PICKUP_HOVER := 1.5
## The pickup that runs away (0x43daf4): it starts within 20 units, stops beyond √1000 (across),
## runs at 40 units/s and turns at 270°/s; idle it replays its animation with a chance of 72 in
## 32768 per tick.
const RUNNER := "SW_H150"
const RUNNER_START := 20.0
const RUNNER_STOP_SQUARED := 1000.0
const RUNNER_SPEED := 40.0
const RUNNER_TURN := 270.0
const RUNNER_IDLE_CHANCE := 72
## The holy cow (0x440074): 50 units/s towards its target, 1000 damage to objects, 10 to Kurt, a
## blast hit (event −3, type −4).
const COW_SPEED := 50.0
const COW_DAMAGE := 1000
const COW_KURT_DAMAGE := 10
const COW_HIT_EVENT := -3
const COW_HIT_TYPE := -4

var runtime: MDKScriptRuntime
var dt := 1.0 / 30.0


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime


## Opens the door when Kurt comes closer than `door_distance`, closes it when he goes away.
func update_door(obj: MDKObject) -> void:
	# A door seen from its other side moves into Kurt's arena (0x43cc68), so it stays live, solid
	# and drawn there after the arena behind it is put away.
	if obj.arena != runtime.current_arena and obj.connects == runtime.current_arena:
		move_door(obj)
	var state := obj.door_state
	if state & DOOR_OPENING:
		if obj.is_animation_done():
			state = (state & 0x70) | DOOR_OPEN
			_play(obj, obj.door_sounds[2])
	elif state & DOOR_CLOSING and obj.is_animation_done():
		state = (state & 0xF0) | DOOR_CLOSED
		_play(obj, obj.door_sounds[3])
		# The arena behind it goes.
		runtime.show_arena("")
	if obj.distance_to(runtime.kurt_position) >= obj.door_distance:
		if not state & (DOOR_CLOSING | DOOR_CLOSED | DOOR_STAYS_OPEN):
			obj.restart_animation(runtime.get_animation(obj, obj.door_animations[1]), false)
			state = (state & 0xF0) | DOOR_CLOSING
			_play(obj, obj.door_sounds[1])
	elif not state & (DOOR_OPEN | DOOR_OPENING | DOOR_LOCKED):
		obj.restart_animation(runtime.get_animation(obj, obj.door_animations[0]), false)
		state = (state & 0xF0) | DOOR_OPENING
		_play(obj, obj.door_sounds[0])
		_show_behind(obj)
	obj.door_state = state
	# Parts named `LOCK` show a locked, closed door; parts named `HC…` are hidden while it's closed.
	var hidden := obj.hidden_parts
	if not state & DOOR_CLOSED:
		hidden = (hidden | obj.lock_parts) & ~obj.hatch_parts
	else:
		hidden |= obj.hatch_parts
		if state & DOOR_LOCKED and not state & DOOR_LOCK_HIDDEN:
			hidden &= ~obj.lock_parts
		else:
			hidden |= obj.lock_parts
	obj.set_hidden_parts(hidden)
	if state & DOOR_OPEN_NOT_SOLID:
		if state & DOOR_OPEN:
			obj.flags |= MDKObject.FLAG_NOT_SOLID
		else:
			obj.flags &= ~MDKObject.FLAG_NOT_SOLID


## Moves a door into the arena on its other side, turned around (0x43ca00): e.g. the door
## CDANT_1 → DANT_2 at yaw 90 becomes DANT_2 → CDANT_1 at yaw 270.
static func move_door(door: MDKObject) -> void:
	var arena := door.arena
	door.arena = door.connects
	door.connects = arena
	door.yaw += DOOR_TURN
	if door.yaw >= FULL_TURN:
		door.yaw -= FULL_TURN


## Sets up a new door (`spawn_connector`): masks of its `LOCK` and `HC…` parts.
func setup_door(obj: MDKObject) -> void:
	# New doors are closed (0x45cdec, spawn flag 1); starting mid-way they'd close and hide the arena behind.
	obj.door_state = DOOR_CLOSED
	obj.lock_parts = 0
	obj.hatch_parts = 0
	if not obj.model:
		return
	for i in obj.model.parts.size():
		var part_name := obj.model.parts[i].name
		if part_name == "LOCK":
			obj.lock_parts |= 1 << i
		elif part_name.begins_with("HC"):
			obj.hatch_parts |= 1 << i


## Pickups fall with a chute, then float and spin; taken ones shrink away in 30 ticks.
func update_pickup(obj: MDKObject) -> void:
	if obj.flags & MDKObject.FLAG_COLLECTED:
		obj.parameter_timer -= 1.0
		obj.model_scale = maxf(obj.parameter_timer / 30.0, 0.0)
		obj.yaw = fposmod(obj.yaw + dt * PICKUP_TURN_SPEED * 4.0, 360.0)
		if obj.parameter_timer <= 0.0:
			runtime.remove(obj)
		return
	if obj.flags & (MDKObject.FLAG_GRAVITY | MDKObject.FLAG_LANDED) == MDKObject.FLAG_GRAVITY:
		if obj.contact_flags & MDKObject.CONTACT_FLOOR:
			# `SW_H150` stands on the floor, the others float.
			var hover := 0.0 if obj.type_name == RUNNER else PICKUP_HOVER
			obj.height_offset = hover
			obj.flags |= MDKObject.FLAG_LANDED
			obj.mdk_position.z += hover
		elif obj.velocity.z < PICKUP_CHUTE_SPEED:
			obj.velocity.z = PICKUP_CHUTE_SPEED
			if not obj.attached:
				var chute := runtime.spawn(obj, "SW_CHUTE", obj.mdk_position, obj.yaw, -1, 0, false)
				if chute:
					chute.flags = 0x820
					chute.leader = obj
					chute.attach_points = Vector2i(0, 0)
					chute.move_command = 74
					obj.attached = chute
		return
	# The chute shrinks away once the pickup has landed.
	var chute := obj.attached
	if chute and chute.model_scale > 0.2:
		chute.model_scale -= dt
		if chute.model_scale <= 0.2:
			runtime.remove(chute)
			obj.attached = null
	if obj.type_name == RUNNER and not obj.attached:
		_update_runner(obj)
	if obj.type_name not in ["SW_H150", "SW_SEAL", "SW_SBONE"]:
		obj.yaw = fposmod(obj.yaw + dt * PICKUP_TURN_SPEED, 360.0)


## `SW_H150` runs away (0x43daf4): when Kurt comes within 20 units it plays `H150_R` and runs at
## 40 units/s, turning away from him at up to 270°/s, until he's 31.6 units away (across); idle, it
## plays `H150_I` now and then (about every 15 s).
##
##   IDLE ──(Kurt within 20)──▶ RUN ──(Kurt beyond 31.6)──▶ IDLE
func _update_runner(obj: MDKObject) -> void:
	var run := runtime.items.get_animation("H150_R")
	var kurt := runtime.kurt_position
	if obj.animation != run:
		if (not obj.animation or obj.is_animation_done()) and randi() % 32768 < RUNNER_IDLE_CHANCE:
			obj.restart_animation(runtime.items.get_animation("H150_I"), false)
			return
		if obj.mdk_position.distance_squared_to(kurt) < RUNNER_START * RUNNER_START:
			obj.restart_animation(run, true)
			runtime.mixer.play("RUNNER", SoundMixer.Start.ONCE)
		return

	var ahead := Vector2.from_angle(deg_to_rad(obj.yaw)) * RUNNER_SPEED
	obj.push.x += ahead.x
	obj.push.y += ahead.y
	var away := rad_to_deg(atan2(kurt.y - obj.mdk_position.y, kurt.x - obj.mdk_position.x)) + 180.0
	var turn := clampf(wrapf(away - obj.yaw, -180.0, 180.0), -RUNNER_TURN * dt, RUNNER_TURN * dt)
	obj.yaw = fposmod(obj.yaw + turn, 360.0)
	obj.flags |= MDKObject.FLAG_GRAVITY
	if Vector2(kurt.x - obj.mdk_position.x, kurt.y - obj.mdk_position.y).length_squared() > RUNNER_STOP_SQUARED:
		obj.restart_animation(runtime.items.get_animation("H150_I"), false)


## The holy cow (0x440074): falling, it slides towards its target at 50 units/s on each axis and
## hits once what it lands on (1000 damage to objects, 10 to Kurt); it blows up 0.5 s after landing.
func update_cow(obj: MDKObject) -> void:
	var target := obj.cow_target.mdk_position if obj.cow_target and not obj.cow_target.dead else runtime.kurt_position
	var landed := obj.contact_flags & MDKObject.CONTACT_FLOOR != 0
	if not obj.flags & MDKObject.FLAG_NOT_TARGET:
		_cow_hits(obj)
		if not landed:
			obj.mdk_position.x = move_toward(obj.mdk_position.x, target.x, COW_SPEED * dt)
			obj.mdk_position.y = move_toward(obj.mdk_position.y, target.y, COW_SPEED * dt)
	if not landed:
		return
	obj.flags |= MDKObject.FLAG_NOT_TARGET
	obj.parameter_timer -= dt
	if obj.parameter_timer < 0.0:
		runtime.kill(obj)


## What the cow overlaps: objects of its arena lose 1000 health (a blast hit), Kurt 10.
func _cow_hits(obj: MDKObject) -> void:
	var bounds := runtime.get_world_bounds(obj)
	var hit := false
	for other in runtime.objects.duplicate():
		if other == obj or other.dead or other.arena != obj.arena or other.flags & (MDKObject.FLAG_NOT_TARGET | MDKObject.FLAG_NOT_SOLID_2):
			continue
		if not bounds.intersects(runtime.get_world_bounds(other)):
			continue
		hit = true
		other.hit_event = COW_HIT_EVENT
		other.hit_type = COW_HIT_TYPE
		if other.health < 65000:
			other.health -= COW_DAMAGE
			if other.health <= 0:
				runtime.kill(other)
	if bounds.intersects(runtime.get_kurt_box()):
		hit = true
		runtime.hurt_kurt(COW_KURT_DAMAGE)
	if hit:
		obj.flags |= MDKObject.FLAG_NOT_TARGET


## An opening door shows the arena behind it (0x43cc68): its other side, or its own arena, whichever
## is neither Kurt's nor already the active second arena.
func _show_behind(obj: MDKObject) -> void:
	for side: String in [obj.connects, obj.arena]:
		if not side.is_empty() and side != runtime.current_arena and not (runtime.second_active and side == runtime.second_arena):
			runtime.show_arena(side)
			return


func _play(obj: MDKObject, sound_name: String) -> void:
	if not sound_name.is_empty() and sound_name != "NONE":
		runtime.play_sound(obj, sound_name, 0, null)

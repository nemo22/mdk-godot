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

## Falling pickups open a chute at this speed.
const PICKUP_CHUTE_SPEED := -15.0
const PICKUP_TURN_SPEED := 180.0
## Pickups float this high once they've landed.
const PICKUP_HOVER := 1.5

var runtime: MDKScriptRuntime
var dt := 1.0 / 30.0


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime


## Opens the door when Kurt comes closer than `door_distance`, closes it when he goes away.
func update_door(obj: MDKObject) -> void:
	var state := obj.door_state
	if state & DOOR_OPENING:
		if obj.is_animation_done():
			state = (state & 0x70) | DOOR_OPEN
			_play(obj, obj.door_sounds[2])
	elif state & DOOR_CLOSING and obj.is_animation_done():
		state = (state & 0xF0) | DOOR_CLOSED
		_play(obj, obj.door_sounds[3])
	if obj.distance_to(runtime.kurt_position) >= obj.door_distance:
		if not state & (DOOR_CLOSING | DOOR_CLOSED | DOOR_STAYS_OPEN):
			obj.restart_animation(runtime.get_animation(obj, obj.door_animations[1]), false)
			state = (state & 0xF0) | DOOR_CLOSING
			_play(obj, obj.door_sounds[1])
	elif not state & (DOOR_OPEN | DOOR_OPENING | DOOR_LOCKED):
		obj.restart_animation(runtime.get_animation(obj, obj.door_animations[0]), false)
		state = (state & 0xF0) | DOOR_OPENING
		_play(obj, obj.door_sounds[0])
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


## Sets up a new door (`spawn_connector`): masks of its `LOCK` and `HC…` parts.
func setup_door(obj: MDKObject) -> void:
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
			obj.height_offset = PICKUP_HOVER
			obj.flags |= MDKObject.FLAG_LANDED
			obj.mdk_position.z += PICKUP_HOVER
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
	if obj.type_name not in ["SW_H150", "SW_SEAL", "SW_SBONE"]:
		obj.yaw = fposmod(obj.yaw + dt * PICKUP_TURN_SPEED, 360.0)


func _play(obj: MDKObject, sound_name: String) -> void:
	if not sound_name.is_empty() and sound_name != "NONE":
		runtime.play_sound(obj, sound_name, 0, null)

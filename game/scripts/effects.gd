## Sprite effects of the arenas (the original's pool of 96 effects, `arena+0x5c`): slime bleeding
## from wounds (`attach_effect` 128), slime drops (`spawn_debris` 136) and bubbles
## (`spawn_effect` 132).
##
## Sprites are animated textures of the level drawn as billboards `width × scale / 256` units wide
## (0x407048); frame `F − 1 − (life × speed mod F)`, so they play forwards as their life runs out.
class_name MDKEffects
extends Node3D

enum Kind { WOUND, DROP, BUBBLE, POP }

## Most effects alive at once.
const MAX_EFFECTS := 96
## Gravity of the drops, units per tick² (about 64 units/s²).
const GRAVITY := 0.284444 * 0.25
const BOUNCE := 1.4
const BOUNCE_TICKS := 20
## A wound spits drops for this many ticks at a time.
const BURST_TICKS := 30


class Effect:
	var kind := Kind.DROP
	var sprite: Sprite3D
	var frames := 1
	var position := Vector3()
	## Units per tick.
	var velocity := Vector3()
	var scale := 1.0
	## Frames per tick.
	var speed := 0.5
	var life := 0.0
	# Wounds: the object, the point it bleeds at, the point the drops fly towards, the chance of a
	# burst (out of 32768) and the burst's time left and jitter.
	var owner: MDKObject
	var slot := 0
	var towards := 0
	var intensity := 0x7fff
	var burst := 0.0
	var jitter := Vector3()
	var done := false


var runtime: MDKScriptRuntime
var _effects: Array[Effect] = []
## Sprite sheets by texture name (per palette): `[texture, width, frames]`.
var _sheets := {}


## Starts the bleeding of a wound at the object's reference point `slot` (0x4067b8): an `SL_BIG`
## blob (2.5 units, looping at 15 fps) that squirts drops towards the point `towards`.
func attach(obj: MDKObject, slot: int, towards: int) -> void:
	if obj.wounds.has(slot):
		return
	var effect := _create(obj.arena, "SL_BIG", Kind.WOUND, obj.get_reference_point(slot), 10.0, 0.5)
	if not effect:
		return
	effect.owner = obj
	effect.slot = slot
	effect.towards = towards
	effect.life = effect.frames * 2 - 1
	obj.wounds[slot] = effect


## Stops the bleeding at a reference point (`attach_effect "OFF"`, 0x405250).
func detach(obj: MDKObject, slot: int) -> void:
	var effect: Effect = obj.wounds.get(slot)
	if effect:
		_remove(effect)


## A slime drop (0x406b3c): `SL_MED` or `SL_SMA`, playing once over 4 seconds.
func spawn_drop(arena_name: String, point: Vector3, velocity: Vector3, scale: float) -> void:
	var effect := _create(arena_name, "SL_MED" if randi() & 1 == 0 else "SL_SMA", Kind.DROP, point, scale, 0.25)
	if effect:
		effect.velocity = velocity
		effect.life = effect.frames * 4 - 1


## A bubble (0x406434): `BUBB`, rising, growing and wobbling, then popping.
func spawn_bubble(arena_name: String, point: Vector3) -> void:
	var effect := _create(arena_name, "BUBB", Kind.BUBBLE, point, (randi() % 32768 - 0x4000) * 0.0002 + 10.0, 0.5)
	if effect:
		effect.life = 64


func _create(arena_name: String, texture_name: String, kind: Kind, point: Vector3, scale: float, speed: float) -> Effect:
	if _effects.size() >= MAX_EFFECTS:
		return null
	var sheet := _get_sheet(arena_name, texture_name)
	if sheet.is_empty():
		return null
	var effect := Effect.new()
	effect.kind = kind
	effect.position = point
	effect.scale = scale
	effect.speed = speed
	effect.frames = sheet[2]
	effect.sprite = Sprite3D.new()
	effect.sprite.texture = sheet[0]
	effect.sprite.vframes = effect.frames
	effect.sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	effect.sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	effect.sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(effect.sprite)
	_effects.push_back(effect)
	_place(effect)
	return effect


func _get_sheet(arena_name: String, texture_name: String) -> Array:
	var resolver := runtime.get_resolver(arena_name)
	var key := "%s/%d" % [texture_name, resolver.palette.get_instance_id()]
	if not _sheets.has(key):
		var texture := resolver.find_texture(texture_name)
		if not texture:
			_sheets[key] = []
		else:
			var image := resolver.palette.make_image(texture.width, texture.height * texture.frame_count, texture.indices, true)
			_sheets[key] = [ImageTexture.create_from_image(image), texture.width, texture.frame_count]
	return _sheets[key]


func _remove(effect: Effect) -> void:
	if effect.owner and is_instance_valid(effect.owner) and effect.owner.wounds.get(effect.slot) == effect:
		effect.owner.wounds.erase(effect.slot)
	effect.sprite.queue_free()
	_effects.erase(effect)


## Updates the effects by a tick.
func update(ticks: float) -> void:
	var dt := ticks / 30.0
	for effect in _effects.duplicate():
		match effect.kind:
			Kind.WOUND:
				_update_wound(effect, ticks)
			Kind.DROP:
				_move(effect, ticks)
				effect.life -= ticks
			Kind.BUBBLE:
				effect.velocity += Vector3((randi() % 32768 - 0x4000) * 1e-4 * dt, (randi() % 32768 - 0x4000) * 1e-4 * dt, dt * 0.5)
				effect.scale += 4.0 * dt
				if _move(effect, ticks):
					effect.life = 0.0
				effect.life -= ticks
				if effect.life < 1.0:
					# The bubble pops (`BUBB_POP`).
					var sheet := _get_sheet(runtime.current_arena, "BUBB_POP")
					if not sheet.is_empty():
						effect.kind = Kind.POP
						effect.frames = sheet[2]
						effect.sprite.texture = sheet[0]
						effect.sprite.vframes = effect.frames
						effect.velocity = Vector3.ZERO
						effect.life = effect.frames * 2 - 1
			Kind.POP:
				effect.life -= ticks
		if effect.done or effect.life <= 0.0 and effect.kind != Kind.WOUND:
			_remove(effect)
		elif effect in _effects:
			_place(effect)


## A wound (0x40690c): the blob loops forever, weaker every loop; now and then it squirts a burst of
## drops (one per update for 30 ticks) towards the second point, at half a unit per tick.
func _update_wound(effect: Effect, ticks: float) -> void:
	var obj := effect.owner
	if not is_instance_valid(obj) or obj.dead:
		effect.done = true
		return
	effect.life -= ticks
	if effect.life < 0.0:
		effect.life = effect.frames * 2 - 1
		effect.intensity = maxi(effect.intensity - ((randi() & 0x7f) + 0x80), 0)
	effect.position = obj.get_reference_point(effect.slot)
	if effect.burst < 1.0 and randi() % 32768 < effect.intensity:
		effect.burst = BURST_TICKS
		effect.jitter = Vector3(randi() % 32768 - 0x4000, randi() % 32768 - 0x4000, randi() % 32768 - 0x4000) / 65536.0
	if effect.burst > 0.0:
		effect.burst -= ticks
		var direction := (obj.get_reference_point(effect.towards) - effect.position).normalized()
		spawn_drop(obj.arena, effect.position, (direction + effect.jitter) * 0.5, 4.0)


## Moves an effect by its velocity (0x4061d8); drops fall and bounce off the arena. Returns whether
## it hit something.
func _move(effect: Effect, ticks: float) -> bool:
	var motion := effect.velocity * ticks
	if motion == Vector3.ZERO:
		return false
	var query := PhysicsRayQueryParameters3D.create(MDKMeshBuilder.to_godot(effect.position),
			MDKMeshBuilder.to_godot(effect.position + motion), MDKScriptRuntime.LEVEL_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		effect.position += motion
		if effect.kind == Kind.DROP:
			effect.velocity.z -= GRAVITY * ticks
		return false
	effect.position = MDKScriptRuntime.to_mdk(hit.position)
	if effect.kind == Kind.DROP:
		var normal := MDKScriptRuntime.to_mdk(hit.normal)
		effect.velocity -= normal * effect.velocity.dot(normal) * BOUNCE
		effect.life -= BOUNCE_TICKS
	else:
		effect.velocity = Vector3.ZERO
	return true


func _place(effect: Effect) -> void:
	effect.sprite.position = MDKMeshBuilder.to_godot(effect.position)
	effect.sprite.pixel_size = effect.scale / 256.0
	effect.sprite.frame = clampi(effect.frames - 1 - int(effect.life * effect.speed) % effect.frames, 0, effect.frames - 1)

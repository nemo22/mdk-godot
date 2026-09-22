## Kurt's thrown items (0x46ce78 throws, 0x43deac updates) and blasts (0x463a94). See
## `docs/engine.md` ("Kurt's items").
class_name MDKItems
extends RefCounted

## Pickup models of the item types (`KurtInventory.Item`).
const MODELS := ["", "SW_DUMMY", "SW_INTER", "SW_TWIST", "SW_THUMP", "SW_HBOMB", "SW_GATT", "SW_KEY",
		"SW_SEAL", "SW_SBONE"]
## A thrown item: Kurt's effect (0x1000), not a target, not solid for Kurt, gravity and collisions.
const THROWN_FLAGS := 0x818a6
## Flag of an item that has landed and does its thing (`obj+0x149` bit 0x40).
const FLAG_ACTIVE := 0x4000
## Thrown items fly this fast (grenades 3 times faster), 15 units/s upwards.
const THROW_SPEED := 25.0
const THROW_UP_SPEED := 15.0
const GRENADE_SPEED_FACTOR := 3.0
## Hit types of blasts (`obj+0x21d`).
const HIT_GRENADE := -7
const HIT_BOMB := -9

var runtime: MDKScriptRuntime
var dt := 1.0 / 30.0
## The World's Most Interesting Bomb (`0x573c24`) and the decoy (`0x573c20`), when out.
var bomb: MDKObject
var decoy: MDKObject
var _animations := {}


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime


## Model animations of items stored in `TRAVSPRT.BNI` (`SW_INTER`, `SW_DUM_I`, `SW_DUM_M`,
## `SW_THUMP`, `SW_NUKE`, …).
func get_animation(animation_name: String) -> MDKModelAnimation:
	if not _animations.has(animation_name):
		var sprites := runtime.kurt.sprites
		_animations[animation_name] = MDKModelAnimation.parse(animation_name, sprites.bytes, sprites.entries[animation_name][0]) \
				if sprites.has(animation_name) else null
	return _animations[animation_name]


## Whether Kurt may use an item now: only one thrown item at a time (decoys excepted), and not
## while the bomb is out (pressing "use" then sets it off).
func can_use(item: int) -> bool:
	if bomb and not bomb.dead:
		return false
	for obj in runtime.objects:
		if not obj.dead and obj.thrown_kind > 0 and obj.thrown_kind not in [1, 8, 9]:
			return item in [1, 8, 9]
	return true


## "Use" pressed while the bomb is out: it goes off at the end of its animation (0x43f258).
func trigger_bomb() -> void:
	if bomb and not bomb.dead and bomb.animation_end_frame >= 0:
		bomb.animation_end_frame = -1


## Throws the selected item (0x46ce78): its pickup model leaves Kurt 4 units up, along his yaw.
func use_item() -> void:
	var kurt := runtime.kurt
	var inventory := kurt.inventory
	if inventory.slots.is_empty():
		return
	var slot := inventory.slots[inventory.selected]
	var item := slot.item
	var controller := runtime.get_arena_state(runtime.current_arena).controller
	var thrown := runtime.spawn(controller, MODELS[item], runtime.kurt_position + Vector3(0, 0, 4), runtime.target_yaw, -1, 0, false)
	if not thrown:
		return
	thrown.flags |= THROWN_FLAGS
	thrown.thrown_kind = item
	thrown.item_ticks = 750 if item in [8, 9] else 150
	thrown.friction = 0.0
	thrown.model_scale = 0.1
	var direction := Vector2.from_angle(deg_to_rad(runtime.target_yaw)) * THROW_SPEED
	if item == KurtInventory.Item.GRENADE:
		direction *= GRENADE_SPEED_FACTOR
	thrown.velocity = Vector3(direction.x, direction.y, 0.0 if kurt.state == Kurt.State.CHUTE else THROW_UP_SPEED)
	if item == KurtInventory.Item.DUMMY:
		thrown.restart_animation(get_animation("SW_DUM_I"), false)
		thrown.animation_end_frame = 0
	thrown.update_transform()
	slot.count -= 1
	if slot.count <= 0:
		inventory.slots.remove_at(inventory.selected)
		inventory.selected = clampi(inventory.selected, 0, maxi(inventory.slots.size() - 1, 0))


## Updates a thrown item after it moved (0x43deac).
func update_thrown(obj: MDKObject) -> void:
	if obj.flags & FLAG_ACTIVE:
		_update_active(obj)
		return
	obj.model_scale = minf(obj.model_scale + dt * 3.0, 1.0)
	# Grenades also stop on aliens (0x43eb48).
	if _hits_object(obj):
		obj.contact_flags |= 0x10
	obj.item_ticks -= 1
	if not obj.contact_flags & (MDKObject.CONTACT_COLLIDED | MDKObject.CONTACT_FLOOR | 0x10) and obj.item_ticks > 0:
		return
	if obj.thrown_kind == KurtInventory.Item.MORTAR and not obj.contact_flags & MDKObject.CONTACT_FLOOR:
		return
	_activate(obj)


func _hits_object(obj: MDKObject) -> bool:
	var excluded := 0x830 if obj.thrown_kind == 0x81 else 0x810
	var needed := 0 if obj.thrown_kind in [KurtInventory.Item.GRENADE, 0x81] else 0x1000000
	for other in runtime.objects:
		if other == obj or other.dead or other.health == 0 or other.arena != obj.arena or other.flags & excluded:
			continue
		if needed and not other.flags & needed:
			continue
		var bounds := runtime.get_world_bounds(other)
		if bounds.has_point(obj.mdk_position) or bounds.intersects_segment(obj.previous_position, obj.mdk_position) != null:
			return true
	return false


## An item landed (or hit something, or its time ran out): it stops and does its thing.
func _activate(obj: MDKObject) -> void:
	obj.velocity = Vector3.ZERO
	obj.flags &= ~(MDKObject.FLAG_GRAVITY | MDKObject.FLAG_COLLIDES)
	obj.flags |= FLAG_ACTIVE
	obj.contact_flags &= ~(MDKObject.CONTACT_COLLIDED | MDKObject.CONTACT_FLOOR | 0x10)
	match obj.thrown_kind:
		KurtInventory.Item.GRENADE:
			var center := obj.mdk_position
			blast(center, 150, 40.0, 6, HIT_GRENADE, obj)
			blast(center, 75, 40.0, 1, HIT_GRENADE, obj)
			runtime.spawn_explosion(obj.arena, center, 2.0)
			runtime.play_sound_at("EXPLODE", center)
			runtime.remove(obj)
		KurtInventory.Item.DUMMY:
			# The decoy walks forward for 15 seconds, and aliens aim at it.
			obj.item_ticks = 450
			var direction := Vector2.from_angle(deg_to_rad(obj.yaw)) * 5.0
			obj.velocity = Vector3(direction.x, direction.y, 0.0)
			obj.flags |= MDKObject.FLAG_GRAVITY | MDKObject.FLAG_COLLIDES
			obj.restart_animation(get_animation("SW_DUM_M"), true)
			decoy = obj
		KurtInventory.Item.INTERESTING_BOMB:
			# It spins on its first frame for 20 seconds (or until Kurt sets it off), then plays its
			# animation and blows up.
			obj.restart_animation(get_animation("SW_INTER"), false)
			obj.animation_end_frame = 0
			obj.item_ticks = 600
			bomb = obj
			runtime.play_sound_at("WMIB", obj.mdk_position)
		KurtInventory.Item.TORNADO:
			obj.item_ticks = 60
			runtime.play_sound_at("TORNADO", obj.mdk_position)
		KurtInventory.Item.MORTAR:
			obj.restart_animation(get_animation("SW_THUMP"), false)
			obj.item_ticks = 30
		KurtInventory.Item.KEY:
			# The "key" is the nuke (`SW_NUKE`).
			obj.item_ticks = 900
			obj.restart_animation(get_animation("SW_NUKE"), false)


## Active items (0x43e860 decoy, 0x43f18c bomb, …). Only the decoy and the bomb are done; the
## others just vanish when their time is up.
func _update_active(obj: MDKObject) -> void:
	match obj.thrown_kind:
		KurtInventory.Item.INTERESTING_BOMB:
			bomb = obj
			if obj.animation_end_frame == 0:
				obj.yaw = fposmod(obj.yaw + dt * 235.0, 360.0)
				obj.item_ticks -= 1
				if obj.item_ticks < 1:
					obj.animation_end_frame = -1
			elif obj.is_animation_done():
				var center := obj.mdk_position
				blast(center, 450, 80.0, 6, HIT_BOMB, null)
				blast(center, 67, 80.0, 1, HIT_BOMB, null)
				runtime.spawn_explosion(obj.arena, center, 3.0)
				runtime.play_sound_at("EXPLODE", center)
				runtime.remove(obj)
				bomb = null
		_:
			obj.item_ticks -= 1
			if obj.item_ticks <= 0:
				if obj == decoy:
					decoy = null
				runtime.remove(obj)


## A blast (0x463a94) of `damage` within `radius` around `center`. `targets`: 1 Kurt, 2 objects,
## 4 arena triangle groups (not done yet). Damage falls off with the distance to a target's box
## (minus half its size), and walls stop it.
func blast(center: Vector3, damage: int, radius: float, targets: int, hit_type: int, source: MDKObject) -> void:
	if targets & 2:
		for obj in runtime.objects.duplicate():
			if obj.dead or obj.arena != runtime.current_arena or obj.health == 0 or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
				continue
			var event := -2
			var best := 0
			var best_distance := 0.0
			var hit_point: Vector3 = obj.mdk_position
			if obj.flags & MDKObject.FLAG_WEAK_PARTS and obj.model:
				var part_bounds: Array = obj.get_part_bounds()
				for i in obj.model.parts.size():
					if obj.hidden_parts & (1 << i) or not MDKScriptRuntime._is_weak_part(obj, i) or i >= obj.part_health.size():
						continue
					var box := runtime.get_world_bounds(obj, part_bounds[i])
					var result := _blast_damage(box, center, damage, radius)
					if result.x <= 0:
						continue
					if result.x > best:
						best = int(result.x)
						best_distance = result.y
						hit_point = box.get_center()
					obj.part_health[i] -= int(result.x)
					if obj.part_health[i] < 1:
						obj.part_health[i] = 0
						event = i + 1
			if obj == source:
				best = damage
				best_distance = 0.0
				hit_point = runtime.get_world_bounds(obj).get_center()
			else:
				var box := runtime.get_world_bounds(obj)
				var result := _blast_damage(box, center, damage, radius)
				if result.x > best:
					best = int(result.x)
					best_distance = result.y
					hit_point = box.get_center()
			if best <= 0 or best_distance > obj.blast_range:
				continue
			var direction := rad_to_deg(atan2(hit_point.y - center.y, hit_point.x - center.x))
			if obj.health < 65000:
				obj.health -= best
			obj.hit_event = event
			obj.hit_type = hit_type
			obj.hit_direction = direction
			if obj.health < 1:
				runtime.kill(obj, direction + 180.0)
	if targets & 1:
		var kurt_point := runtime.kurt_position + Vector3(0, 0, 1)
		var distance := center.distance_to(kurt_point)
		if not runtime.raycast(center + Vector3(0, 0, 1), kurt_point).is_empty():
			distance = radius + 1.0
		distance *= 2.0
		if distance < radius:
			runtime.kurt.hurt(mini(roundi(damage * (1.0 - distance / radius)), 15))


## Damage of a blast on a box (0x463958): `Vector2(damage, distance)`; 0 beyond the radius or
## behind a wall. The distance is measured to the box centre, less half the box's size.
func _blast_damage(box: AABB, center: Vector3, damage: int, radius: float) -> Vector2:
	var size := box.size.length()
	var target := box.get_center()
	# Lift the blast off the floor it may lie on, so the wall test doesn't hit that floor.
	center += Vector3(0, 0, 1)
	var squared := center.distance_squared_to(target) - size * size * 0.25
	if squared > radius * radius:
		return Vector2.ZERO
	squared = maxf(squared, 0.0)
	if not runtime.raycast(center, target).is_empty():
		return Vector2.ZERO
	var distance := sqrt(squared)
	return Vector2(roundi(damage * (1.0 - distance / radius)), distance)

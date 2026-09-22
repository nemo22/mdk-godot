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
## Hit types (`obj+0x21d`, `if_hit_weapon`).
const HIT_MORTAR := -3
const HIT_GRENADE := -7
const HIT_NUKE := -8
const HIT_BOMB := -9
## The mortar (`SW_THUMP`) pounds the ground on these frames of its animation (`0x491e4c`).
const MORTAR_THUMPS := [28, 54, 64, 71, 77, 82, 87, 92, 97, 102, 107, 112, 117, 122, 127]
## Flying aliens the mortar doesn't hurt.
const MORTAR_SPARED := ["XE", "XF"]
## Doors this close to the nuke (squared distance) are blown open.
const NUKE_DOOR_RANGE_SQUARED := 2500.0

var runtime: MDKScriptRuntime
var dt := 1.0 / 30.0
## The World's Most Interesting Bomb (`0x573c24`) and the decoy (`0x573c20`), when out.
var bomb: MDKObject
var decoy: MDKObject
## Twisters of tornados.
var twisters: Array[MDKTwister] = []
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
	if obj.flags & MDKObject.FLAG_COLLECTED:
		# A seal or bone Kurt took back shrinks away like a pickup.
		runtime.behaviors.update_pickup(obj)
		return
	if obj.flags & FLAG_ACTIVE:
		_update_active(obj)
		return
	obj.model_scale = minf(obj.model_scale + dt * 3.0, 1.0)
	# The seal rolls over while it flies.
	if obj.thrown_kind == KurtInventory.Item.SEAL:
		obj.roll = fposmod(obj.roll + dt * 30.0, 360.0)
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
			# The tornado spins for 2 seconds, letting out a twister every half second.
			add_twister(MDKTwister.new(runtime, obj.arena, obj.mdk_position, 0.0))
			obj.item_ticks = 60
			obj.parameter = 45
			runtime.play_sound_at("TORNADO", obj.mdk_position)
		KurtInventory.Item.MORTAR:
			obj.restart_animation(get_animation("SW_THUMP"), false)
			obj.item_ticks = 30
			obj.parameter = 0.0
			_update_mortar(obj)
		KurtInventory.Item.KEY:
			# The "key" becomes the nuke (`SW_NUKE`): a white flash, its animation, then the blast.
			var nuke := runtime.find_model(obj.arena, "SW_NUKE")
			if nuke:
				obj.setup("SW_NUKE", nuke, runtime._get_resolver(obj.arena))
				obj.update_transform()
			obj.item_ticks = 900
			obj.restart_animation(get_animation("SW_NUKE"), false)
			obj.animation_time = 1.0
			runtime.kurt.white_flash = maxf(runtime.kurt.white_flash, 255.0)
			runtime.set_loop_sound(obj, "NUKE")


## Active items (0x43e860 decoy, 0x43f18c bomb, 0x43e690 mortar, 0x43efcc nuke, 0x43e980 seal,
## 0x43ea84 bone, 0x43ee98 tornado).
func _update_active(obj: MDKObject) -> void:
	match obj.thrown_kind:
		KurtInventory.Item.TORNADO:
			obj.yaw = fposmod(obj.yaw + dt * 360.0, 360.0)
			obj.item_ticks -= 1
			if obj.item_ticks < obj.parameter:
				obj.parameter -= 15
				add_twister(MDKTwister.new(runtime, obj.arena, obj.mdk_position, obj.yaw))
			if obj.item_ticks <= 0:
				runtime.kill(obj)
		KurtInventory.Item.MORTAR:
			_update_mortar(obj)
		KurtInventory.Item.KEY:
			_update_nuke(obj)
		KurtInventory.Item.SEAL, KurtInventory.Item.SUPER_BONE:
			_update_seal(obj)
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


func add_twister(twister: MDKTwister) -> void:
	twisters.push_back(twister)
	runtime.add_child(twister)


## Moves the twisters (one tick).
func update_twisters() -> void:
	for twister in twisters.duplicate():
		if twister.arena != runtime.current_arena:
			continue
		if not twister.tick(dt):
			twisters.erase(twister)
			twister.queue_free()


## The mortar (0x43e690) pounds the ground on the frames of `MORTAR_THUMPS`: the screen shakes and
## every alien of the arena (flying ones spared) loses 4 health, and is thrown up if it stands. From
## the fourth thump on, Kurt is knocked down if he stands on a floor. It blows up at the end.
func _update_mortar(obj: MDKObject) -> void:
	if not obj.animation or obj.is_animation_done():
		runtime.kill(obj)
		return
	var thump := int(obj.parameter)
	if thump >= MORTAR_THUMPS.size() or obj.animation_frame < MORTAR_THUMPS[thump]:
		return
	thump += 1
	obj.parameter = thump
	if thump >= 4 and runtime.kurt.is_on_floor():
		runtime.kurt.knock_damage = Kurt.KNOCKDOWN_DAMAGE
	runtime.raise_shake(5.0)
	for other in runtime.objects.duplicate():
		if other == obj or other.dead or other.arena != obj.arena or other.flags & 0x1030 or other.type_name.to_upper() in MORTAR_SPARED:
			continue
		if other.contact_flags & MDKObject.CONTACT_FLOOR:
			other.velocity.z += 5.0
		var center := runtime.get_world_bounds(other).get_center()
		var direction := rad_to_deg(atan2(center.y - runtime.kurt_position.y, center.x - runtime.kurt_position.x))
		if other.health < 65000:
			other.health -= 4
		other.hit_event = -1
		other.hit_type = HIT_MORTAR
		other.hit_direction = direction
		if other.health <= 0:
			runtime.kill(other, direction + 180.0)


## The nuke (0x43efcc) shakes the screen while its animation plays (with a white flash towards the
## end), then blows open the doors nearby and blasts everything within 60 units.
func _update_nuke(obj: MDKObject) -> void:
	if obj.animation and not obj.is_animation_done():
		runtime.raise_shake(3.0)
		# The screen turns white from frame 70 to the end.
		if obj.animation_frame > 70:
			var flash := roundf((obj.animation_frame - 70) * 255.0 / maxi(obj.animation.frame_count - 70, 1))
			runtime.kurt.white_flash = maxf(runtime.kurt.white_flash, flash)
		return
	var center := obj.mdk_position
	for other in runtime.objects:
		if not other.dead and other.flags & MDKObject.FLAG_DOOR and other.mdk_position.distance_squared_to(center) < NUKE_DOOR_RANGE_SQUARED:
			other.door_state = (other.door_state & 0x1F) | 0x80
	blast(center, 200, 60.0, 6, HIT_NUKE, null)
	blast(center, 19, 60.0, 1, HIT_NUKE, null)
	runtime.play_sound_at("EXPLODE", center)
	runtime.spawn_explosion(obj.arena, center, 3.0)
	runtime.remove(obj)


## A thrown seal or bone (0x43e980, 0x43ea84) plays `XMT_LAND` once it lands. Unless something has
## got hold of it (its script flag 1), Kurt can take it back after 5 seconds; a seal shrinks away
## after 25.
func _update_seal(obj: MDKObject) -> void:
	if not obj.script_flags & 1:
		if obj.item_ticks < 601:
			obj.flags |= MDKObject.FLAG_PICKUP
		if obj.thrown_kind == KurtInventory.Item.SEAL:
			obj.item_ticks -= 1
			if obj.item_ticks < 1:
				obj.model_scale *= 0.9
				obj.update_transform()
				if obj.model_scale < 0.1:
					runtime.kill(obj)
				return
		elif obj.item_ticks >= 601:
			obj.item_ticks -= 1
	else:
		obj.model_scale = 1.0
		obj.flags &= ~MDKObject.FLAG_PICKUP
	if not obj.animation and not obj.script_flags & 2:
		obj.roll = 0.0
		obj.script_flags |= 2
		obj.flags |= MDKObject.FLAG_GRAVITY | MDKObject.FLAG_COLLIDES
		obj.flags &= ~MDKObject.FLAG_LOOP
		obj.restart_animation(runtime.find_arena_animation(obj.arena, "XMT_LAND"), false)


## A blast (0x463a94) of `damage` within `radius` around `center`. `targets`: 1 Kurt, 2 objects,
## 4 arena triangle groups (not done yet). Damage falls off with the distance to a target's box
## (minus half its size), and walls stop it.
func blast(center: Vector3, damage: int, radius: float, targets: int, hit_type: int, source: MDKObject, count_kills := true) -> void:
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
			# Blasts knock Kurt down twice as easily.
			runtime.kurt.knock_damage *= 2.0
	if targets & 4:
		_blast_groups(center, damage, radius, hit_type, MDKScriptRuntime.HIT_BLAST if count_kills else MDKScriptRuntime.HIT_OTHER_BLAST)


## A blast on the triangle groups that react to hits (0x463a94): each gets one hit, on the first
## of its triangles within the radius that the blast reaches (its centre, or another triangle of the
## group in the way), of the damage less the falloff.
func _blast_groups(center: Vector3, damage: int, radius: float, hit_type: int, kind: int) -> void:
	var arena_name := runtime.current_arena
	var state := runtime.get_arena_state(arena_name)
	var origin := center + Vector3(0, 0, 1)
	for i in 16:
		if not state.group_hit_flags[i] and not state.group_hit_scripts[i]:
			continue
		for triangle_center in runtime.level.get_group_centers(arena_name, i + 1):
			if origin.distance_squared_to(triangle_center) > radius * radius:
				continue
			var point := triangle_center
			var hit := runtime.raycast(origin, triangle_center)
			if not hit.is_empty():
				var collider: Object = hit.collider
				if not collider.has_meta(&"group") or collider.get_meta(&"group") != i + 1:
					continue
				point = MDKScriptRuntime.to_mdk(hit.position)
			var distance := origin.distance_to(point)
			runtime.hit_group(arena_name, i + 1, roundi(damage * (radius - distance) / radius), kind, hit_type)
			break


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

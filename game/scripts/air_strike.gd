## Bones' air strike (sniper ammo type 5, `SW_BONES`; 0x4641ac, 0x43fa0c, 0x43deac). See
## `docs/gameplay.md` ("Sniper mode").
##
## The point in the crosshair (within 5000 units, with open sky 1000 units above it) is the target.
## `X_STRIKE` flies a 5-point curve at 150 units/s, from 50 units behind Kurt at the arena's top +
## 30, over the target (32 above it) and away, and drops 9 `X_TOOTH` bombs (grenades) one every 15
## units from 60 before the target to 60 after. From level 7 on there's a single strike, and it
## dives into the target instead (450 damage within 80).
class_name MDKAirStrike
extends RefCounted

const SPEED := 150.0
const RANGE := 5000.0
const SKY := 1000.0
const HEIGHT := 30.0
const OVER_TARGET := 32.0
const TEETH := 9
const TOOTH_SPACING := 15.0
const TOOTH_TICKS := 900
const DIVE_DAMAGE := 450
const DIVE_KURT_DAMAGE := 67
const DIVE_RADIUS := 80.0
const HIT_DIVE := -6

var runtime: MDKScriptRuntime
## The one strike of levels 7 and 8 was used (`0x57440b`).
var used_up := false
var _strike: MDKObject
var _curve: Curve3D
var _offset := 0.0
var _target_offset := 0.0
var _dive_offset := INF
var _teeth := 0
var _diving := false


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime


func is_active() -> bool:
	return _strike != null and is_instance_valid(_strike) and not _strike.dead


## Calls the strike on the point in the view from `eye` (MDK) along `yaw`/`pitch`. Returns false
## (and Kurt blows a raspberry) without a target, while a strike is out or when it's used up.
func call_strike(eye: Vector3, yaw: float, pitch: float) -> bool:
	if is_active():
		return false
	var direction := Vector3(cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)), sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)), -sin(deg_to_rad(pitch)))
	var hit := runtime.raycast(eye, eye + direction * RANGE)
	if hit.is_empty() or used_up:
		runtime.kurt.play_sound("RASPBER")
		return false
	var target := MDKScriptRuntime.to_mdk(hit.position)
	if not runtime.raycast(target + Vector3(0, 0, 1), target + Vector3(0, 0, SKY)).is_empty():
		runtime.kurt.play_sound("RASPBER")
		return false
	var dive := runtime.level.number >= 7
	if dive:
		used_up = true
	_start(target, dive)
	return true


func _start(target: Vector3, dive: bool) -> void:
	var bounds: AABB = runtime.level.arena_bounds.get(runtime.current_arena, AABB())
	var cruise := bounds.end.y + HEIGHT
	var kurt := runtime.kurt_position
	var away := Vector2(kurt.x - target.x, kurt.y - target.y).normalized() * 50.0
	var start := Vector3(kurt.x + away.x, kurt.y + away.y, cruise)
	var over := target + Vector3(0, 0, OVER_TARGET)
	var end := over * 2.0 - start
	if not dive:
		end.z = cruise
	var before := _clear_point(start, over, target)
	var after := _clear_point(end, over, target) if not dive else (over + end) * 0.5
	_curve = Curve3D.new()
	var points := [start, before, over, after, end]
	for i in points.size():
		var previous: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, points.size() - 1)]
		var tangent := MDKMeshBuilder.to_godot(next - previous) * 0.25
		_curve.add_point(MDKMeshBuilder.to_godot(points[i]), -tangent, tangent)
	_target_offset = _curve.get_closest_offset(MDKMeshBuilder.to_godot(over))
	_dive_offset = (_curve.get_closest_offset(MDKMeshBuilder.to_godot(before)) + _target_offset) * 0.5 if dive else INF
	_offset = 0.0
	_teeth = 0
	_diving = false
	var controller := runtime.get_arena_state(runtime.current_arena).controller
	_strike = runtime.spawn(controller, "X_STRIKE", start, 0.0, -1, 0, false)
	if _strike:
		_strike.health = 65000
		_strike.flags = 0x85e20


## The first point from `from` towards `over` (in steps of 9%) that the target can see.
func _clear_point(from: Vector3, over: Vector3, target: Vector3) -> Vector3:
	for i in range(1, 11):
		var point := from.lerp(over, 0.09 * i)
		if runtime.raycast(target + Vector3(0, 0, 2), point).is_empty():
			return point
	return from.lerp(over, 0.9)


## Moves the strike by a tick.
func update(ticks: float) -> void:
	if not is_active():
		_strike = null
		return
	if _diving:
		if _strike.contact_flags & (MDKObject.CONTACT_COLLIDED | MDKObject.CONTACT_FLOOR):
			var center := _strike.mdk_position
			runtime.items.blast(center, DIVE_DAMAGE, DIVE_RADIUS, 6, HIT_DIVE, _strike)
			runtime.items.blast(center, DIVE_KURT_DAMAGE, DIVE_RADIUS, 1, HIT_DIVE, _strike)
			runtime.spawn_explosion(_strike.arena, center, 2.0)
			runtime.play_sound_at("EXPLODE", center)
			runtime.remove(_strike)
		return
	var previous := _strike.mdk_position
	_offset += SPEED / 30.0 * ticks
	if _offset >= _curve.get_baked_length():
		runtime.remove(_strike)
		return
	_strike.mdk_position = MDKScriptRuntime.to_mdk(_curve.sample_baked(_offset))
	var motion := _strike.mdk_position - previous
	if motion != Vector3.ZERO:
		_strike.yaw = fposmod(rad_to_deg(atan2(motion.y, motion.x)), 360.0)
	if _offset >= _dive_offset:
		# It leaves the path with its velocity, falling, until it hits something.
		_diving = true
		_strike.velocity = motion * 30.0 / ticks
		_strike.flags |= MDKObject.FLAG_GRAVITY | MDKObject.FLAG_COLLIDES
		return
	var tooth := roundi((_offset - _target_offset) / TOOTH_SPACING + 5.0)
	while _teeth < tooth and _teeth < TEETH and _dive_offset == INF:
		_teeth += 1
		_drop_tooth()


## A tooth falls as a hand grenade (kind 5).
func _drop_tooth() -> void:
	var controller := runtime.get_arena_state(runtime.current_arena).controller
	var tooth := runtime.spawn(controller, "X_TOOTH", _strike.mdk_position, _strike.yaw, -1, 0, false)
	if not tooth:
		return
	tooth.flags |= MDKItems.THROWN_FLAGS
	tooth.thrown_kind = KurtInventory.Item.GRENADE
	tooth.item_ticks = TOOTH_TICKS
	tooth.friction = 0.0
	tooth.velocity = Vector3(0, 0, -5.0)

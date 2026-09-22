## Fans (updrafts) of the arenas (`arena+0x45e`): created on the arena's type-7 hotspots by
## `fan_create` (0x413a94), they lift Kurt and objects inside their box (`updraft_query` 0x413c24
## → 0x413d14) and show rising particles (0x414230). See `docs/engine.md` ("Fans and conveyors").
class_name MDKFans
extends RefCounted

## Who asks: Kurt (1) or an object (2); a fan acts on those whose bit is in its mask.
const MASK_KURT := 1
const MASK_OBJECTS := 2
## Type 6 fans lift at full strength up to 5 units below their top, then less and less (0.2 per
## unit); the box reaches 5 units above the top.
const TOP := 5.0
const TOP_FADE := 0.2
## In the last 2 units a wobble of ±2 u/s (0.1 per query) is added (`0x490d7c`).
const WOBBLE_ZONE := 2.0
const WOBBLE_LIMIT := 2.0
const WOBBLE_STEP := 0.1
## Kurt's or an object's vertical speed rises by `(target + 64) × dt` towards the fan's speed.
const LIFT_ACCELERATION := 64.0


class Fan:
	var name := ""
	var arena := ""
	var hotspot := 0
	var param := 0
	var type := 0
	## Upward speed at full strength (units/s).
	var strength := 0.0
	## Bit 0: enabled (`fan_enable`); the bits are tested against the asker's mask.
	var mask := -1
	var box_start := Vector3()
	var box_end := Vector3()
	var particles: CPUParticles3D


var runtime: MDKScriptRuntime
var _fans: Array[Fan] = []
var _wobble := 0.0
var _wobble_up := false


func _init(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime


## `fan_create` (0x413a94): a fan on the arena's hotspot `hotspot` (DTI record of type 7). With
## type 6, `strength` is the time to rise through the box.
func create(arena: String, hotspot: int, fan_name: String, param: int, type: int, strength: float) -> void:
	var record := _find_hotspot(arena, hotspot)
	if record.is_empty():
		push_error("Cannot find fan hotspot id %d for %s" % [hotspot, fan_name])
		return
	var fan := Fan.new()
	fan.name = fan_name
	fan.arena = arena
	fan.hotspot = hotspot
	fan.param = param
	fan.type = type
	fan.box_start = record.position - Vector3(0, 0, 0.5)
	fan.box_end = record.box_end
	fan.strength = strength
	if type == 6:
		fan.strength = (record.box_end.z - record.position.z) / (strength - 0.5)
	fan.particles = _make_particles(fan)
	_fans.push_back(fan)


## `fan_remove` (0x413fa0).
func remove(arena: String, fan_name: String) -> void:
	for fan in _fans:
		if fan.arena == arena and fan.name == fan_name:
			fan.particles.queue_free()
			_fans.erase(fan)
			return


## `fan_enable` (0x4140e4): sets or clears bit 0 of the fan's mask.
func enable(arena: String, fan_name: String, enabled: bool) -> void:
	for fan in _fans:
		if fan.arena == arena and fan.name == fan_name:
			fan.mask = fan.mask | 1 if enabled else fan.mask & ~1
			fan.particles.emitting = fan.mask & (MASK_KURT | MASK_OBJECTS) != 0


func clear() -> void:
	for fan in _fans:
		fan.particles.queue_free()
	_fans.clear()


## The vertical speed for something at `point` (MDK coordinates) in `arena` going up or down at
## `vz`, or NAN when no fan of that arena holds it (`updraft_query`).
func query(arena: String, point: Vector3, vz: float, mask: int, dt: float) -> float:
	var found := false
	for fan in _fans:
		if fan.arena != arena or not fan.mask & mask:
			continue
		if point.x < fan.box_start.x or point.x > fan.box_end.x or point.y < fan.box_start.y or point.y > fan.box_end.y \
				or point.z < fan.box_start.z or point.z > fan.box_end.z + TOP:
			continue
		found = true
		vz = _lift(fan, point.z, vz, dt)
	return vz if found else NAN


## One fan's effect (0x413d14).
func _lift(fan: Fan, z: float, vz: float, dt: float) -> float:
	var height := (z - fan.box_start.z) / (fan.box_end.z - fan.box_start.z) if fan.param == 0 else 1.0
	var factor := 1.0
	match fan.type:
		1:
			factor = 1.0 - height * height
		2:
			factor = (1.0 - height) * (1.0 - height)
		3:
			factor = 1.0 - height
		4:
			factor = 1.0 - height * height * height
		5:
			factor = pow(1.0 - height, 3.0)
		6:
			if fan.box_end.z - z < TOP:
				factor = 1.0 - (z - (fan.box_end.z - TOP)) * TOP_FADE
	var target := fan.strength * factor
	if fan.type == 6:
		if fan.box_end.z - z < WOBBLE_ZONE:
			if not _wobble_up:
				_wobble -= WOBBLE_STEP
				if _wobble < -WOBBLE_LIMIT:
					_wobble_up = true
			else:
				_wobble += WOBBLE_STEP
				if _wobble > WOBBLE_LIMIT:
					_wobble_up = false
			target += _wobble
		if target < vz:
			vz = (vz + target) * 0.5
	elif factor < 0.0:
		target = -LIFT_ACCELERATION
	if vz < target:
		vz = minf(vz + (target + LIFT_ACCELERATION) * dt, target)
	return vz


func _find_hotspot(arena: String, id: int) -> Dictionary:
	for entry in runtime.level.dti.arenas:
		if entry.name != arena:
			continue
		for record: Dictionary in entry.records:
			if record.type == 7 and record.id == id:
				return record
	return {}


## The original spawns a rising particle at a random point of the box one frame in 8.
func _make_particles(fan: Fan) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	var start := MDKMeshBuilder.to_godot(fan.box_start)
	var end := MDKMeshBuilder.to_godot(fan.box_end)
	var bottom_center := Vector3((start.x + end.x) * 0.5, start.y + 0.25, (start.z + end.z) * 0.5)
	var height := end.y - start.y
	var speed := maxf(fan.strength, 1.0)
	particles.position = bottom_center
	particles.amount = 12
	particles.lifetime = height / speed
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(absf(end.x - start.x) * 0.5, 0.0, absf(end.z - start.z) * 0.5)
	particles.direction = Vector3.UP
	particles.spread = 0.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = speed
	particles.initial_velocity_max = speed
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.6, 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.6)
	mesh.material = material
	particles.mesh = mesh
	runtime.add_child(particles)
	return particles

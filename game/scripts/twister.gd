## A twister of the tornado item (0x40741c): it spirals out of the tornado for 2 seconds, then
## splits into one twister per object of the arena, each chasing its object (0x407974) for 5
## seconds, bouncing off walls and hurting whatever it's inside by 2 health per tick. The original
## draws it as a ribbon along its last positions; this one is a spinning funnel.
class_name MDKTwister
extends MeshInstance3D

## Spiral: the angle grows by 720°/s; at 1440° the twister is 15 units out and 15 up.
const SPIRAL_RATE := 720.0
const SPIRAL_END := 1440.0
const SPIRAL_SIZE := 15.0
const SPIRAL_SPEED := 200.0
## Chasing: 150 ticks of life, a tick more for each tick inside an object; the velocity keeps 90%
## of itself and gains 20 u/s towards the target each tick (at most 200 u/s).
const LIFETIME := 150
const KEEP := 0.9
const PULL := 20.0
const DAMAGE := 2

var runtime: MDKScriptRuntime
var arena := ""
var origin := Vector3()
var yaw := 0.0
var angle := 0.0
var mdk_position := Vector3()
var velocity := Vector3()
var target: MDKObject
var chasing := false
var life := LIFETIME


func _init(p_runtime: MDKScriptRuntime, p_arena: String, p_origin: Vector3, p_yaw: float) -> void:
	runtime = p_runtime
	arena = p_arena
	origin = p_origin
	yaw = p_yaw
	mdk_position = p_origin
	var funnel := CylinderMesh.new()
	funnel.top_radius = 2.5
	funnel.bottom_radius = 0.3
	funnel.height = 8.0
	funnel.radial_segments = 12
	funnel.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	funnel.material = material
	mesh = funnel
	_place()


## A copy chasing another object.
func split(p_target: MDKObject) -> MDKTwister:
	var twister := MDKTwister.new(runtime, arena, origin, yaw)
	twister.mdk_position = mdk_position
	twister.velocity = velocity
	twister.chasing = true
	twister.target = p_target
	twister._place()
	return twister


## One tick; returns false when the twister is gone.
func tick(dt: float) -> bool:
	rotate_y(dt * TAU * 3.0)
	if not chasing:
		angle += dt * SPIRAL_RATE
		var r := angle / SPIRAL_END
		var direction := Vector2.from_angle(deg_to_rad(angle + yaw))
		var next := origin + Vector3(direction.x, direction.y, 1.0) * SPIRAL_SIZE * r
		_move_to(next)
		velocity = Vector3(direction.y, -direction.x, 0.0) * SPIRAL_SPEED
		if angle > SPIRAL_END:
			chasing = true
			_split()
		return true
	var next := mdk_position + velocity * dt
	var hit := runtime.raycast(mdk_position, next)
	if not hit.is_empty():
		# Bounce off the wall.
		var normal := MDKScriptRuntime.to_mdk(hit.normal)
		velocity -= normal * velocity.dot(normal) * 2.0
		next = MDKScriptRuntime.to_mdk(hit.position) + normal * 0.1
	mdk_position = next
	_place()
	for obj in runtime.objects.duplicate():
		if obj.dead or obj.arena != arena or obj.health == 0 or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		var bounds := runtime.get_world_bounds(obj)
		if not bounds.has_point(mdk_position):
			continue
		var center := bounds.get_center()
		var direction := rad_to_deg(atan2(center.y - runtime.kurt_position.y, center.x - runtime.kurt_position.x))
		if obj.health < 65000:
			obj.health -= DAMAGE
		obj.hit_event = -1
		obj.hit_direction = direction
		life -= 1
		if obj.health < 1:
			runtime.kill(obj, direction + 180.0)
	life -= 1
	if life <= 0:
		return false
	if target and not target.dead and target.health > 0:
		var toward := (runtime.get_world_bounds(target).get_center() - mdk_position).normalized()
		velocity = velocity * KEEP + toward * PULL
	else:
		target = null
	return true


## The spiral is over: one twister for each object of the arena (0x407774).
func _split() -> void:
	var first := true
	for obj in runtime.objects:
		if obj.dead or obj.arena != arena or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		if first:
			target = obj
			first = false
		else:
			runtime.items.add_twister(split(obj))


func _move_to(next: Vector3) -> void:
	var hit := runtime.raycast(mdk_position, next)
	if not hit.is_empty():
		var normal := MDKScriptRuntime.to_mdk(hit.normal)
		next = MDKScriptRuntime.to_mdk(hit.position) + normal * 0.1
	mdk_position = next
	_place()


func _place() -> void:
	position = MDKMeshBuilder.to_godot(mdk_position) + Vector3.UP * 3.0

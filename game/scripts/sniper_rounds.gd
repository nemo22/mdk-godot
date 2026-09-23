## Sniper rounds (3 slots at `0x573c98`, updated by 0x462708 after the objects). See
## `docs/gameplay.md` ("Sniper mode").
##
## A round starts at the eye along the view (yaw = Kurt's, pitch = the view's) and is tested every
## tick along the segment it moved: objects (their boxes, then their parts), then the arena.
## - Type 0, bullet: 1100 units/s for 75 ticks; 8 damage.
## - Type 1 (`SW_HOME`), homing bullet: 400 units/s for 240 ticks, steering at the locked object.
## - Type 2 (`SW_SGREN`), grenade: like the bullet, but it explodes.
## - Type 3 (`SW_HGREN`), homing grenade.
## - Type 4 (`SW_LGREN`), mortar: thrown at 150 units/s, slowed by drag and gravity, bouncing off the
##   arena (a hit on a triangle group can be guided by `bomb_follow_path`), exploding after 450 ticks
##   or on an object.
class_name MDKSniperRounds
extends Node3D

enum State { FREE, FLYING, KILLED, HIT, DEAD, EXPLODED }

const SLOTS := 3
const LIFE := [75, 240, 75, 240, 450]
const SPEED := [1100.0, 400.0, 1100.0, 400.0, 150.0]
const MODELS := ["SW_SHOT", "SW_HOME", "SW_SGREN", "SW_HGREN", "SW_LGREN"]
const DAMAGE := 8
## Bullets and homing bullets spin 720° per second (not the mortar).
const SPIN := 720.0
## Homing (0x463174): steering starts after 7 ticks; the yaw rate accelerates by 540°/s² up to
## 270°/s, the pitch turns by at most 120°/s; the speed aims for 250 when within 35° of the target,
## else 100, rising by 200/s and falling by 500/s.
const HOMING_START := 233
const HOMING_YAW_ACCELERATION := 540.0
const HOMING_YAW_RATE := 270.0
const HOMING_PITCH_RATE := 120.0
## Mortar (0x46360c): drag of 60 units/s² shared between the horizontal and vertical speeds,
## gravity 32 units/s², bounces with `v −= 1.75 (v·n) n`.
const MORTAR_DRAG := 60.0
const MORTAR_GRAVITY := 32.0
const MORTAR_BOUNCE := 1.75
## Explosions (0x4638cc): 150 damage to objects and triangle groups, 75 to Kurt, hit type −7.
const EXPLOSION_DAMAGE := 150
const EXPLOSION_KURT_DAMAGE := 75
const HIT_EXPLOSION := -7


class Round:
	var state := State.FREE
	var type := 0
	var position := Vector3()
	var yaw := 0.0
	## Positive looks down.
	var pitch := 0.0
	var roll := 0.0
	var speed := 0.0
	## Mortar: vertical speed.
	var vertical := 0.0
	var life := 0.0
	## Ticks the slot stays busy after the round ended (its camera keeps watching).
	var linger := 0.0
	var target: MDKObject
	var target_part := -1
	var yaw_rate := 0.0
	## `bomb_follow_path` (opcode 28): the path and its time.
	var path := 0
	var path_time := 0.0
	var visual: MDKObject
	## The round's camera (0x461d80): its distance behind the round (growing by 10/s up to 10) and,
	## after a hit, how long it keeps watching (30 ticks).
	var camera_distance := 0.0
	var camera_position := Vector3()
	var watch := 0.0


var runtime: MDKScriptRuntime
var _rounds: Array[Round] = []
## The mortar round that just hit a triangle group (`0x491ef0`, for `bomb_follow_path`).
var last_mortar: Round


func _ready() -> void:
	for i in SLOTS:
		_rounds.push_back(Round.new())


## Fires a round of `type` from `eye` (MDK) along the view (0x461e88). Returns false when all the
## slots are busy.
func fire(type: int, eye: Vector3, yaw: float, pitch: float, target: MDKObject) -> bool:
	var round: Round = null
	for candidate in _rounds:
		if candidate.state == State.FREE:
			round = candidate
			break
	if not round:
		return false
	round.state = State.FLYING
	round.type = type
	round.position = eye
	round.yaw = yaw
	round.pitch = pitch
	round.roll = 0.0
	round.life = LIFE[type]
	round.linger = 0.0
	round.speed = SPEED[type]
	round.vertical = 0.0
	round.path = 0
	round.yaw_rate = 0.0
	round.target = target if type == 1 or type == 3 else null
	round.target_part = _head_part(target) if round.target else -1
	round.camera_distance = 0.0
	round.camera_position = eye
	round.watch = 0.0
	if type == 4:
		round.speed = SPEED[4] * cos(deg_to_rad(pitch))
		round.vertical = -SPEED[4] * sin(deg_to_rad(pitch))
	_make_visual(round)
	return true


## What the camera of slot `index` shows (0x461bcc): `{"transform": Transform3D}` (Godot space)
## while it watches, or `{"fill": palette index}` (0 empty, 0x3c after a hit, 0xf4 after a kill or
## an explosion, −1 after a miss: the `SNIPERGA` animation).
func get_camera(index: int) -> Dictionary:
	var round := _rounds[index]
	if round.state == State.FREE:
		return {"fill": 0}
	if round.state == State.FLYING or round.watch > 0.0:
		var direction := _direction(round)
		var look := MDKMeshBuilder.to_godot(direction)
		return {"transform": Transform3D(Basis.looking_at(look, Vector3.UP), MDKMeshBuilder.to_godot(round.camera_position))}
	match round.state:
		State.HIT:
			return {"fill": 0x3c}
		State.DEAD:
			return {"fill": -1, "time": round.linger}
	return {"fill": 0xf4}


## `bomb_follow_path` (opcode 28): the mortar round that just hit a triangle group follows a path.
func guide_last_mortar(path: int) -> void:
	var round := last_mortar
	if round and round.state == State.FLYING and round.type == 4 and round.path == 0:
		round.path = path
		round.path_time = 0.0


## A part whose name contains `HEAD` is aimed at, else the whole object.
func _head_part(obj: MDKObject) -> int:
	if not obj or not obj.model:
		return -1
	for i in obj.model.parts.size():
		if "HEAD" in obj.model.parts[i].name:
			return i
	return -1


func _make_visual(round: Round) -> void:
	if round.visual:
		round.visual.queue_free()
		round.visual = null
	var model := runtime.find_model(runtime.current_arena, MODELS[round.type])
	if not model:
		return
	round.visual = MDKObject.new()
	round.visual.setup(MODELS[round.type], model, runtime.get_resolver(runtime.current_arena))
	# The orientation is set as a whole (see `_visual_basis`).
	round.visual.flags |= MDKObject.FLAG_ROLLING
	add_child(round.visual)


## Updates the rounds by a tick.
func update(ticks: float) -> void:
	var dt := ticks / 30.0
	for round in _rounds:
		if round.state == State.FREE:
			continue
		if round.state != State.FLYING:
			round.linger -= ticks
			round.watch -= ticks
			if round.linger <= 0.0:
				round.state = State.FREE
			continue
		round.life -= ticks
		if round.type != 4:
			round.roll = fposmod(round.roll + SPIN * dt, 360.0)
		if round.path:
			_follow_path(round, ticks)
		elif round.type == 4:
			_move_mortar(round, dt)
		else:
			if round.target:
				_steer(round, dt)
			_move_straight(round, dt)
		if round.state == State.FLYING and round.life <= 0.0:
			if round.type >= 2:
				_explode(round, 50.0 if round.type == 4 else 25.0, null)
			else:
				_end(round, State.DEAD, 30.0)
		if round.state == State.FLYING:
			round.camera_distance = minf(round.camera_distance + 10.0 * dt, 10.0)
			round.camera_position = round.position - _direction(round) * round.camera_distance
		if round.visual:
			round.visual.visible = round.state == State.FLYING
			round.visual.mdk_position = round.position
			round.visual.rolling_basis = _visual_basis(round)
			round.visual.update_transform()


## The round models stand upright (their length along +Z), so the nose is turned from +Z to the
## flight direction, and the spin is around the length.
func _visual_basis(round: Round) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(round.yaw)) * Basis(Vector3.BACK, deg_to_rad(-round.pitch)) 			* Basis(Vector3.BACK, -PI / 2.0) * Basis(Vector3.UP, deg_to_rad(round.roll))


func _direction(round: Round) -> Vector3:
	var yaw := deg_to_rad(round.yaw)
	var pitch := deg_to_rad(round.pitch)
	return Vector3(cos(yaw) * cos(pitch), sin(yaw) * cos(pitch), -sin(pitch))


## Straight flight (0x462f24), tested against objects and the arena.
func _move_straight(round: Round, dt: float) -> void:
	var start := round.position
	var end := start + _direction(round) * round.speed * dt
	var hit := _test_objects(start, end)
	var wall := runtime.raycast(start, end)
	var wall_point := MDKScriptRuntime.to_mdk(wall.position) if not wall.is_empty() else Vector3()
	if hit and (wall.is_empty() or start.distance_to(hit[1]) < start.distance_to(wall_point)):
		round.position = hit[1]
		_hit_object(round, hit[0], hit[2], hit[1])
		return
	if not wall.is_empty():
		# The point is taken back a unit off the wall.
		round.position = wall_point + MDKScriptRuntime.to_mdk(wall.normal)
		runtime.hit_group_at(wall, DAMAGE if round.type < 2 else 0, MDKScriptRuntime.HIT_SHOT, round.type)
		runtime.spark(round.position, 3)
		if round.type >= 2:
			_explode(round, 25.0, null)
		else:
			_end(round, State.DEAD, 30.0)
		return
	round.position = end
	if round.position.z < runtime.get_arena_floor(runtime.current_arena) - MDKObjectMotion.FALL_OUT_DEPTH:
		_end(round, State.DEAD, 30.0)


## Homing (0x463028, 0x463174): the yaw rate accelerates towards the error (and restarts from 0 when
## it has the wrong sign), never overshooting; the pitch turns at a limited rate.
func _steer(round: Round, dt: float) -> void:
	var target := round.target
	if not is_instance_valid(target) or target.dead:
		round.target = null
		return
	if round.life > HOMING_START:
		return
	var bounds := runtime.get_world_bounds(target)
	if round.target_part >= 0 and not target.hidden_parts & (1 << round.target_part):
		bounds = runtime.get_world_bounds(target, target.get_part_bounds()[round.target_part])
	var aim := bounds.get_center() - round.position
	var yaw_error := wrapf(rad_to_deg(atan2(aim.y, aim.x)) - round.yaw, -180.0, 180.0)
	if round.yaw_rate * yaw_error < 0.0:
		round.yaw_rate = 0.0
	round.yaw_rate = clampf(round.yaw_rate + signf(yaw_error) * HOMING_YAW_ACCELERATION * dt, -HOMING_YAW_RATE, HOMING_YAW_RATE)
	var yaw_step := round.yaw_rate * dt
	if absf(yaw_step) > absf(yaw_error):
		yaw_step = yaw_error
	round.yaw = fposmod(round.yaw + yaw_step, 360.0)
	var pitch_goal := -rad_to_deg(atan2(aim.z, Vector2(aim.x, aim.y).length()))
	var pitch_error := wrapf(pitch_goal - round.pitch, -180.0, 180.0)
	round.pitch += clampf(pitch_error, -HOMING_PITCH_RATE * dt, HOMING_PITCH_RATE * dt)
	var goal := 250.0 if absf(yaw_error) + absf(pitch_error) <= 35.0 else 100.0
	round.speed = move_toward(round.speed, goal, (200.0 if goal > round.speed else 500.0) * dt)


## The mortar (0x46360c): drag shared between the horizontal and the vertical speed (only while
## rising), gravity, bounces off the arena; it settles after 15 ticks once it stops.
func _move_mortar(round: Round, dt: float) -> void:
	var fraction := round.speed / (absf(round.vertical) + round.speed) if round.speed > 0.0 else 0.0
	round.speed = maxf(round.speed - fraction * MORTAR_DRAG * dt, 0.0)
	if round.vertical > 0.0:
		round.vertical = maxf(round.vertical - (1.0 - fraction) * MORTAR_DRAG * dt, 0.0)
	round.vertical = maxf(round.vertical - MORTAR_GRAVITY * dt, -220.0)
	var heading := Vector2.from_angle(deg_to_rad(round.yaw)) * round.speed
	var velocity := Vector3(heading.x, heading.y, round.vertical)
	var start := round.position
	var end := start + velocity * dt
	var hit := _test_objects(start, end)
	if hit:
		round.position = hit[1]
		_explode(round, 50.0, hit[0])
		return
	var wall := runtime.raycast(start, end)
	if wall.is_empty():
		round.position = end
		return
	var normal := MDKScriptRuntime.to_mdk(wall.normal)
	round.position = MDKScriptRuntime.to_mdk(wall.position) + normal * 0.5
	last_mortar = round
	runtime.hit_group_at(wall, 0, MDKScriptRuntime.HIT_SHOT, 4)
	if round.path:
		return
	velocity -= normal * velocity.dot(normal) * MORTAR_BOUNCE
	if velocity.z > 0.0 and velocity.z < 4.0:
		velocity.z = 0.0
	round.speed = Vector2(velocity.x, velocity.y).length()
	round.vertical = velocity.z
	if round.speed > 0.0:
		round.yaw = rad_to_deg(atan2(velocity.y, velocity.x))
	if round.life > 15.0 and round.speed < 0.5 and round.vertical < 1.0:
		round.life = 15.0


## A mortar round guided by `bomb_follow_path` (0x4634ac): along the path (absolute positions)
## without collisions until its last key, then it goes off.
func _follow_path(round: Round, ticks: float) -> void:
	var motion := runtime.motion
	var last := motion.path_key_frame(round.path, motion.path_key_count(round.path) - 1) - 1.0
	round.path_time += ticks
	if round.path_time < last:
		round.life = 99.0
	else:
		round.path_time = last
		round.life = 0.0
	round.position = motion.path_position(round.path, round.path_time)


## The first object the segment crosses: `[object, point, part]` (part −1 for the whole box), or
## an empty array. Objects of Kurt's arena, alive, not flagged 0x30.
func _test_objects(start: Vector3, end: Vector3) -> Array:
	var best := []
	var best_distance := INF
	for obj in runtime.objects:
		if obj.dead or obj.arena != runtime.current_arena or obj.health == 0 or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		var bounds := runtime.get_world_bounds(obj)
		if bounds.intersects_segment(start, end) == null:
			continue
		var part := -1
		var point: Variant = null
		if obj.model:
			var parts := obj.get_part_bounds()
			for i in parts.size():
				if obj.hidden_parts & (1 << i):
					continue
				var part_point: Variant = runtime.get_world_bounds(obj, parts[i]).intersects_segment(start, end)
				if part_point != null and (point == null or start.distance_to(part_point) < start.distance_to(point)):
					point = part_point
					part = i
			if point == null:
				continue
		else:
			point = bounds.intersects_segment(start, end)
		var distance := start.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = [obj, point, part]
	return best


## A round hits an object (0x462708): grenades and the mortar explode; bullets take 8 hit points
## (not from objects with 65000 or more) and kill it at 0, else make sparks. The hit event is the
## part + 1 (`if_hit_part`).
func _hit_object(round: Round, obj: MDKObject, part: int, point: Vector3) -> void:
	obj.hit_event = part + 1 if part >= 0 else -2
	obj.hit_type = round.type
	obj.hit_direction = round.yaw
	obj.shot_part = part + 1
	obj.shot_point = point
	GameState.stats.sniper_hits += 1
	if round.type >= 2:
		_explode(round, 25.0, obj)
		return
	if obj.health < 65000:
		obj.health -= DAMAGE
	if obj.health <= 0:
		obj.health = 0
		GameState.count_enemy(obj.type_name, true)
		runtime.kill(obj, round.yaw + 180.0)
		_end(round, State.KILLED, 45.0)
	else:
		runtime.spark(point, 3, obj.labels[1])
		_end(round, State.HIT, 45.0)


## An explosion (0x4638cc): 150 damage to objects and triangle groups and 75 to Kurt within the
## radius, and the explosion effect at scale 2.
func _explode(round: Round, radius: float, source: MDKObject) -> void:
	runtime.items.blast(round.position, EXPLOSION_DAMAGE, radius, 6, HIT_EXPLOSION, source)
	runtime.items.blast(round.position, EXPLOSION_KURT_DAMAGE, radius, 1, HIT_EXPLOSION, source)
	runtime.spawn_explosion(runtime.current_arena, round.position, 2.0)
	runtime.play_sound_at("EXPLODE", round.position)
	_end(round, State.EXPLODED, 30.0)


func _end(round: Round, state: State, linger: float) -> void:
	round.state = state
	round.linger = linger
	round.watch = 30.0 if state == State.KILLED or state == State.HIT else 0.0
	if round.visual:
		round.visual.visible = false

## Kurt on the snowboard of level 4 (`XSNOWB`, `snowboard_update` 0x46ac4c). See
## docs/gameplay.md, "The snowboard".
##
## The board object's path only guides the heading `H`, which turns towards the path at 40°/s
## (faster carving into the turn, slower against it). Kurt steers with the carve angle `S` (±30°),
## which slides him sideways (`L`), and speeds up or brakes (`V`); slopes speed him up or slow him
## down. The board sits under his feet at the yaw `H + S`.
##
##   input ──▶ S ──▶ L (sideways)     path ──▶ H (heading)     slope, keys ──▶ V (forward)
class_name MDKSnowboard
extends RefCounted

const TICKS := 30.0
## Steering: ±30° at 4°/tick (reached over 15 ticks on the ground), back at 3°/tick.
const STEER_MAX := 30.0
const STEER_RATE := 4.0
## The mouse: 4 × clamp(dx / dt, ±4) °/tick (`input_read_axes` 0x408334), dx in the original's
## units: its walk turns 3° a unit.
const MOUSE_DEGREES := 3.0
const MOUSE_LIMIT := 4.0
const STEER_RAMP_TICKS := 15.0
const STEER_RETURN := 3.0
## Sideways speed `L = −S·V/96`, braked in the air by 0.0055556 per tick.
const SIDE_FACTOR := -0.8333 * 0.0125
const SIDE_AIR_BRAKE := 0.0055556
## Speeds (units/tick): cruise 1.5, up to 2.5 with the key (or locked), down to 1.1667 braking or
## uphill, up to 2.6667 downhill; 0.05 per tick², decay above cruise 0.0027778.
const CRUISE := 1.5
const FAST := 2.5
const SLOW := 1.16667
const DOWNHILL := 2.66667
const ACCELERATION := 0.05
const DECAY := 0.0027778
const SLOPE_ACCELERATION := 0.066667
## Gravity as when walking, and sticking to downhill floors steeper than nz 0.25.
const GRAVITY := 64.0
const MAX_FALL := 250.0
const STICK_NZ := 0.25
## The board's ends are 4 units from its middle; ground up to 3 units above them counts.
const BOARD_HALF := 4.0
const RAY_HEIGHT := 3.0
## The board pitches towards the ground at 90°/s, between −45° and 45°.
const PITCH_RATE := 90.0
const PITCH_LIMIT := 45.0
## Jump: 28.5 units/s up, the key counts up to 12 ticks before landing; not at the end of CMEAT_1.
const JUMP_SPEED := 28.5
const JUMP_BUFFER := 12
const NO_JUMP_ARENA := "CMEAT_1"
const NO_JUMP_Y := 2131.0
## Heading: 4/3 °/tick ± S/30 on the ground, 0.4 in the air; Kurt's yaw follows it at 360°/s.
const HEADING_RATE := 1.33333
const HEADING_CARVE := 1.33333 / 30.0 * 0.75
const HEADING_AIR := 0.4
const KURT_TURN := 360.0
## Kurt nudged back towards the path when stuck (moving under 0.5 units/tick at speed).
const UNSTICK_SPEED := 0.5
const UNSTICK_STEP := 2.0
## The board sits 0.25 below Kurt's feet.
const BOARD_DROP := 0.25
## Sounds: `SKITURN` beyond 22.5°, `SKILAND` after 15 ticks in the air, `SKI` stops after 7.
const TURN_SOUND := 22.5
const LAND_TICKS := 15
const QUIET_TICKS := 7
## Ramming: objects without these flags and with 0 < health < 65000 die; Kurt takes 5.
const RAM_SPARED := 0x40304000
const RAM_DAMAGE := 5
## `K_SURFJ` holds on frame 5 in the air, lands from frame 6 to 10.
const JUMP_HOLD_FRAME := 5
const JUMP_LAND_FRAME := 6
## The camera pivot dips by 0.2 a frame while `K_SURFJ` takes off, then comes back up by 1 u/s.
const PIVOT_DIP := 0.2

enum Pose { SURF, JUMP, LAND }

var board: MDKObject

var _runtime: MDKScriptRuntime
var _kurt: Kurt
var _speed := 0.0
var _side := 0.0
var _heading := 0.0
var _steer := 0.0
var _pitch := 0.0
var _turn_ticks := 0.0
var _jump_ticks := 0.0
var _air_ticks := 0.0
var _grounded := true
var _path_heading := 0.0
var _pose := Pose.SURF
var _frame := 0.0


func _init(runtime: MDKScriptRuntime, p_board: MDKObject) -> void:
	_runtime = runtime
	_kurt = runtime.kurt
	board = p_board
	_heading = board.yaw
	_path_heading = board.yaw


## One tick of riding (Kurt's physics step).
func update(delta: float) -> void:
	var dt := delta * TICKS
	var controls := not board.flags & MDKRides.FLAG_LOCKED
	_pitch -= absf(_steer) * 0.25

	_steer_board(controls, dt)
	if _grounded:
		_update_speed(controls, dt)
	else:
		_side = move_toward(_side, 0.0, SIDE_AIR_BRAKE * dt)

	# Forward and sideways, sticking to downhill floors, falling.
	var h := deg_to_rad(_heading)
	var move := Vector2(cos(h), sin(h)) * _speed + Vector2(sin(h), -cos(h)) * _side
	var vertical := maxf(_kurt.velocity.y - GRAVITY * delta, -MAX_FALL)
	if _kurt.is_on_floor():
		var n := MDKScriptRuntime.to_mdk(_kurt.get_floor_normal())
		var down := move.x * n.x + move.y * n.y
		if n.z > STICK_NZ and down > 0.0:
			vertical = minf(vertical, -down * TICKS)
	var previous := _position()
	_kurt.velocity = MDKMeshBuilder.to_godot(Vector3(move.x * TICKS, move.y * TICKS, 0.0))
	_kurt.velocity.y = vertical
	_kurt.move_and_slide()

	_update_pitch(delta)
	if _grounded:
		var k := sin(deg_to_rad(_pitch))
		if _pitch > 180.0 and _speed < DOWNHILL:
			_speed = minf(_speed - k * SLOPE_ACCELERATION * dt, DOWNHILL)
		elif _pitch > 0.0 and _pitch <= 180.0 and _speed > SLOW:
			_speed = maxf(_speed - k * SLOPE_ACCELERATION * dt, SLOW)

	_jump(controls, dt)
	_update_sounds(dt)
	if _pose == Pose.JUMP:
		_kurt.stop_firing()
	else:
		_kurt.update_gun()
	_follow_path(previous, dt)
	_turn(delta, dt)
	_place()
	_ram()
	_animate(dt)


## Kurt's feet (MDK coordinates), as he is now.
func _position() -> Vector3:
	return MDKScriptRuntime.to_mdk(_kurt.global_position)


## The carve angle `S`: the turn input (°/tick) turns it (ramping up over 15 ticks on the ground),
## the other way snaps it straight, and it goes back at 3°/tick.
func _steer_board(controls: bool, dt: float) -> void:
	# Mouse motion is used up either way, or Kurt would turn by all of it when he gets off.
	var mouse: float = -_kurt.take_mouse_turn()
	var turn := Input.get_axis(&"turn_left", &"turn_right")
	var strafe := Input.get_axis(&"strafe_left", &"strafe_right")
	var input := turn_input(mouse, turn, strafe, dt) if controls else 0.0
	if input == 0.0:
		_turn_ticks = 0.0
		_steer = move_toward(_steer, 0.0, STEER_RETURN * dt)
		return
	_turn_ticks += dt
	var right := input > 0.0
	if (right and _steer > 0.0) or (not right and _steer < 0.0):
		_steer = 0.0
		return
	var rate := input * (_turn_ticks * 2.0 / TICKS if _grounded and _turn_ticks < STEER_RAMP_TICKS else 1.0)
	_steer = clampf(_steer - rate * dt, -STEER_MAX, STEER_MAX)


## The turn input (°/tick, > 0 right; 0x5014ec): the mouse's 4 × clamp(dx / dt, ±4) when it moved
## (`mouse`: the walking turn in degrees, > 0 right), else the larger of the turn and strafe keys
## × 4 (the strafe on a tie). E.g. 1.5° of mouse in a tick: 2°/tick; a flick: 16°/tick.
static func turn_input(mouse: float, turn: float, strafe: float, dt: float) -> float:
	if mouse != 0.0 and dt > 0.0:
		return STEER_RATE * clampf(mouse / MOUSE_DEGREES / dt, -MOUSE_LIMIT, MOUSE_LIMIT)
	return STEER_RATE * (turn if absf(strafe) < absf(turn) else strafe)


## Speed on the ground: the keys speed up (to 2.5) or brake (to 1.1667), else back to cruise 1.5;
## locked controls speed up to 2.5 on their own. Carving slides sideways.
func _update_speed(controls: bool, dt: float) -> void:
	if _steer != 0.0:
		_side = _steer * SIDE_FACTOR * _speed
	if not controls:
		_speed = minf(_speed + ACCELERATION * dt, FAST)
		return
	var forward := Input.get_axis(&"move_back", &"move_forward")
	if forward > 0.0 and _speed < FAST:
		_speed = minf(_speed + ACCELERATION * dt, FAST)
	elif forward < 0.0 and _speed > SLOW:
		_speed = maxf(_speed - ACCELERATION * dt, SLOW)
	elif forward == 0.0:
		_speed = minf(_speed + ACCELERATION * dt, CRUISE) if _speed < CRUISE else maxf(_speed - DECAY * dt, CRUISE)


## The board's pitch from the ground under its ends (rays from 3 units above each end down to it),
## turning at 90°/s; any ground under the board means it's grounded.
func _update_pitch(delta: float) -> void:
	var p := _position()
	var yaw := deg_to_rad(_heading + _steer)
	var forward := Vector3(cos(yaw), sin(yaw), 0.0) * BOARD_HALF
	var front: Variant = _ground(p + forward)
	var back: Variant = _ground(p - forward)
	var v := Vector3.ZERO
	if front != null and back != null:
		v = front - back
	elif front != null:
		v = front - p
	elif back != null:
		v = p - back
	_grounded = front != null or back != null
	if not _grounded:
		return
	var target := fposmod(rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length())), 360.0)
	if _pitch > PITCH_LIMIT and _pitch < 180.0:
		target = PITCH_LIMIT
	elif _pitch >= 180.0 and _pitch < 360.0 - PITCH_LIMIT:
		target = 360.0 - PITCH_LIMIT
	_pitch = fposmod(wrapf(_pitch, -180.0, 180.0) + clampf(wrapf(target - _pitch, -180.0, 180.0), -PITCH_RATE * delta, PITCH_RATE * delta), 360.0)


## The ground under a board end: up to 3 units above it, or null.
func _ground(end: Vector3) -> Variant:
	var hit := _runtime.raycast(end + Vector3(0, 0, RAY_HEIGHT), end - Vector3(0, 0, 0.01))
	return MDKScriptRuntime.to_mdk(hit.position) if not hit.is_empty() else null


## Jumping: on the ground, within 12 ticks of pressing the key.
func _jump(controls: bool, dt: float) -> void:
	var blocked := _runtime.current_arena == NO_JUMP_ARENA and _position().y >= NO_JUMP_Y
	if not controls or not Input.is_action_pressed(&"jump") or blocked:
		_jump_ticks = 0.0
		return
	if _grounded and _jump_ticks <= JUMP_BUFFER:
		_kurt.velocity.y = JUMP_SPEED
		_kurt.global_position.y += 1.0
		_grounded = false
		_jump_ticks = 50.0
		_pose = Pose.JUMP
		_frame = 0.0
	_jump_ticks += dt


func _update_sounds(dt: float) -> void:
	var mixer := _runtime.mixer
	if not _grounded:
		_air_ticks += dt
		if _air_ticks >= QUIET_TICKS and mixer.is_playing("SKI"):
			mixer.stop("SKI")
			mixer.stop("SKITURN")
		return
	if _air_ticks >= LAND_TICKS:
		mixer.play("SKILAND", SoundMixer.Start.RESTART)
	_air_ticks = 0.0
	mixer.play("SKI", SoundMixer.Start.ONCE)
	if absf(_steer) > TURN_SOUND:
		mixer.play("SKITURN", SoundMixer.Start.ONCE)
	else:
		mixer.stop("SKITURN")


## The heading follows the board's path: the path time moves on to the point nearest to Kurt,
## the direction there is the path's heading; a stuck Kurt is nudged towards the path.
func _follow_path(previous: Vector3, dt: float) -> void:
	var motion := _runtime.motion
	if board.path == 0:
		return
	var last := motion.path_key_frame(board.path, motion.path_key_count(board.path) - 1)
	var t := board.path_time
	if t >= last:
		return
	var kurt := Vector2(_position().x, _position().y)
	var start := t
	for step: float in [1.0, 0.2]:
		while t + step < last and _distance(t + step, kurt) < _distance(t, kurt):
			t += step
	if t == start:
		return

	var here := _path_point(start)
	var ahead := _path_point(t + 0.2)
	board.path_time = t
	board.path_stop = roundi(t)
	_path_heading = rad_to_deg(atan2(ahead.y - here.y, ahead.x - here.x))
	var moved := Vector2(_position().x - previous.x, _position().y - previous.y).length()
	if _speed >= SLOW and dt > 0.0 and moved / dt < UNSTICK_SPEED:
		var nudge := (Vector2(here.x, here.y) - kurt).normalized() * UNSTICK_STEP
		_kurt.global_position += MDKMeshBuilder.to_godot(Vector3(nudge.x, nudge.y, 0.0))


func _path_point(t: float) -> Vector3:
	return _runtime.motion.path_position(board.path, t) + board.path_origin


func _distance(t: float, kurt: Vector2) -> float:
	var p := _path_point(t)
	return Vector2(p.x, p.y).distance_squared_to(kurt)


## The heading turns towards the path's (faster carving into the turn); Kurt faces the heading.
func _turn(delta: float, dt: float) -> void:
	var rate := HEADING_AIR
	if _grounded:
		var d := wrapf(_path_heading - _heading, -180.0, 180.0)
		rate = HEADING_RATE + (_steer if d >= 0.0 else -_steer) * HEADING_CARVE
	_heading = _turn_towards(_heading, _path_heading, maxf(rate, 0.0) * dt)
	var kurt_yaw := rad_to_deg(_kurt.yaw) + 90.0
	_kurt.yaw = deg_to_rad(_turn_towards(kurt_yaw, _heading, KURT_TURN * delta) - 90.0)


static func _turn_towards(from: float, to: float, step: float) -> float:
	return fposmod(from + clampf(wrapf(to - from, -180.0, 180.0), -step, step), 360.0)


## The board under Kurt's feet at the yaw `H + S`, its nose up while carving.
func _place() -> void:
	_pitch = fposmod(_pitch + absf(_steer) * 0.25, 360.0)
	board.mdk_position = _position() - Vector3(0, 0, BOARD_DROP)
	board.yaw = fposmod(_heading + _steer, 360.0)
	board.pitch = wrapf(_pitch, -180.0, 180.0)
	board.update_transform()
	_kurt.camera_roll.follow(wrapf(board.roll, -180.0, 180.0), 1.0 / TICKS)


## Whatever Kurt runs into dies, and he takes 5 damage.
func _ram() -> void:
	for i in _kurt.get_slide_collision_count():
		var body := _kurt.get_slide_collision(i).get_collider() as Node
		var obj := body.get_parent() as MDKObject if body else null
		if not obj or obj == board or obj.dead or obj.flags & RAM_SPARED or obj.health <= 0 or obj.health >= 65000:
			continue
		_runtime.kill(obj)
		_runtime.hurt_kurt(RAM_DAMAGE)


## `K_SURF` loops; `K_SURFJ` holds on frame 5 in the air and lands on frames 6–10.
func _animate(dt: float) -> void:
	_frame += dt
	match _pose:
		Pose.SURF:
			_kurt.camera_pivot = Kurt.CAMERA_PIVOT
			_kurt.show_animation("K_SURF", int(_frame) % 8)
		Pose.JUMP:
			_frame = minf(_frame, JUMP_HOLD_FRAME)
			if _grounded and _kurt.velocity.y <= 0.0:
				_pose = Pose.LAND if _frame > 3.0 else Pose.SURF
				_frame = JUMP_LAND_FRAME if _pose == Pose.LAND else 0.0
			_kurt.camera_pivot = jump_pivot(_frame, _kurt.camera_pivot, dt / TICKS)
			_kurt.show_animation("K_SURFJ", int(_frame))
		Pose.LAND:
			if _frame >= 11.0:
				_pose = Pose.SURF
				_frame = 0.0
			_kurt.camera_pivot = jump_pivot(_frame, _kurt.camera_pivot, dt / TICKS)
			_kurt.show_animation("K_SURFJ", int(_frame))


## The camera pivot at `K_SURFJ` frame `frame` (0x46ac4c), coming from `pivot` after `seconds`.
static func jump_pivot(frame: float, pivot: float, seconds: float) -> float:
	if frame < JUMP_HOLD_FRAME:
		return Kurt.CAMERA_PIVOT - int(frame) * PIVOT_DIP
	return minf(pivot + seconds, Kurt.CAMERA_PIVOT)


## Getting off (the script clears the rideable flag, or Kurt died): he keeps the board's speeds as
## his walking ones, and the board is thrown on at 1.1 × his velocity.
func get_off() -> void:
	for sound_name in ["SKI", "SKITURN", "SKILAND"]:
		_runtime.mixer.stop(sound_name)
	_kurt.camera_pivot = Kurt.CAMERA_PIVOT
	var y := deg_to_rad(rad_to_deg(_kurt.yaw) + 90.0)
	board.velocity = Vector3(_speed * cos(y) + _side * sin(y), _speed * sin(y) - _side * cos(y), 0.0) * TICKS * 1.1
	board.velocity.z = _kurt.velocity.y
	board.gravity = GRAVITY
	board.friction = 0.0
	board.mdk_position = _position()
	_kurt.get_off_board(_speed * TICKS, -_side * TICKS)

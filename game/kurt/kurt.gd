## Kurt Hectic, the player character ("Damp" in the original code).
##
## Movement follows the original (`damp_move`, `vel_accel`, `vel_friction`, `damp_vertical`), which
## runs at 30 ticks per second; the constants below are converted to seconds. See `docs/gameplay.md`.
class_name Kurt
extends CharacterBody3D

const TICKS := 30.0

## Forward, backward and strafe speeds (u/s) and accelerations (u/s²), normal and turbo.
const MAX_SPEED := 0.6667 * TICKS
const MAX_SPEED_TURBO := 1.3333 * TICKS
const ACCELERATION := 0.04444 * TICKS * TICKS
const ACCELERATION_TURBO := 0.08889 * TICKS * TICKS
## Deceleration when no key is held (u/s²): above `MAX_SPEED`, and below it.
const FRICTION_FAST := 0.17778 * TICKS * TICKS
const FRICTION_SLOW := 0.08889 * TICKS * TICKS
## Multiplier of the friction and strafe acceleration in the air.
const AIR_CONTROL := 0.75

## Keyboard turning (degrees/s and degrees/s²), normal and turbo.
const TURN_SPEED := 4.0 * TICKS
const TURN_SPEED_TURBO := 6.0 * TICKS
const TURN_ACCELERATION := 0.9 * TICKS * TICKS
const TURN_ACCELERATION_TURBO := 1.3 * TICKS * TICKS
const TURN_FRICTION_FAST := 1.6 * TICKS * TICKS
const TURN_FRICTION_SLOW := 0.55 * TICKS * TICKS
const MOUSE_SENSITIVITY := 0.15

## Vertical movement (u/s, u/s²).
const GRAVITY := 64.0
const MAX_FALL_SPEED := 250.0
const JUMP_VELOCITY := 40.0
## Releasing jump during the first ticks of a jump cuts it short.
const JUMP_HOLD_TICKS := 6
const JUMP_RELEASE_PENALTY := 3.333
## Falling faster than this starts the fall (or with jump held, opens the chute).
const FALL_START_SPEED := -16.0
const CHUTE_GRAVITY := 21.33
const CHUTE_FALL_SPEED := -8.0
const CHUTE_BRAKE := 256.0

## Seconds standing still before the idle animation plays.
const IDLE_DELAY := 6.0

enum State { STILL, IDLE, RUN, SIDE, TURN, JUMP, RUN_JUMP, FALL, CHUTE, LAND }

## Sprite animation used by each state, and whether it loops.
const STATE_ANIMATIONS := {
	State.STILL: ["K_STILL", false],
	State.IDLE: ["K_IDLE", false],
	State.RUN: ["K_RUN", true],
	State.SIDE: ["K_SIDE", true],
	State.TURN: ["K_TRN45", true],
	State.JUMP: ["K_JUMP", false],
	State.RUN_JUMP: ["K_RJMP", false],
	State.FALL: ["K_FALL", true],
	State.CHUTE: ["K_FLOATC", true],
	State.LAND: ["K_LAND", false],
}

## Yaw in radians (0 faces -Z).
var yaw := 0.0
## Forward and strafe speeds (u/s) in Kurt's frame, and turning speed (degrees/s).
var forward_speed := 0.0
var strafe_speed := 0.0
var turn_speed := 0.0
var state := State.STILL
var state_time := 0.0
## Animation position in frames.
var animation_frame := 0.0
var chute_open := false
## Health (the original's `0x574324`; damage isn't scaled by the difficulty yet).
var health := 100
var sprites: MDKBni
## Returns a sound by name (see `Level.get_sound()`).
var get_sound: Callable

var _mouse_turn := 0.0
var _jump_ticks_left := 0
var _jump_released := true
## The original alternates two pairs of footstep sounds (`damp_animate`).
var _footstep_pair := false
var _sound_players: Array[AudioStreamPlayer] = []

@onready var sprite: SpriteAnimator = $Sprite


func _ready() -> void:
	# Wait for `setup()`.
	set_physics_process(false)


func setup(p_sprites: MDKBni, palette: MDKPalette, p_get_sound: Callable) -> void:
	sprites = p_sprites
	get_sound = p_get_sound
	for i in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sound_players.push_back(player)
	sprite.setup(palette)
	_set_state(State.STILL)
	set_physics_process(true)


func teleport(p_position: Vector3, p_yaw: float) -> void:
	global_position = p_position
	yaw = p_yaw
	velocity = Vector3.ZERO
	forward_speed = 0.0
	strafe_speed = 0.0
	reset_physics_interpolation()


## Damage from aliens (`hurt_kurt`).
func hurt(damage: int) -> void:
	health = maxi(health - damage, 0)


## Facing direction (horizontal).
func get_facing() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_turn -= event.screen_relative.x * MOUSE_SENSITIVITY


func _physics_process(delta: float) -> void:
	var turbo := Input.is_action_pressed(&"turbo")
	var on_floor := is_on_floor()
	_update_turning(delta, turbo)

	var forward_input := Input.get_axis(&"move_back", &"move_forward")
	var strafe_input := Input.get_axis(&"strafe_left", &"strafe_right")
	var air := 1.0 if on_floor else AIR_CONTROL
	forward_speed = _accelerate(forward_speed, forward_input, turbo, 1.0, air, delta)
	strafe_speed = _accelerate(strafe_speed, strafe_input, turbo, air, air, delta)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var horizontal := get_facing() * forward_speed + right * strafe_speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	_update_vertical(delta, on_floor)
	move_and_slide()
	_update_state(delta, forward_input, strafe_input)


## Keyboard turning accelerates up to a maximum speed; the mouse turns directly.
func _update_turning(delta: float, turbo: bool) -> void:
	var turn_input := Input.get_axis(&"turn_right", &"turn_left")
	if is_zero_approx(turn_input):
		var friction := TURN_FRICTION_FAST if absf(turn_speed) > TURN_SPEED else TURN_FRICTION_SLOW
		turn_speed = move_toward(turn_speed, 0.0, friction * delta)
	else:
		var max_speed := TURN_SPEED_TURBO if turbo else TURN_SPEED
		var acceleration := TURN_ACCELERATION_TURBO if turbo else TURN_ACCELERATION
		turn_speed = clampf(turn_speed + turn_input * acceleration * delta, -max_speed, max_speed)
	yaw += deg_to_rad(turn_speed * delta + _mouse_turn)
	_mouse_turn = 0.0


## Accelerates a speed towards `input × max speed`, or applies friction without input (`vel_accel`,
## `vel_friction`). Pressing the opposite direction reverses immediately.
func _accelerate(speed: float, input: float, turbo: bool, accel_factor: float, friction_factor: float, delta: float) -> float:
	if is_zero_approx(input):
		var friction := FRICTION_FAST if absf(speed) > MAX_SPEED else FRICTION_SLOW
		return move_toward(speed, 0.0, friction * friction_factor * delta)
	var acceleration := (ACCELERATION_TURBO if turbo else ACCELERATION) * accel_factor
	var max_speed := MAX_SPEED_TURBO if turbo else MAX_SPEED
	if speed * input < 0.0:
		speed = 0.0
	return clampf(speed + input * acceleration * delta, -max_speed, max_speed)


func _update_vertical(delta: float, on_floor: bool) -> void:
	var jump_held := Input.is_action_pressed(&"jump")
	if not jump_held:
		_jump_released = true
		if _jump_ticks_left > 0:
			velocity.y -= _jump_ticks_left * JUMP_RELEASE_PENALTY
			_jump_ticks_left = 0

	if on_floor:
		chute_open = false
		if jump_held and _jump_released:
			velocity.y = JUMP_VELOCITY
			_jump_ticks_left = JUMP_HOLD_TICKS
			_jump_released = false
		return

	if _jump_ticks_left > 0:
		_jump_ticks_left = maxi(0, _jump_ticks_left - int(ceil(delta * TICKS)))
	if not chute_open and jump_held and _jump_released and velocity.y < FALL_START_SPEED:
		chute_open = true
		play_sound("CHUTEOUT")
	if chute_open:
		velocity.y -= CHUTE_GRAVITY * delta
		if velocity.y < CHUTE_FALL_SPEED:
			velocity.y = minf(velocity.y + CHUTE_BRAKE * delta, CHUTE_FALL_SPEED)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)


func _update_state(delta: float, forward_input: float, strafe_input: float) -> void:
	state_time += delta
	var animation := sprites.get_animation(STATE_ANIMATIONS[state][0])
	var animation_done := animation_frame >= animation.frame_count - 1
	if not is_on_floor():
		if chute_open:
			_set_state(State.CHUTE)
		elif velocity.y > 0.0 and state not in [State.JUMP, State.RUN_JUMP, State.FALL]:
			_set_state(State.RUN_JUMP if absf(forward_speed) > 1.0 else State.JUMP)
		elif velocity.y < FALL_START_SPEED and (state not in [State.JUMP, State.RUN_JUMP] or animation_done):
			_set_state(State.FALL)
	elif state in [State.JUMP, State.RUN_JUMP, State.FALL, State.CHUTE]:
		if state == State.CHUTE:
			play_sound("CHUTEIN")
		play_sound("LAND")
		_set_state(State.LAND)
	elif state == State.LAND and not animation_done and is_zero_approx(forward_input) and is_zero_approx(strafe_input):
		pass
	elif not is_zero_approx(forward_input) or absf(forward_speed) > 1.0:
		_set_state(State.RUN)
	elif not is_zero_approx(strafe_input) or absf(strafe_speed) > 1.0:
		_set_state(State.SIDE)
		sprite.flip_h = strafe_speed < 0.0
	elif absf(turn_speed) > 1.0:
		_set_state(State.TURN)
	elif state == State.IDLE and not animation_done:
		pass
	elif state == State.STILL and state_time > IDLE_DELAY:
		_set_state(State.IDLE)
	elif state != State.STILL:
		_set_state(State.STILL)

	animation = sprites.get_animation(STATE_ANIMATIONS[state][0])
	match state:
		State.RUN:
			# `damp_run_anim_frame`: the run animation follows the speed (backwards when backing up).
			var u := absf(forward_speed) / TICKS * 1.5
			var rate := 0.75 * u + 0.25 if u <= 1.0 else 0.25 * u + 0.75
			var previous := posmod(int(floor(animation_frame)), animation.frame_count)
			animation_frame += rate * TICKS * delta * (-1.0 if forward_speed < 0.0 else 1.0)
			var current := posmod(int(floor(animation_frame)), animation.frame_count)
			# Footsteps on frames 0 and 13.
			if current != previous:
				if current == 0:
					play_sound("FOOT3" if _footstep_pair else "FOOT1")
				elif current == 13:
					play_sound("FOOT4" if _footstep_pair else "FOOT2")
					_footstep_pair = not _footstep_pair
		State.TURN:
			# The turning animation covers 45° of rotation.
			animation_frame = rad_to_deg(yaw) / 45.0 * animation.frame_count
		_:
			animation_frame += TICKS * delta
	var frame := int(floor(animation_frame))
	if not STATE_ANIMATIONS[state][1]:
		frame = mini(frame, animation.frame_count - 1)
	sprite.show_frame(animation, frame)


## Plays a sound (by name, from the level's sounds) without position.
func play_sound(sound_name: String) -> void:
	var stream: AudioStream = get_sound.call(sound_name)
	if not stream:
		return
	for player in _sound_players:
		if not player.playing:
			player.stream = stream
			player.play()
			return


func _set_state(new_state: State) -> void:
	if new_state == state and state_time > 0.0:
		return
	state = new_state
	state_time = 0.0
	animation_frame = 0.0
	if state != State.SIDE:
		sprite.flip_h = false

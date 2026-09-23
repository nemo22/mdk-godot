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
## Out of an updraft Kurt rises at most this fast.
const UPDRAFT_EXIT_SPEED := 40.0

## Sliding (`damp_buttslide`, started by the wind zones): the slide velocity grows by the square of
## the slope push (`10 × floor normal`) and of the wind, and brakes by 2 u/s² without either.
const SLIDE_SLOPE := 10.0
const SLIDE_FRICTION := 2.0
## Speed cap: 50 by default, raised by 10/s up to 80 while accelerating, lowered by 25/s down to 15
## while braking, and back towards 50 by 20/s without input.
const SLIDE_CAP := 50.0
const SLIDE_CAP_RANGE := Vector2(15.0, 80.0)
const SLIDE_CAP_RISE := 10.0
const SLIDE_CAP_FALL := 25.0
const SLIDE_CAP_RELAX := 20.0
## Kurt accelerates by 35 u/s² (above 15 u/s), brakes by 15 u/s² (down to 15 u/s) and turns by 45°/s.
const SLIDE_ACCELERATION := 35.0
const SLIDE_BRAKE := 15.0
const SLIDE_MIN_SPEED := 15.0
const SLIDE_TURN := 45.0
## He falls twice as fast as usual, and the slide ends after 20 ticks in the air.
const SLIDE_GRAVITY := 128.0
const SLIDE_AIR_TICKS := 20.0
## `BUTSLIDE` plays at 11025 Hz, or at 15000 Hz while accelerating.
const SLIDE_PITCH := 15000.0 / 11025.0

## Seconds standing still before the idle animation plays.
const IDLE_DELAY := 6.0

# Sniper mode (`0x573a60`, controls 0x467384, see docs/gameplay.md "Sniper mode").
## The eye is this high above Kurt's feet (`0x573b7c`).
const SNIPER_EYE_HEIGHT := 4.0
const SNIPER_PITCH_LIMIT := 50.0
## Sidestepping only, at a quarter of the running speed.
const SNIPER_STRAFE := 0.25
## Looking around: degrees per second (per tick in the original: 0.4/0.6 per tick, at most 4/6),
## scaled by the zoom × 0.416667.
const SNIPER_LOOK_ACCELERATION := 0.4 * TICKS * TICKS
const SNIPER_LOOK_ACCELERATION_TURBO := 0.6 * TICKS * TICKS
const SNIPER_LOOK_SPEED := 4.0 * TICKS
const SNIPER_LOOK_SPEED_TURBO := 6.0 * TICKS
const SNIPER_LOOK_FRICTION_SLOW := 1.0667 * TICKS * TICKS
const SNIPER_LOOK_FRICTION_FAST := 1.6 * TICKS * TICKS
const SNIPER_LOOK_SCALE := 0.416667
## Zoom (`0x57391c`, the inverse of the magnification): 1 when sniping starts, down to 0.25 (4×).
const ZOOM_MIN := 0.25
## The zoom speed grows by 0.01 per tick up to 0.15 while a zoom key is held and decays by 0.015.
const ZOOM_ACCELERATION := 0.01
const ZOOM_MAX_SPEED := 0.15
const ZOOM_DECAY := 0.015
## The port also zooms with the mouse wheel: a notch holds the zoom key for this many ticks.
const ZOOM_WHEEL_TICKS := 6.0
## Falling this fast (or rising) ends sniper mode.
const SNIPER_FALL_SPEED := -30.0
## Rounds in the clip, and the clip timer (`0x5743eb`): it drops by 4 per second, a shot adds 1
## (a quarter of a second between shots), an empty clip sets it to 3.
const CLIP_SIZE := 3
const CLIP_DECAY := 4.0

enum State { STILL, IDLE, RUN, SIDE, TURN, JUMP, RUN_JUMP, FALL, CHUTE, LAND, SHOT, RUN_FIRE, DEAD, THROW, KNOCKED,
		SLIP, SLIDE, SLIDE_FAST, SLIDE_BRAKE, HANG }

# Ledge grab (`damp_ledge_grab` 0x469868, climbing in `damp_animate` state 800). See
# docs/gameplay.md ("Ledge grab").
## The ledge is looked for this high above the feet (`0x49798c`), 1 to 3 units ahead.
const LEDGE_HEIGHT := 4.6041665
const LEDGE_SPEED := -0.25
const LEDGE_FLAT := 0.85
const LEDGE_ANGLE := 30.0
## Climbing (`K_HANG`, 2 ticks per frame): the height and the backward offset of each frame pair
## (`0x491f34`, `0x491f74`), scaled by 0.708333 × 0.5 per tick.
const CLIMB_HEIGHTS := [0.374, 0.326, 0.292, 0.311, 0.677, 1.263, 2.754, 4.172, 4.903, 5.343, 5.711,
		6.001, 6.212, 6.345, 6.406, 6.417]
const CLIMB_BACK := [0.685, 0.383, 0.167, 0.254, 0.635, 1.053, 0.847, 0.514, 0.17, -0.125, -0.501,
		-0.825, -1.066, -1.221, -1.293, -1.305]
const CLIMB_SCALE := 0.708333 * 0.5

## Frame of `K_SPWEP` at which the item leaves Kurt's hand (`damp_animate`).
const THROW_FRAME := 8

## Knocking down (`damp_control` 0x4664xx): the damage taken adds up (`0x573b20`, draining by 2 per
## second, at most 5); at 5 Kurt is knocked down (state 901: `K_BANG` then `K_BFLIP`) and is
## invulnerable for 3 seconds. In the air it only happens within 13 units of a floor, and he's
## slammed onto it at 64 u/s.
const KNOCKDOWN_DAMAGE := 5.0
const KNOCKDOWN_DRAIN := 2.0
const KNOCKDOWN_INVULNERABILITY := 3.0
const KNOCKDOWN_FLOOR_DISTANCE := 13.0
const KNOCKDOWN_SLAM_SPEED := -64.0
## A push (`push_kurt`, `0x573c08`) slows down by 0.1 u/tick per tick.
const PUSH_DRAIN := 0.1 * TICKS * TICKS

## Muzzle flash (`K_MUZZF`) offsets in the states that don't show the chain gun firing by
## themselves (`damp_animate`): a random offset of 0–4 pixels is added. `SHOT` and `RUN_FIRE` have
## the flash in their frames.
const MUZZLE_OFFSETS := {
	State.TURN: Vector2i(0, 0),
	State.SIDE: Vector2i(0, 0),
	State.FALL: Vector2i(40, 6),
	State.JUMP: Vector2i(0, 0),
	State.RUN_JUMP: Vector2i(0, -10),
	State.CHUTE: Vector2i(20, 0),
}

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
	State.SHOT: ["K_SHOT", true],
	State.RUN_FIRE: ["K_RUNFIR", true],
	State.DEAD: ["K_BANG", false],
	State.THROW: ["K_SPWEP", false],
	State.KNOCKED: ["K_BANG", false],
	State.SLIP: ["K_SLIP", false],
	State.SLIDE: ["K_SLIDE", true],
	State.SLIDE_FAST: ["K_FSLIDE", true],
	State.SLIDE_BRAKE: ["K_BSLIDE", true],
	State.HANG: ["K_HANG", false],
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
## The chain gun is firing (`0x573a38`).
var firing := false
var inventory := KurtInventory.new()
## Red flash after hits (`0x573b70`: +25 per damage point, 75–180, -4 per tick); once Kurt is dead
## it's the fade of the skull, and the level restarts at 255.
var hurt_flash := 0.0
## White flash of the screen (`0x573b68`: the nuke, `screen_flash`), fading by 4 per tick.
var white_flash := 0.0
## Invulnerability time in seconds (`0x573bd4`).
var invulnerable := 0.0
## Damage taken recently (`0x573b20`), see `KNOCKDOWN_DAMAGE`.
var knock_damage := 0.0
## Horizontal push (u/s, Godot's XZ plane) while knocked down.
var push := Vector2.ZERO
signal died
## Kurt uses the selected item (0x46ce78): the scripts runtime throws it.
signal item_used
## Kurt presses "use" again while the World's Most Interesting Bomb is out (0x43f258).
signal bomb_triggered
## Whether an item may be used now (the runtime says no while a thrown item is active).
var can_use_item: Callable
## Fans (`updraft_query`, set by the scripts runtime): `(vertical speed, dt)` → Kurt's new
## vertical speed, or NAN outside them.
var updraft: Callable
## Kurt slides on his back (`0x573be8`, state 807): the wind zones start it.
## Kurt stands still and ignores the controls (cutscenes).
var frozen := false
## Sniper mode: on, the view's pitch in degrees (positive looks down, `0x573918`), the zoom, the
## rounds loaded and the clip timer.
var sniping := false
var sniper_pitch := 0.0
var zoom := 1.0
var zoom_limit := ZOOM_MIN
var clip_rounds := 0
var clip_time := 0.0
## Fires a sniper round: `func(ammo_type: int) -> bool` (false when no slot is free).
var sniper_fire: Callable
var _look_speed := Vector2.ZERO
var _mouse_look := Vector2.ZERO
var _zoom_speed := 0.0
## Mouse wheel zoom: ticks left and direction (−1 in, 1 out). The wheel then doesn't change the ammo.
var _wheel_ticks := 0.0
var _wheel_direction := 0.0
var _wheel_used := false
var _shot_ticks := 0
var _breath_player: AudioStreamPlayer
var _zoom_player: AudioStreamPlayer
var sliding := false
## Slide velocity in MDK coordinates (`0x573bf0`), its speed cap and the smoothed floor normal.
var slide_velocity := Vector2.ZERO
var _slide_cap := SLIDE_CAP
var _slide_normal := Vector3(0.0, 0.0, 1.0)
var _slide_push := Vector2.ZERO
var _slide_air := 0.0
var sprites: MDKBni
## Returns a sound by name (see `Level.get_sound()`).
var get_sound: Callable

var _mouse_turn := 0.0
## Ticks since Kurt grabbed a ledge (`0x573a78`).
var _climb_ticks := 0
## Object bodies Kurt is inside of (an object moved into him): he doesn't collide with them until
## he's out, like the original's box sweeps, instead of being pushed out (maybe through the floor).
var _inside_bodies: Array[RID] = []
var _jump_ticks_left := 0
var _jump_released := true
## The original alternates two pairs of footstep sounds (`damp_animate`).
var _footstep_pair := false
var _sound_players: Array[AudioStreamPlayer] = []
var _gun_player: AudioStreamPlayer
## `FAN` loops while Kurt is in an updraft; `BUTSLIDE`/`BUTBRAKE` while he slides.
var _fan_player: AudioStreamPlayer
var _slide_player: AudioStreamPlayer
var _gun_super := false
var _muzzle_frame := 0
var _ticks := 0

@onready var sprite: SpriteAnimator = $Sprite
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var muzzle: SpriteAnimator = $Muzzle


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
	_gun_player = AudioStreamPlayer.new()
	add_child(_gun_player)
	_fan_player = AudioStreamPlayer.new()
	add_child(_fan_player)
	_slide_player = AudioStreamPlayer.new()
	add_child(_slide_player)
	_breath_player = AudioStreamPlayer.new()
	add_child(_breath_player)
	_zoom_player = AudioStreamPlayer.new()
	add_child(_zoom_player)
	sprite.setup(palette)
	muzzle.setup(palette)
	muzzle.visible = false
	_set_state(State.STILL)
	set_physics_process(true)


## Stops firing the chain gun.
func stop_firing() -> void:
	leave_sniper()
	firing = false
	_gun_player.stop()
	muzzle.visible = false


func teleport(p_position: Vector3, p_yaw: float) -> void:
	global_position = p_position
	yaw = p_yaw
	velocity = Vector3.ZERO
	forward_speed = 0.0
	strafe_speed = 0.0
	reset_physics_interpolation()


## Damage from aliens (`hurt_kurt`).
## Damage from aliens (`hurt_kurt` 0x46a604): 2/3 on easy (at least 1), double on hard.
func hurt(damage: int) -> void:
	if health == 0:
		return
	if invulnerable > 0.0 or state in [State.DEAD, State.KNOCKED]:
		knock_damage = 0.0
		return
	match inventory.difficulty:
		0:
			damage = maxi(damage * 2 / 3, 1)
		2:
			damage *= 2
	if damage > 0:
		hurt_flash = clampf(hurt_flash + damage * 25, 75.0, 180.0)
	health = maxi(health - damage, 0)
	knock_damage += damage


## Facing direction (horizontal).
func get_facing() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.screen_relative * MOUSE_SENSITIVITY * Settings.mouse_sensitivity
		if Settings.invert_mouse:
			motion.y = -motion.y
		if sniping:
			_mouse_look += motion * zoom
		else:
			_mouse_turn -= motion.x
	elif sniping and event is InputEventMouseButton and event.pressed 			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		_wheel_ticks = ZOOM_WHEEL_TICKS if direction != _wheel_direction else _wheel_ticks + ZOOM_WHEEL_TICKS
		_wheel_direction = direction
		_wheel_used = true


func _physics_process(delta: float) -> void:
	invulnerable = maxf(invulnerable - delta, 0.0)
	if frozen:
		velocity = Vector3.ZERO
		return
	if state == State.DEAD:
		leave_sniper()
		_update_death(delta)
		return
	hurt_flash = maxf(hurt_flash - 4.0 * TICKS * delta, 0.0)
	white_flash = maxf(white_flash - 4.0 * TICKS * delta, 0.0)
	_update_knock_damage(delta)
	var turbo := Input.is_action_pressed(&"turbo")
	var on_floor := is_on_floor()
	if Input.is_action_just_pressed(&"sniper_mode"):
		if sniping:
			leave_sniper(true)
		else:
			_enter_sniper(on_floor)
	if sniping:
		_update_sniper(delta, turbo, on_floor)
		return
	if sliding:
		_update_slide(delta, on_floor)
		_update_inside_bodies()
		move_and_slide()
		_update_slide_state(delta)
		_update_muzzle()
		return
	if state == State.HANG:
		_update_climb(delta)
		return
	_update_turning(delta, turbo)

	var forward_input := Input.get_axis(&"move_back", &"move_forward")
	var strafe_input := Input.get_axis(&"strafe_left", &"strafe_right")
	if state in [State.THROW, State.KNOCKED]:
		forward_input = 0.0
		strafe_input = 0.0
	var air := 1.0 if on_floor else AIR_CONTROL
	forward_speed = _accelerate(forward_speed, forward_input, turbo, 1.0, air, delta)
	strafe_speed = _accelerate(strafe_speed, strafe_input, turbo, air, air, delta)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var horizontal := get_facing() * forward_speed + right * strafe_speed
	velocity.x = horizontal.x + push.x
	velocity.z = horizontal.z + push.y
	push = Vector2(move_toward(push.x, 0.0, PUSH_DRAIN * delta), move_toward(push.y, 0.0, PUSH_DRAIN * delta))

	_update_vertical(delta, on_floor)
	_update_inside_bodies()
	var previous := global_position
	move_and_slide()
	if _grab_ledge(previous):
		return
	_update_items()
	_update_firing()
	_update_state(delta, forward_input, strafe_input)
	_update_muzzle()


## Grabs a ledge (`damp_ledge_grab`): falling (at least 0.25 u/s) while moving forward, the path
## of a point 4.6 above the feet and 1, 2 or 3 units ahead crosses a flat surface (|nz| ≥ 0.85);
## the edge towards Kurt must be faced within 30° and there must be room above it. Kurt then hangs
## 1 unit from the edge, 4.6 below it, facing it.
func _grab_ledge(previous: Vector3) -> bool:
	if velocity.y > LEDGE_SPEED or forward_speed <= 0.0 or is_on_floor() or health == 0 			or state in [State.DEAD, State.KNOCKED, State.THROW, State.HANG]:
		return false
	var space := get_world_3d().direct_space_state
	var facing := get_facing()
	var up := Vector3.UP * LEDGE_HEIGHT
	for i in range(1, 4):
		var ray := PhysicsRayQueryParameters3D.create(previous + up + facing * i, global_position + up + facing * i,
				MDKScriptRuntime.LEVEL_LAYER)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		if absf(hit.normal.y) < LEDGE_FLAT:
			return false
		return _hang_from(hit.position, facing * i)
	return false


## Finds the edge between the ledge point `top` and Kurt (`step` back), checks the angle and the
## room, and hangs Kurt from it.
func _hang_from(top: Vector3, step: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	# The edge: the last point on the way back to Kurt that still has the ledge under it.
	var edge := top
	var samples := 40
	for k in range(1, samples + 1):
		var point := top - step * (float(k) / samples)
		var down := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 0.5,
				MDKScriptRuntime.LEVEL_LAYER)
		if space.intersect_ray(down).is_empty():
			break
		edge = point
	# Kurt faces the wall under the edge (the edge's direction − 90°), within 30° of his yaw.
	var facing := get_facing()
	var wall_from := edge - step + Vector3.DOWN * 1.0
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(wall_from, wall_from + step * 1.5,
			MDKScriptRuntime.LEVEL_LAYER))
	if not wall.is_empty() and absf(wall.normal.y) < 0.5:
		var into := Vector3(-wall.normal.x, 0.0, -wall.normal.z).normalized()
		if rad_to_deg(facing.angle_to(into)) > LEDGE_ANGLE:
			return false
		facing = into
	# Room above the edge: a box of 1 × 1 × 4 from 1 unit before it to half a unit past it, 0.5–4.5
	# above it.
	var room := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 4.0, 1.0)
	room.shape = box
	room.collision_mask = MDKScriptRuntime.LEVEL_LAYER
	for t: float in [-0.5, 0.0, 0.5]:
		room.transform = Transform3D(Basis(), edge + facing * t + Vector3.UP * 2.5)
		if not space.intersect_shape(room, 1).is_empty():
			return false
	yaw = atan2(-facing.x, -facing.z)
	forward_speed = 0.0
	strafe_speed = 0.0
	velocity = Vector3.ZERO
	global_position = edge - facing + Vector3.DOWN * LEDGE_HEIGHT
	firing = false
	_gun_player.stop()
	muzzle.visible = false
	chute_open = false
	_climb_ticks = 0
	_set_state(State.HANG)
	sprite.show_frame(sprites.get_animation("K_HANG"), 0)
	return true


## Climbs up the ledge (state 800): `K_HANG` at 2 ticks per frame, moving by the climb tables.
func _update_climb(delta: float) -> void:
	var animation := sprites.get_animation("K_HANG")
	state_time += delta
	var ticks := int(state_time * TICKS) - _climb_ticks
	var facing := get_facing()
	for i in ticks:
		_climb_ticks += 1
		var k := (_climb_ticks + 1) >> 1
		if k < 15:
			global_position.y += (CLIMB_HEIGHTS[k] - CLIMB_HEIGHTS[k - 1]) * CLIMB_SCALE
			global_position -= facing * (CLIMB_BACK[k] - CLIMB_BACK[k - 1]) * CLIMB_SCALE
	velocity = Vector3.ZERO
	var last := animation.frame_count * 2 - 1
	if _climb_ticks >= last:
		_set_state(State.STILL)
		return
	sprite.show_frame(animation, mini(_climb_ticks / 2, animation.frame_count - 1))


func _update_inside_bodies() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape.shape
	query.transform = _shape.global_transform
	query.collision_mask = 2
	var inside: Array[RID] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		inside.push_back(hit.rid)
	for rid in _inside_bodies:
		if rid not in inside:
			PhysicsServer3D.body_remove_collision_exception(get_rid(), rid)
	for rid in inside:
		if rid not in _inside_bodies:
			PhysicsServer3D.body_add_collision_exception(get_rid(), rid)
	_inside_bodies = inside


## Knocks Kurt down when the damage taken recently reaches 5 (see `KNOCKDOWN_DAMAGE`).
func _update_knock_damage(delta: float) -> void:
	if health > 0 and knock_damage >= KNOCKDOWN_DAMAGE and state not in [State.KNOCKED, State.DEAD]:
		var knocked := is_on_floor()
		if not knocked:
			var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * KNOCKDOWN_FLOOR_DISTANCE, MDKScriptRuntime.LEVEL_LAYER)
			if get_world_3d().direct_space_state.intersect_ray(query):
				knocked = true
				velocity.y = minf(velocity.y, KNOCKDOWN_SLAM_SPEED)
		if knocked:
			knock_down()
			return
	knock_damage = minf(knock_damage, KNOCKDOWN_DAMAGE)
	knock_damage = maxf(knock_damage - KNOCKDOWN_DRAIN * delta, 0.0)


## Enters sniper mode (`damp_move` 0x46883c): only standing on a floor, not knocked down, sliding
## or throwing. Kurt stops firing and shows `SNIPERON` (state 803); his sprite isn't drawn.
func _enter_sniper(on_floor: bool) -> void:
	if not on_floor or sliding or health == 0 or state in [State.KNOCKED, State.DEAD, State.THROW]:
		return
	stop_firing()
	sniping = true
	forward_speed = 0.0
	strafe_speed = 0.0
	_look_speed = Vector2.ZERO
	_mouse_look = Vector2.ZERO
	_mouse_turn = 0.0
	_zoom_speed = 0.0
	_wheel_ticks = 0.0
	sniper_pitch = 0.0
	zoom = 1.0
	clip_rounds = 0
	clip_time = 0.0
	_set_state(State.STILL)
	sprite.visible = false
	play_sound("SNIPERON")
	_breath_player.stream = _looped(get_sound.call("BREATH"))
	if _breath_player.stream:
		_breath_player.play()


## Leaves sniper mode (0x4645c8): on the sniper key (with `SNIPEROFF`), when Kurt falls, is
## knocked down or dies, and in cutscenes.
func leave_sniper(with_sound := false) -> void:
	if not sniping:
		return
	sniping = false
	sprite.visible = true
	strafe_speed = 0.0
	_breath_player.stop()
	_zoom_player.stop()
	if with_sound:
		play_sound("SNIPEROFF")


## The eye in sniper mode (Godot space): 4 units above the feet, and a little forward when looking
## down (`5 × (1 − cos pitch)`, as the normal camera).
func get_sniper_eye() -> Vector3:
	var eye := get_global_transform_interpolated().origin + Vector3.UP * SNIPER_EYE_HEIGHT
	if sniper_pitch > 0.0:
		eye += get_facing() * 5.0 * (1.0 - cos(deg_to_rad(sniper_pitch)))
	return eye


## Sniper controls (0x467384): Kurt only sidesteps; the turn keys and the forward/back keys (or the
## mouse) turn and tilt the view, slower the more it's zoomed in; the zoom keys zoom.
func _update_sniper(delta: float, turbo: bool, on_floor: bool) -> void:
	if not on_floor and (velocity.y < SNIPER_FALL_SPEED or velocity.y > 1.0):
		leave_sniper()
	var look := Vector2(Input.get_axis(&"turn_left", &"turn_right"), -Input.get_axis(&"move_back", &"move_forward"))
	for axis in 2:
		_look_speed[axis] = _look_accelerate(_look_speed[axis], look[axis], turbo, delta)
	var scale := zoom * SNIPER_LOOK_SCALE * delta
	yaw -= deg_to_rad(_look_speed.x * scale + _mouse_look.x)
	sniper_pitch = clampf(sniper_pitch + _look_speed.y * scale + _mouse_look.y, -SNIPER_PITCH_LIMIT, SNIPER_PITCH_LIMIT)
	_mouse_look = Vector2.ZERO
	_update_zoom(delta)
	if not _wheel_used:
		if Input.is_action_just_pressed(&"item_next"):
			select_ammo(1)
		elif Input.is_action_just_pressed(&"item_prev"):
			select_ammo(-1)
	_wheel_used = false
	var strafe_input := Input.get_axis(&"strafe_left", &"strafe_right")
	strafe_speed = _accelerate(strafe_speed, strafe_input, turbo, 1.0, 1.0, delta)
	var max_strafe := (MAX_SPEED_TURBO if turbo else MAX_SPEED) * SNIPER_STRAFE
	strafe_speed = clampf(strafe_speed, -max_strafe, max_strafe)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	velocity.x = right.x * strafe_speed + push.x
	velocity.z = right.z * strafe_speed + push.y
	velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED) if not on_floor else 0.0
	_update_inside_bodies()
	move_and_slide()
	_update_clip(delta)


func _look_accelerate(speed: float, input: float, turbo: bool, delta: float) -> float:
	if is_zero_approx(input):
		var friction := SNIPER_LOOK_FRICTION_FAST if absf(speed) > SNIPER_LOOK_SPEED else SNIPER_LOOK_FRICTION_SLOW
		return move_toward(speed, 0.0, friction * delta)
	var max_speed := SNIPER_LOOK_SPEED_TURBO if turbo else SNIPER_LOOK_SPEED
	if speed * input < 0.0:
		speed = 0.0
	return clampf(speed + input * (SNIPER_LOOK_ACCELERATION_TURBO if turbo else SNIPER_LOOK_ACCELERATION) * delta, -max_speed, max_speed)


## The zoom (0x4687a4): zooming out multiplies it by `1 + v` each tick, zooming in divides it by
## `1 + v`, between 1 and the limit (0.25, or less to see a far target better, 0x4678b0).
func _update_zoom(delta: float) -> void:
	var ticks := delta * TICKS
	var direction := Input.get_axis(&"zoom_in", &"zoom_out")
	if _wheel_ticks > 0.0:
		_wheel_ticks -= ticks
		if direction == 0.0:
			direction = _wheel_direction
	if direction != 0.0:
		_zoom_speed = clampf(_zoom_speed + direction * ZOOM_ACCELERATION * ticks, -ZOOM_MAX_SPEED, ZOOM_MAX_SPEED)
	else:
		_zoom_speed = move_toward(_zoom_speed, 0.0, ZOOM_DECAY * ticks)
	if _zoom_speed > 0.0:
		zoom = minf(zoom * pow(1.0 + _zoom_speed, ticks), 1.0)
	elif _zoom_speed < 0.0:
		zoom = maxf(zoom / pow(1.0 - _zoom_speed, ticks), zoom_limit)
	var zooming := direction != 0.0 and (zoom < 1.0 or direction < 0.0) and (zoom > zoom_limit or direction > 0.0)
	if zooming and not _zoom_player.playing:
		_zoom_player.stream = _looped(get_sound.call("ZOOM"))
		if _zoom_player.stream:
			_zoom_player.play()
	elif not zooming and _zoom_player.playing:
		_zoom_player.stop()


## The clip (0x41eb10) and firing (0x461e88): while the timer runs, rounds load one per tick up to
## 3 (only as many as there's ammo for, except normal bullets; `SNIPRELD`); a shot needs the timer at
## 0, 5 ticks since the last one and a free round slot.
func _update_clip(delta: float) -> void:
	_shot_ticks = mini(_shot_ticks + 1, 999)
	var ammo_type := inventory.selected_ammo
	var stock: int = 999 if ammo_type == 0 else inventory.ammo[ammo_type - 1]
	if clip_time > 0.0 and clip_rounds < mini(CLIP_SIZE, stock):
		clip_rounds += 1
		play_sound("SNIPRELD")
	if clip_rounds == 0 and clip_time <= 0.0:
		if ammo_type != 0 and stock <= 0:
			inventory.selected_ammo = 0
		clip_time = 3.0
	clip_time = maxf(clip_time - CLIP_DECAY * delta, 0.0)
	if not Input.is_action_pressed(&"fire") or clip_time > 0.0 or _shot_ticks <= 4 or clip_rounds <= 0:
		return
	if sniper_fire.is_valid() and not sniper_fire.call(ammo_type):
		return
	_shot_ticks = 0
	play_sound("SNIPERSHOT")
	clip_rounds -= 1
	if ammo_type != 0:
		inventory.ammo[ammo_type - 1] -= 1
	clip_time += 1.0
	if clip_rounds == 0:
		clip_time = 3.0


## Picks the next or previous sniper ammo type that has rounds (0x46c900); the clip reloads.
func select_ammo(step: int) -> void:
	var ammo_type := inventory.selected_ammo
	for i in 6:
		ammo_type = wrapi(ammo_type + step, 0, 6)
		if ammo_type == 0 or inventory.ammo[ammo_type - 1] > 0:
			break
	if ammo_type != inventory.selected_ammo:
		inventory.selected_ammo = ammo_type
		clip_rounds = 0
		clip_time = 3.0


## Knocks Kurt down (state 901): he stops firing, falls and gets up (`K_BANG`, `K_BFLIP`), and is
## invulnerable for 3 seconds. After a slide he only gets up (`from_flip`).
func knock_down(p_push := Vector2.ZERO, from_flip := false) -> void:
	leave_sniper()
	knock_damage = 0.0
	invulnerable = KNOCKDOWN_INVULNERABILITY
	push += p_push
	firing = false
	_gun_player.stop()
	muzzle.visible = false
	chute_open = false
	_set_state(State.KNOCKED)
	if from_flip:
		animation_frame = sprites.get_animation("K_BANG").frame_count


## Starts the slide (0x468b64): the wind zones (opcode 224) call this while Kurt is in their box.
func start_slide() -> void:
	if sliding or health == 0:
		return
	sliding = true
	slide_velocity = Vector2.ZERO
	_slide_cap = SLIDE_CAP
	_slide_normal = Vector3(0.0, 0.0, 1.0)
	_slide_push = Vector2.ZERO
	_slide_air = 0.0
	firing = false
	_gun_player.stop()
	muzzle.visible = false
	chute_open = false
	_set_state(State.SLIP)


func stop_slide() -> void:
	sliding = false
	slide_velocity = Vector2.ZERO
	_slide_player.stop()


## Adds to the slide velocity (`slide_accel` 0x468be0): a push above 0.1 accelerates by its square,
## below −0.1 it slows the same way, and in between the velocity brakes towards 0.
func slide_accel(push_amount: Vector2, delta: float) -> void:
	for axis in 2:
		var a: float = push_amount[axis]
		if a > 0.1:
			slide_velocity[axis] += a * a * delta
		elif a < -0.1:
			slide_velocity[axis] -= a * a * delta
		else:
			slide_velocity[axis] = move_toward(slide_velocity[axis], 0.0, SLIDE_FRICTION * delta)


## One frame of the slide (`damp_buttslide`).
func _update_slide(delta: float, on_floor: bool) -> void:
	if on_floor:
		var normal := MDKScriptRuntime.to_mdk(get_floor_normal())
		_slide_normal.x = 0.8 * _slide_normal.x + 0.2 * normal.x
		_slide_normal.y = 0.8 * _slide_normal.y + 0.2 * normal.y
		_slide_normal.z = 0.5 * _slide_normal.z + 0.5 * normal.z
		_slide_push = Vector2(_slide_normal.x, _slide_normal.y) * SLIDE_SLOPE
		_slide_air = 0.0
	else:
		_slide_air += TICKS * delta
		if _slide_air > SLIDE_AIR_TICKS:
			stop_slide()
			_set_state(State.FALL)
			return
	slide_accel(_slide_push, delta)
	# The slide goes where the velocity points, and Kurt faces it.
	var mdk_yaw := rad_to_deg(yaw) + 90.0
	if absf(slide_velocity.x) + absf(slide_velocity.y) > 0.5:
		mdk_yaw = rad_to_deg(slide_velocity.angle())
	mdk_yaw += Input.get_axis(&"turn_left", &"turn_right") * SLIDE_TURN * delta
	yaw = deg_to_rad(mdk_yaw - 90.0)
	var speed := minf(slide_velocity.length(), _slide_cap)
	var forward_input := Input.get_axis(&"move_back", &"move_forward")
	if forward_input > 0.0:
		if speed >= SLIDE_MIN_SPEED:
			speed += SLIDE_ACCELERATION * forward_input * delta
		_slide_cap = minf(_slide_cap + SLIDE_CAP_RISE * delta, SLIDE_CAP_RANGE.y)
	elif forward_input < 0.0:
		if speed > SLIDE_MIN_SPEED:
			speed = maxf(speed + SLIDE_BRAKE * forward_input * delta, SLIDE_MIN_SPEED)
		_slide_cap = maxf(_slide_cap - SLIDE_CAP_FALL * delta, SLIDE_CAP_RANGE.x)
	else:
		_slide_cap = move_toward(_slide_cap, SLIDE_CAP, SLIDE_CAP_RELAX * delta)
	speed = minf(speed, _slide_cap)
	slide_velocity = Vector2.from_angle(deg_to_rad(mdk_yaw)) * speed
	velocity.x = slide_velocity.x
	velocity.z = -slide_velocity.y
	velocity.y -= SLIDE_GRAVITY * delta
	if on_floor and is_zero_approx(speed) and _slide_push.is_zero_approx():
		# At rest he gets back up.
		stop_slide()
		knock_down(Vector2.ZERO, true)


## The slide animations: `K_SLIP` once, then `K_SLIDE`, `K_FSLIDE` or `K_BSLIDE`.
func _update_slide_state(delta: float) -> void:
	if not sliding:
		_update_state(delta, 0.0, 0.0)
		return
	state_time += delta
	var animation := sprites.get_animation(STATE_ANIMATIONS[state][0])
	animation_frame += TICKS * delta
	if state != State.SLIP or animation_frame >= animation.frame_count:
		var forward_input := Input.get_axis(&"move_back", &"move_forward")
		var wanted := State.SLIDE
		if forward_input > 0.0:
			wanted = State.SLIDE_FAST
		elif forward_input < 0.0:
			wanted = State.SLIDE_BRAKE
		if wanted != state:
			_set_state(wanted)
			animation = sprites.get_animation(STATE_ANIMATIONS[state][0])
	_update_slide_sound()
	sprite.show_frame(animation, int(animation_frame) % maxi(animation.frame_count, 1))


func _update_slide_sound() -> void:
	var sound_name := "BUTBRAKE" if state == State.SLIDE_BRAKE else "BUTSLIDE"
	var pitch := SLIDE_PITCH if state == State.SLIDE_FAST else 1.0
	if _slide_player.get_meta(&"sound", "") != sound_name:
		_slide_player.set_meta(&"sound", sound_name)
		_slide_player.stream = _looped(get_sound.call(sound_name))
		_slide_player.play()
	_slide_player.pitch_scale = pitch


## Dead Kurt lies still while the skull fades in (`damp_control`), then the level restarts (the
## original loads the last saved game).
func _update_death(delta: float) -> void:
	velocity = Vector3(0.0, velocity.y - GRAVITY * delta, 0.0) if not is_on_floor() else Vector3.ZERO
	move_and_slide()
	state_time += delta
	var animation := sprites.get_animation("K_BANG")
	animation_frame = minf(animation_frame + TICKS * delta, animation.frame_count - 1)
	sprite.show_frame(animation, int(animation_frame))
	hurt_flash += 2.0 * TICKS * delta
	if hurt_flash > 255.0:
		set_physics_process(false)
		died.emit()


## Item keys (`damp_move`, 0x46ca38): select a slot (1–5, next, previous) or use the selected
## item: on the floor Kurt throws it with `K_SPWEP`, in the air it's used at once.
func _update_items() -> void:
	var inventory := inventory
	if not inventory.slots.is_empty():
		if Input.is_action_just_pressed(&"item_next"):
			inventory.selected = (inventory.selected + 1) % inventory.slots.size()
		if Input.is_action_just_pressed(&"item_prev"):
			inventory.selected = posmod(inventory.selected - 1, inventory.slots.size())
		for i in 5:
			if Input.is_action_just_pressed(StringName("item_%d" % (i + 1))) and i < inventory.slots.size():
				inventory.selected = i
	if not Input.is_action_just_pressed(&"item_use") or state in [State.THROW, State.DEAD, State.KNOCKED]:
		return
	if inventory.slots.is_empty():
		return
	var item := inventory.slots[inventory.selected].item
	if item == KurtInventory.Item.SUPER_CHAIN_GUN:
		return
	if can_use_item.is_valid() and not can_use_item.call(item):
		bomb_triggered.emit()
		return
	if is_on_floor():
		_set_state(State.THROW)
	elif state in [State.JUMP, State.RUN_JUMP, State.FALL, State.CHUTE]:
		item_used.emit()


## Holding fire fires the chain gun (`damp_move`); the hits are done by the scripts runtime
## (`MDKScriptRuntime.fire_chain_gun()`).
func _update_firing() -> void:
	var fire := Input.is_action_pressed(&"fire") and health > 0 and state not in [State.THROW, State.KNOCKED]
	var super_gun := inventory.super_chain_gun > 0
	if fire == firing and (not firing or super_gun == _gun_super):
		return
	firing = fire
	_gun_super = super_gun
	if firing:
		# `GATTFIRE` loops while firing (`MULTIFIRE` with the super chain gun, 0x46c3e4).
		var stream := _looped(get_sound.call("MULTIFIRE" if super_gun else "GATTFIRE"))
		if stream:
			_gun_player.stream = stream
			_gun_player.play()
	else:
		_gun_player.stop()


## Every other tick while firing, a random muzzle flash frame is drawn behind Kurt.
func _update_muzzle() -> void:
	_ticks += 1
	muzzle.visible = firing and MUZZLE_OFFSETS.has(state) and _ticks & 1 == 1
	if not muzzle.visible:
		return
	_muzzle_frame = (_muzzle_frame + randi() % 3 + 1) & 3
	var offset: Vector2i = MUZZLE_OFFSETS[state] + Vector2i(randi() % 5, randi() % 5)
	# The flash's hotspot is drawn at Kurt's hotspot plus the offset.
	muzzle.anchor_offset = sprite.anchor_offset - Vector2(offset)
	muzzle.flip_h = sprite.flip_h
	muzzle.show_frame(sprites.get_animation("K_MUZZF"), _muzzle_frame)


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
		_update_updraft(delta)
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
	_update_updraft(delta)


## In a fan's box the fan sets Kurt's vertical speed and opens his chute (state 701), with the
## `FAN` sound looping; out of them he can't rise faster than 40 u/s (`damp_gravity`).
func _update_updraft(delta: float) -> void:
	var vz: float = updraft.call(velocity.y, delta) if updraft.is_valid() and health > 0 else NAN
	if is_nan(vz):
		_fan_player.stop()
		if state != State.KNOCKED and velocity.y > UPDRAFT_EXIT_SPEED:
			velocity.y = UPDRAFT_EXIT_SPEED
		return
	velocity.y = vz
	if not chute_open:
		chute_open = true
		play_sound("CHUTEOUT")
	if not _fan_player.playing:
		_fan_player.stream = _looped(get_sound.call("FAN"))
		_fan_player.play()


func _update_state(delta: float, forward_input: float, strafe_input: float) -> void:
	state_time += delta
	var animation := sprites.get_animation(STATE_ANIMATIONS[state][0])
	var animation_done := animation_frame >= animation.frame_count - 1
	if health == 0 and is_on_floor():
		# Dead: the death animation once on the floor (state 1002).
		firing = false
		_gun_player.stop()
		muzzle.visible = false
		hurt_flash = 0.0
		_set_state(State.DEAD)
		sprite.show_frame(sprites.get_animation("K_BANG"), 0)
		return
	if state == State.KNOCKED:
		# `K_BANG` then `K_BFLIP`, one frame per tick; the push stops when he flips back up.
		var flip := sprites.get_animation("K_BFLIP")
		animation_frame += TICKS * delta
		var frame := int(animation_frame)
		if frame < animation.frame_count:
			sprite.show_frame(animation, frame)
			return
		push = Vector2.ZERO
		if frame - animation.frame_count < flip.frame_count:
			sprite.show_frame(flip, frame - animation.frame_count)
			return
		_set_state(State.STILL)
	if state == State.THROW and is_on_floor() and not animation_done:
		# Kurt stands still while throwing; the item leaves his hand on frame 8.
		var previous := int(animation_frame)
		animation_frame += TICKS * delta
		if previous < THROW_FRAME and int(animation_frame) >= THROW_FRAME:
			item_used.emit()
		sprite.show_frame(animation, mini(int(animation_frame), animation.frame_count - 1))
		return
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
		_set_state(State.RUN_FIRE if firing else State.RUN)
	elif not is_zero_approx(strafe_input) or absf(strafe_speed) > 1.0:
		_set_state(State.SIDE)
		sprite.flip_h = strafe_speed < 0.0
	elif absf(turn_speed) > 1.0:
		_set_state(State.TURN)
	elif firing:
		_set_state(State.SHOT)
	elif state == State.IDLE and not animation_done:
		pass
	elif state == State.STILL and state_time > IDLE_DELAY:
		_set_state(State.IDLE)
	elif state != State.STILL:
		_set_state(State.STILL)

	animation = sprites.get_animation(STATE_ANIMATIONS[state][0])
	match state:
		State.RUN, State.RUN_FIRE:
			# `damp_run_anim_frame`: the run animation follows the speed (backwards when backing up).
			var u := absf(forward_speed) / TICKS * 1.5
			var rate := 0.75 * u + 0.25 if u <= 1.0 else 0.25 * u + 0.75
			var previous := posmod(int(floor(animation_frame)), animation.frame_count)
			animation_frame += rate * TICKS * delta * (-1.0 if forward_speed < 0.0 else 1.0)
			var current := posmod(int(floor(animation_frame)), animation.frame_count)
			# Footsteps on frames 0 and 13 (4 and 17 when firing).
			var steps := [4, 17] if state == State.RUN_FIRE else [0, 13]
			if current != previous:
				if current == steps[0]:
					play_sound("FOOT3" if _footstep_pair else "FOOT1")
				elif current == steps[1]:
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


## A looping copy of a sound.
static func _looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	if stream and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var frame_bytes := (2 if stream.stereo else 1) * (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1)
		stream.loop_end = stream.data.size() / frame_bytes
	return stream


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

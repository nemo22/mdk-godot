## Runs the level's scripts: arena scripts (for the arena Kurt is in), the objects they spawn and the
## aliens placed by the DTI. Scripts run at the original's 30 ticks per second.
class_name MDKScriptRuntime
extends Node3D

const TICK := 1.0 / 30.0
## Flags of objects spawned by `spawn_flagged` and of projectiles (`fire`).
const SPAWN_FLAGGED_FLAGS := 0x2008A6
const PROJECTILE_FLAGS := 0x80820
## Chain gun (`0x41a304`): damage per tick, reach beyond the target's size, and the reach of shots
## that hit nothing.
const CHAIN_GUN_DAMAGE := 1
const CHAIN_GUN_REACH := 140.0
const CHAIN_GUN_WALL_REACH := 150.0
## Objects with more hit points than this don't show the health bar.
const MAX_BAR_HEALTH := 900
## Ticks before the minecrawler reaches the level's town, per difficulty (45, 30 and 20 minutes).
const TOWN_TICKS := [81000, 54000, 36000]
## Global flags: the minecrawler went for the second town (set by the game), the first town or
## the second one was flattened (tested by the debriefing).
const FLAG_SECOND_TOWN := 1 << 31
const FLAG_TOWN_FLATTENED := 1 << 30
const FLAG_SECOND_TOWN_FLATTENED := 1 << 29
## Collision layer of the level geometry (objects are on layer 2, see `MDKObject.update_body()`, and
## Kurt on layer 3).
const LEVEL_LAYER := 1


## Per arena script state (the arena's embedded object).
class ArenaState:
	var name := ""
	var controller: MDKObject
	## The object group hit scripts run in (the original's scratch object `0x57fc40`).
	var hit_scripts: MDKObject
	var variables := [0.0, 0.0, 0.0, 0.0]
	var flags := 0
	var started := false
	## Per triangle group (1–16): hit behaviour (`group_set_hit_flags`), hit types that run the
	## group's hit script and that script (`group_on_hit`), and counters (`arena+0xcc`).
	var group_hit_flags: Array[int] = []
	var group_hit_masks: Array[int] = []
	var group_hit_scripts: Array[int] = []
	var group_counters: Array[int] = []


	func _init() -> void:
		for array: Array[int] in [group_hit_flags, group_hit_masks, group_hit_scripts, group_counters]:
			array.resize(16)


var level: Level
var kurt: Kurt
var vm: MDKScriptVM
var motion: MDKObjectMotion
## Sprite effects (wounds, drops, bubbles) and shattered triangle groups.
var effects: MDKEffects
var debris: MDKDebris
## Sniper rounds, and the object locked in the scope (`0x573a8c`: homing target and zoom limit).
var sniper_rounds: MDKSniperRounds
var sniper_target: MDKObject
var air_strike: MDKAirStrike
## The end of the level's tornado, once it started.
var end_level: MDKEndLevel
## The point and direction of the last `shatter_group` (0x4d5374, 0x4d5358).
var shatter_point := Vector3()
var shatter_direction := Vector3(0.0, 0.0, 1.0)
var behaviors: MDKObjectBehaviors
var items: MDKItems
var fans: MDKFans
var global_variables := [0.0, 0.0, 0.0, 0.0]
var global_flags := 0
## Kurt's position (MDK coordinates) and the target of alien scripts (Kurt, or a decoy).
var kurt_position := Vector3()
var target_position := Vector3()
## Yaw of the target and of Kurt (degrees, MDK convention).
var target_yaw := 0.0
var kurt_yaw := 0.0
## The object aliens aim at instead of Kurt (`0x491e48`, `set_target_mode` 1).
var alien_target: MDKObject
## Ticks the alarm keeps sounding (`0x573aec`), set by objects with movement command 15.
var alarm_ticks := 0
## A count the scripts keep (`0x573c4c`, opcode 217), shown after the level.
var global_573c4c := 0
## How the sky is drawn (`0x574304`, opcode 202): 0 normally.
var sky_mode := 0
## Option toggled by cheat codes (`if_option`, the original's `0x5742dc`), 1 by default.
var option := 1
## On-screen messages (`hud_message`), set by the game.
var messages: HUDMessages
## The health bar at the top left of the view (`0x573c74` seconds left, 0x41e3c8): for a second
## after the chain gun hits an object with at most 900 hit points or one of its weak parts, or
## while a script sets it (`boss_bar`, only while Kurt fires).
var bar_time := 0.0
## The object whose health the bar shows (`0x573c78`), or null for `bar_health` of `bar_max`
## (the arena's own object).
var bar_object: MDKObject
var bar_health := 0
var bar_max := 0
## Ticks left before the minecrawler flattens the town (`0x574270`, 0x4240c4); none on the last
## level.
## Cutscene state (`0x573c60`, set by `special_event`): 0 = none.
const CUTSCENE_DOG := 0x34
const CUTSCENE_ALL := 0x3d
const CUTSCENE_STRIKE := 0x47
const CUTSCENE_END := 0x51
const CUTSCENE_ALL_FLAGGED := 0x5b
const CUTSCENE_BOSS := 0x5d
## The only objects that run in cutscenes below `CUTSCENE_ALL` (0x47868c).
const CUTSCENE_TYPES := ["XM5_FLAP", "XBN", "BOLT", "BIGBOLT", "SW_SBONE", "SW_SEAL"]
var cutscene := 0
var cutscene_target: MDKObject
## The cutscene camera (0x599920…0x599940): shot, yaw (`90° − heading`), pitch, distance to the
## target, stored position and the blend timer in ticks.
var camera_mode := 0
var camera_yaw := 0.0
var camera_pitch := 0.0
var camera_distance := 0.0
var camera_position := Vector3()
var camera_timer := 0
var _camera_point := Vector3()
## The level is over (`0x573b60`).
var level_over := false
## A level ended (`special_event` ≤ 50), or the whole game (event 81).
signal level_ended(game_over: bool)
var town_ticks := 0
var current_arena := ""
var objects: Array[MDKObject] = []

var _arenas := {}
var _animations := {}
var _resolvers := {}
var _next_instance := 1000
var _previous_kurt_position := Vector3()
## Kurt's velocity in units per second, measured over the last tick.
var kurt_velocity := Vector3()
## `camera_track` (opcode 203): the camera pitch the scripts want (`0x573918`), for this many more
## ticks (`0x5739b0`).
var camera_track_pitch := 0.0
var camera_track_ticks := 0
var _time := 0.0
var _tick_usec := 0
var _tick_count := 0
var _box_sprites: Array[Sprite3D] = []
var _box_time := 0.0


func setup(p_level: Level, p_kurt: Kurt) -> void:
	level = p_level
	kurt = p_kurt
	vm = MDKScriptVM.new(self, MDKScriptDecoder.new(level.cmi.bytes))
	motion = MDKObjectMotion.new(self)
	behaviors = MDKObjectBehaviors.new(self)
	items = MDKItems.new(self)
	fans = MDKFans.new(self)
	effects = MDKEffects.new()
	effects.runtime = self
	add_child(effects)
	debris = MDKDebris.new()
	debris.level = level
	add_child(debris)
	sniper_rounds = MDKSniperRounds.new()
	sniper_rounds.runtime = self
	add_child(sniper_rounds)
	air_strike = MDKAirStrike.new(self)
	air_strike.used_up = GameState.strike_used
	kurt.sniper_fire = func(type: int) -> bool:
		if type == 5:
			return air_strike.call_strike(to_mdk(kurt.get_sniper_eye()), kurt_yaw, kurt.sniper_pitch)
		return sniper_rounds.fire(type, to_mdk(kurt.get_sniper_eye()), kurt_yaw, kurt.sniper_pitch, sniper_target)
	kurt.updraft = func(vz: float, dt: float) -> float:
		return fans.query(current_arena, to_mdk(kurt.global_position), vz, MDKFans.MASK_KURT, dt)
	kurt.item_used.connect(items.use_item)
	kurt.bomb_triggered.connect(items.trigger_bomb)
	kurt.can_use_item = items.can_use
	# No town to save in the last level (index 5, LEVEL5).
	if GameState.index_of(level.number) != 5:
		town_ticks = TOWN_TICKS[kurt.inventory.difficulty]


func get_arena_state(arena_name: String) -> ArenaState:
	if not _arenas.has(arena_name):
		var state := ArenaState.new()
		state.name = arena_name
		state.controller = MDKObject.new()
		state.controller.name = "Arena_" + arena_name
		state.controller.arena = arena_name
		state.controller.restart = level.cmi.arena_scripts.get(arena_name, 0)
		state.hit_scripts = MDKObject.new()
		state.hit_scripts.name = "HitScripts_" + arena_name
		state.hit_scripts.arena = arena_name
		_arenas[arena_name] = state
	return _arenas[arena_name]


func _exit_tree() -> void:
	if motion:
		motion.free_probe()
	for state: ArenaState in _arenas.values():
		state.controller.free()
		state.hit_scripts.free()


## Group of the floor triangle below Kurt (`0x573c10`).
func get_kurt_floor_group() -> int:
	return level.get_floor_group(kurt.global_position, [kurt.get_rid()])


## The target of an object's script (`script_run`): Kurt, or the decoy while it walks, or the
## aliens' target (opcode 251), unless the object always targets Kurt.
func select_target(obj: MDKObject) -> void:
	target_position = kurt_position
	target_yaw = kurt_yaw
	if obj.target_mode == 2:
		return
	var other: MDKObject = null
	if items.decoy and not items.decoy.dead:
		other = items.decoy
	elif alien_target and not alien_target.dead:
		other = alien_target
	if other:
		target_position = other.mdk_position
		target_yaw = other.yaw


## Whether a sound (by name) is playing anywhere (`if_sound_playing`).
func is_sound_playing(sound_name: String) -> bool:
	for player in get_tree().get_nodes_in_group(&"mdk_sounds"):
		if player.get_meta(&"sound") == sound_name.to_upper() and player.playing:
			return true
	return false


## Moves Kurt (`teleport_player`): within the arena with a white flash when `arena_name` is empty,
## otherwise into that arena (the port keeps every arena where it is, so it's the same).
func teleport_kurt(arena_name: String, mdk_position: Vector3, yaw: float) -> void:
	kurt.teleport(MDKMeshBuilder.to_godot(mdk_position), deg_to_rad(yaw - 90.0))
	if arena_name.is_empty():
		kurt.white_flash = maxf(kurt.white_flash, 255.0)


## Converts a Godot position to MDK coordinates.
static func to_mdk(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


func _physics_process(delta: float) -> void:
	if not level:
		return
	_time += delta
	while _time >= TICK:
		_time -= TICK
		var start := Time.get_ticks_usec()
		_tick()
		_tick_usec += Time.get_ticks_usec() - start
		_tick_count += 1


## Ticks run so far.
func tick_count() -> int:
	return _tick_count


## Average duration of a script tick, in milliseconds (for profiling).
func average_tick_ms() -> float:
	if not vm:
		return 0.0
	return _tick_usec / 1000.0 / maxi(_tick_count, 1)


func _tick() -> void:
	kurt_position = to_mdk(kurt.global_position)
	target_position = kurt_position
	# Kurt's yaw 0 faces -Z (Godot) = +Y (MDK).
	target_yaw = fposmod(90.0 + rad_to_deg(kurt.yaw), 360.0)
	kurt_yaw = target_yaw
	if cutscene:
		_cutscene_tick()
		return
	alarm_ticks = maxi(alarm_ticks - 1, 0)
	camera_track_ticks = maxi(camera_track_ticks - 1, 0)
	_update_bar()
	if town_ticks > 0:
		town_ticks -= 1
		if town_ticks == 0:
			_flatten_town()
	var arena_name := level.get_arena_at(kurt.global_position)
	if not arena_name.is_empty() and arena_name != current_arena:
		current_arena = arena_name
		var state := get_arena_state(arena_name)
		if not state.started:
			state.started = true
			_spawn_dti_aliens(arena_name)
	# Kurt moves and takes pickups, then fires, then the objects run (`game_frame`).
	if _tick_count > 0:
		collect_pickups()
	kurt_velocity = (kurt_position - _previous_kurt_position) * 30.0
	_previous_kurt_position = kurt_position
	if kurt.firing:
		fire_chain_gun()
	if not current_arena.is_empty():
		vm.run(get_arena_state(current_arena).controller)
	items.update_twisters()
	effects.update(1.0)
	debris.update(1.0)
	sniper_rounds.update(1.0)
	air_strike.update(1.0)
	if end_level:
		end_level.update(1.0)
	_update_sniper_target()
	# Only the objects of Kurt's arena are updated (0x43c7dc; the original also updates the arena
	# seen through an open door).
	for obj in objects.duplicate():
		if obj.dead or obj.arena != current_arena:
			continue
		if obj.flags & MDKObject.FLAG_DOOR:
			behaviors.update_door(obj)
		vm.run(obj)
		if not obj.dead:
			motion.update(obj)


## `special_event` (opcode 131, 0x4456d2): cutscenes (events above 50, 0x477cf4) or the end of the
## level (50 and below).
func special_event(obj: MDKObject, event: int) -> void:
	if event <= 50:
		_end_level()
		return
	match event:
		51:
			# Kurt strikes (0x4779e0): the original first plays Kurt's `X_STRIKD` animation full screen
			# (0x4398f0, not done yet), then puts him at the object, which moves 4 units along y.
			kurt.teleport(MDKMeshBuilder.to_godot(obj.mdk_position), deg_to_rad(obj.yaw - 90.0))
			obj.mdk_position.y += 4.0
			_start_cutscene(CUTSCENE_STRIKE, obj)
			camera_distance = 10.0
			camera_position = obj.mdk_position - Vector3(10.0, 4.0, -8.0)
			camera_pitch = 0.0
			camera_yaw = 90.0 - obj.yaw
		52:
			var dog := find_object_named("XBN")
			if dog:
				_start_cutscene(CUTSCENE_DOG, dog)
				camera_mode = 0
		53, 92:
			_end_cutscene()
		55:
			camera_mode = 2
		61:
			var gunter := find_object_named("XGUNTAM")
			if gunter:
				_start_cutscene(CUTSCENE_ALL, gunter)
				camera_mode = 11
				var heading := Vector2.from_angle(deg_to_rad(gunter.yaw)) * 45.0
				camera_position = gunter.mdk_position + Vector3(heading.x, heading.y, 3.0)
				camera_pitch = -20.0
				camera_yaw = 270.0 - gunter.yaw
				camera_distance = 45.0
		81:
			# The end of the game: the original plays `MISC/FLIC/MDKEND.FLC` and `MDKBZK.MVE`.
			_start_cutscene(CUTSCENE_END, obj)
			level_ended.emit(true)
		91:
			_start_cutscene(CUTSCENE_ALL_FLAGGED, obj)
			camera_mode = 12
			camera_position = Vector3(-121.0, 3347.0, -350.0)
		93:
			_start_cutscene(CUTSCENE_BOSS, obj)
			camera_mode = 12
			camera_position = Vector3(1158.0, 5006.0, 315.0)


## The shooting galleries' guns (`if_gun_aim` 219, 0x461024) of level 6: they only fire along −y
## (270° ± 3°) and lead Kurt by the 1.67 s their shot takes (sideways only). Faster sideways
## movement makes them likelier to fire at him; otherwise they aim at a raised target (objects within
## 2 of `y` and 3 of `z` in their cone), then at Kurt anyway, and else face 270° and fire 29% of the
## time. Sets the yaw; returns whether to fire.
func gun_aim(obj: MDKObject, y: float, z: float) -> bool:
	var lead := Vector3(kurt_position.x + kurt_velocity.x * 1.67333, kurt_position.y, 0.0)
	var angle := obj.yaw_to(lead) + randi() % 500 * 0.001 - 0.25
	var aimed := absf(angle - 270.0) <= 3.0
	if aimed and randi() % 70 < roundi(absf(kurt_velocity.x)) + 10:
		obj.yaw = angle
		return true
	var angles: Array[float] = []
	for other in objects:
		if other.dead or other.arena != obj.arena or absf(other.mdk_position.y - y) > 2.0 or absf(other.mdk_position.z - z) > 3.0:
			continue
		var other_angle := obj.yaw_to(other.mdk_position)
		if absf(other_angle - 270.0) <= 3.0:
			angles.push_back(other_angle)
			if angles.size() == 4:
				break
	if not angles.is_empty():
		obj.yaw = angles[randi() % angles.size()]
		return true
	if aimed:
		obj.yaw = angle
		return true
	obj.yaw = 270.0
	return randi() % 100 > 70


## `place_x_near_player` (220, 0x460f00): the level 6 pop-up targets rise at Kurt's x (25%), where he
## will be 2.67 s later (50%) or at random (25%, or always when he's outside `x_min…x_max` or past
## `y_limit`), at least 12 units from other objects on the same y.
func place_near_kurt(obj: MDKObject, x_min: float, x_max: float, y_limit: float) -> void:
	var r := randi() % 100
	var x: float
	if r < 25 or kurt_position.x < x_min or kurt_position.x > x_max or kurt_position.y > y_limit:
		x = x_min + (x_max - x_min) * (randi() % 10000) * 0.0001
	elif r < 50:
		x = kurt_position.x
	else:
		x = kurt_position.x + kurt_velocity.x * 2.67333
	if x < x_min:
		x += x_max - x_min
	for i in 100:
		var moved := false
		for other in objects:
			if other != obj and not other.dead and other.arena == obj.arena and other.mdk_position.y == obj.mdk_position.y \
					and absf(x - other.mdk_position.x) < 11.5:
				x = other.mdk_position.x - 12.0
				moved = true
		if not moved:
			break
	obj.mdk_position.x = x


## `camera_track` (203, 0x4612e0): tilts the camera up towards a tall object (level 7's `XU`, level
## 5's Gunter) while Kurt faces it, less the more he turns away (none past 90°), at most 30° up,
## easing by 15% per tick. Mode 0 looks 70% of the way up the object, mode 1 at `height × scale`
## above its origin.
func camera_track(obj: MDKObject, mode: int, height: float) -> void:
	var off := fposmod(kurt_yaw - rad_to_deg(atan2(obj.mdk_position.y - kurt_position.y, obj.mdk_position.x - kurt_position.x)), 360.0)
	if off > 180.0:
		off = 360.0 - off
	var top := obj.mdk_position.z + height * obj.model_scale
	if mode == 0:
		var bounds_top := obj.mdk_position.z + (obj.model.bounds.end.z * obj.model_scale if obj.model else 0.0)
		top = 0.3 * obj.mdk_position.z + 0.7 * bounds_top
	var rest := level.get_camera_pitch(kurt.global_position)
	var target := rest
	if off <= 90.0 and top >= kurt_position.z:
		var distance := Vector2(obj.mdk_position.x - kurt_position.x, obj.mdk_position.y - kurt_position.y).length()
		target = clampf(-rad_to_deg(atan2(top - kurt_position.z, distance)) * (120.0 - off) / 120.0, -30.0, rest)
	camera_track_pitch = target
	camera_track_ticks = 2


## The scope's target lock (during projection in the original, 0x43b65c): the nearest object whose
## screen box overlaps a 64-pixel square around the crosshair (in 640×480 pixels), not flagged 0x30.
## It's what homing rounds chase, and zooming in on it is allowed down to `0.375 × its height /
## distance` (0x4678b0) instead of 0.25.
func _update_sniper_target() -> void:
	sniper_target = null
	kurt.zoom_limit = Kurt.ZOOM_MIN
	var camera := get_viewport().get_camera_3d()
	if not kurt.sniping or not camera:
		return
	var screen := get_viewport().get_visible_rect().size
	var scale := screen.y / SniperOverlay.SCREEN.y
	var center := Vector2((screen.x - SniperOverlay.SCREEN.x * scale) / 2.0, 0.0) 			+ (SniperOverlay.VIEW_ORIGIN + SniperOverlay.CROSSHAIR) * scale
	var square := Rect2(center - Vector2(32.0, 32.0) * scale, Vector2(64.0, 64.0) * scale)
	var best_depth := INF
	for obj in objects:
		if obj.dead or obj.arena != current_arena or not obj.model or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		var bounds := get_world_bounds(obj)
		var center_point := MDKMeshBuilder.to_godot(bounds.get_center())
		if camera.is_position_behind(center_point):
			continue
		var rect := Rect2(camera.unproject_position(center_point), Vector2.ZERO)
		for i in 8:
			var corner := MDKMeshBuilder.to_godot(bounds.get_endpoint(i))
			if not camera.is_position_behind(corner):
				rect = rect.expand(camera.unproject_position(corner))
		var depth := camera.global_position.distance_to(center_point)
		if rect.intersects(square) and depth < best_depth:
			best_depth = depth
			sniper_target = obj
	if sniper_target:
		var bounds := get_world_bounds(sniper_target)
		kurt.zoom_limit = minf(Kurt.ZOOM_MIN, 0.375 * maxf(bounds.size.z, 10.0) / maxf(kurt_position.distance_to(bounds.get_center()), 1.0))


## `special_130` (0x45d140): stamps a bullet hole (`BHOLE`, or `BHOLE2` with `option` 0) onto the
## texture of the object's face that a sniper round hit last, at the hit point's texel (the UVs of
## the face interpolated there), keeping the hole's transparent pixels. Textures are shared, so every
## object using it gets the hole. The port finds the face nearest to the point on the hit part (the
## original keeps the face the round's test found).
func stamp_bullet_hole(obj: MDKObject) -> void:
	if obj.shot_part <= 0 or not obj.model or obj.shot_part > obj.model.parts.size():
		return
	var part_index := obj.shot_part - 1
	var part := obj.model.parts[part_index]
	var vertices: PackedVector3Array = obj.get_pose()[part_index]
	if vertices.is_empty():
		return
	var point := (obj.shot_point - obj.mdk_position).rotated(Vector3.BACK, -deg_to_rad(obj.yaw)) / obj.model_scale
	var best := -1
	var best_distance := INF
	var best_weights := Vector3()
	var resolver := get_resolver(obj.arena)
	for tri in part.triangle_materials.size():
		var value := part.triangle_materials[tri]
		if value < 0 or value >= obj.model.materials.size() or not resolver.find_texture(obj.model.materials[value]):
			continue
		var a := vertices[part.triangle_indices[tri * 3]]
		var b := vertices[part.triangle_indices[tri * 3 + 1]]
		var c := vertices[part.triangle_indices[tri * 3 + 2]]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() == 0.0:
			continue
		normal = normal.normalized()
		var on_plane := point - normal * normal.dot(point - a)
		var weights := Geometry3D.get_triangle_barycentric_coords(on_plane, a, b, c)
		weights = weights.clamp(Vector3.ZERO, Vector3.ONE)
		weights /= maxf(weights.x + weights.y + weights.z, 1e-6)
		var closest := a * weights.x + b * weights.y + c * weights.z
		var distance := closest.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = tri
			best_weights = weights
	if best < 0:
		return
	var texture := resolver.find_texture(obj.model.materials[part.triangle_materials[best]])
	var uv := part.triangle_uvs[best * 3] * best_weights.x + part.triangle_uvs[best * 3 + 1] * best_weights.y 			+ part.triangle_uvs[best * 3 + 2] * best_weights.z
	var hole := kurt.sprites.get_image("BHOLE" if option else "BHOLE2")
	var origin := Vector2i(roundi(uv.x) - hole.width / 2, roundi(uv.y) - hole.height / 2)
	for y in hole.height:
		for x in hole.width:
			var index := hole.indices[y * hole.width + x]
			if index == 0:
				continue
			var tx := posmod(origin.x + x, texture.width)
			var ty := posmod(origin.y + y, texture.height)
			texture.indices[ty * texture.width + tx] = index
	texture.get_index_texture().update(Image.create_from_data(texture.width, texture.height * texture.frame_count, false,
			Image.FORMAT_R8, texture.indices))


## The first active object of a type (the cutscenes' targets).
func find_object_named(type_name: String) -> MDKObject:
	for obj in objects:
		if not obj.dead and obj.type_name == type_name:
			return obj
	return null


## Starts a cutscene: Kurt stops firing (0x4779b0) and stands still, the camera looks at `target`.
func _start_cutscene(state: int, target: MDKObject) -> void:
	cutscene = state
	cutscene_target = target
	kurt.stop_firing()
	kurt.frozen = true


func _end_cutscene() -> void:
	cutscene = 0
	cutscene_target = null
	kurt.frozen = false
	kurt.visible = true
	for obj in objects:
		obj.visible = true


## A frame during a cutscene (0x478704 instead of the normal frame): only some objects run and are
## drawn, and the camera follows the cutscene's shot (0x477d94).
func _cutscene_tick() -> void:
	kurt.visible = cutscene == CUTSCENE_STRIKE or cutscene == CUTSCENE_END
	for obj in objects.duplicate():
		if obj.dead or obj.arena != current_arena:
			continue
		var flagged: bool = obj.flags & 0x201000 != 0 or obj.thrown_kind > 0
		var runs: bool
		var shown: bool
		if cutscene == CUTSCENE_END:
			runs = false
			shown = false
		elif cutscene < CUTSCENE_ALL:
			runs = obj.type_name in CUTSCENE_TYPES
			shown = runs and obj.type_name != "BOLT" and obj.type_name != "BIGBOLT"
		else:
			runs = cutscene == CUTSCENE_ALL_FLAGGED or not flagged
			shown = not flagged
		obj.visible = shown
		if runs:
			vm.run(obj)
			if not obj.dead:
				motion.update(obj)
	if cutscene and cutscene_target and not cutscene_target.dead:
		_update_cutscene_camera()


## The cutscene camera (0x477d94). Every shot but mode 11 looks at the target, 3 units above its
## origin. Mode 0 starts from (423, 85) and switches to mode 1 once the target is 12 units away;
## modes 1 and 2 orbit behind the target (12 or 25 units), smoothly for 1800 ticks.
func _update_cutscene_camera() -> void:
	var target := cutscene_target.mdk_position
	var point := camera_position
	var yaw := camera_yaw
	var distance := camera_distance
	match camera_mode:
		0:
			point = Vector3(423.0, 85.0, maxf(target.z - 25.0, -2260.0))
			yaw = 90.0 - rad_to_deg(atan2(target.y - point.y, target.x - point.x))
			distance = point.distance_to(target)
			if distance >= 12.0:
				camera_mode = 1
			camera_timer = 1800
		1, 2:
			distance = (12.0 if camera_mode == 1 else 25.0) * 0.1 + camera_distance * 0.9
			var around := Vector2.from_angle(deg_to_rad(cutscene_target.yaw + 150.0)) * distance
			point = Vector3(target.x + around.x, target.y + around.y, -2258.0)
			if camera_mode == 2:
				point.z = minf(camera_position.z + motion.ticks, -2246.0)
			if camera_timer > 0:
				point = point * 0.2 + camera_position * 0.8
			yaw = 120.0 - cutscene_target.yaw
		12:
			yaw = 90.0 - rad_to_deg(atan2(target.y - point.y, target.x - point.x))
			distance = point.distance_to(target)
			camera_timer = 1800
	var pitch := camera_pitch
	if camera_mode != 11:
		pitch = -rad_to_deg(atan2(target.z + 3.0 - point.z, distance))
		if pitch < -180.0:
			pitch += 360.0
	if camera_mode == 1 or camera_mode == 2:
		if camera_timer > 0:
			pitch = pitch * 0.2 + camera_pitch * 0.8
			yaw = yaw * 0.2 + camera_yaw * 0.8
			camera_timer -= 1
		else:
			pitch = pitch * 0.7 + camera_pitch * 0.3
			yaw = yaw * 0.3 + camera_yaw * 0.7
	camera_distance = distance
	camera_pitch = pitch
	camera_yaw = yaw
	if cutscene != CUTSCENE_BOSS:
		camera_position = point
	_camera_point = point


## The cutscene camera's view (Godot space). The camera's yaw is `90° − heading`.
func get_cutscene_camera() -> Transform3D:
	var yaw := deg_to_rad(camera_yaw)
	var pitch := deg_to_rad(camera_pitch)
	var forward := Vector3(sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), -sin(pitch))
	return Transform3D(Basis.looking_at(MDKMeshBuilder.to_godot(forward), Vector3.UP), MDKMeshBuilder.to_godot(_camera_point))


## The end of a level (`special_event` 0–50): at the end of the frame (0x41d4d8, 0x40a9e0) Kurt
## stops firing and the level is over (`0x573b60`), with the sounds `NUKE` and `TORNADO`, and the
## arena breaks up around Kurt as he rises (`MDKEndLevel`); then the next level.
func _end_level() -> void:
	if level_over:
		return
	level_over = true
	kurt.stop_firing()
	play_sound_at("NUKE", kurt_position)
	play_sound_at("TORNADO", kurt_position)
	end_level = MDKEndLevel.new()
	add_child(end_level)
	end_level.finished.connect(level_ended.emit.bind(false))
	end_level.start(self)


## Spawns the aliens placed by the DTI records of type 2 (`ARENA$TYPE_n` scripts).
func _spawn_dti_aliens(arena_name: String) -> void:
	for entry in level.dti.arenas:
		if entry.name != arena_name:
			continue
		for record: Dictionary in entry.records:
			if record.type != 2:
				continue
			var key := "%s$%s_%d" % [arena_name, record.name, record.id]
			var controller := get_arena_state(arena_name).controller
			spawn(controller, record.name, record.position, record.angle, record.id, level.cmi.alien_scripts.get(key, 0), false)


## Spawns an object of type `type_name` in `parent`'s arena. Returns `null` if the type is unknown.
func spawn(parent: MDKObject, type_name: String, mdk_position: Vector3, yaw: float, instance: int, script: int, flagged: bool) -> MDKObject:
	var model := find_model(parent.arena, type_name)
	if not model:
		return null
	var obj := MDKObject.new()
	obj.arena = parent.arena
	obj.setup(type_name, model, get_resolver(parent.arena))
	obj.instance_id = instance if instance >= 0 else _next_instance
	if instance < 0:
		_next_instance += 1
	obj.mdk_position = mdk_position
	obj.spawn_position = mdk_position
	obj.previous_position = mdk_position
	obj.yaw = fposmod(yaw, 360.0)
	obj.update_transform()
	if flagged:
		obj.flags = SPAWN_FLAGGED_FLAGS
	add_child(obj)
	objects.push_back(obj)
	# The object type's init script runs once at creation.
	var init_script: int = level.cmi.object_scripts.get("%s$%s" % [parent.arena, type_name], 0)
	if init_script:
		obj.restart = init_script
		vm.run(obj)
	obj.restart = script
	return obj


## `spawn_box` (opcode 159): an object whose model is a box of `size` (`model_create_box` 0x404188,
## 8 corners at ± half the size, 12 triangles) showing the texture `texture_name` as an animated
## sprite (`FIRE`: small flames, `PULSE`). The triangles themselves aren't drawn.
func spawn_box(parent: MDKObject, mdk_position: Vector3, size: Vector3, texture_name: String, script: int) -> MDKObject:
	var model := MDKModel.new()
	model.name = texture_name
	var part := MDKModel.Part.new()
	for i in 8:
		part.vertices.push_back(Vector3(size.x if i & 1 else -size.x, size.y if i & 2 else -size.y, size.z if i & 4 else -size.z) * 0.5)
	for triangle in [[0, 1, 2], [1, 2, 3], [0, 4, 6], [0, 2, 6], [0, 1, 5], [0, 5, 4], [1, 5, 7], [1, 3, 7], [3, 2, 6], [3, 7, 6], [5, 4, 6], [5, 7, 6]]:
		part.triangle_indices.append_array(PackedInt32Array(triangle))
		part.triangle_materials.push_back(-256)
		part.triangle_uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
	part.bounds = AABB(-size * 0.5, size)
	model.parts.push_back(part)
	model.bounds = part.bounds
	var obj := MDKObject.new()
	obj.arena = parent.arena
	var resolver := get_resolver(parent.arena)
	obj.setup(texture_name, model, resolver)
	obj.instance_id = _next_instance
	_next_instance += 1
	obj.mdk_position = mdk_position
	obj.spawn_position = mdk_position
	obj.previous_position = mdk_position
	obj.update_transform()
	var texture := resolver.find_texture(texture_name)
	if texture:
		var sprite := Sprite3D.new()
		var image := resolver.palette.make_image(texture.width, texture.height * texture.frame_count, texture.indices, true)
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.vframes = texture.frame_count
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = maxf(size.x, size.z) / maxf(texture.width, 1)
		obj.add_child(sprite)
		_box_sprites.push_back(sprite)
	add_child(obj)
	objects.push_back(obj)
	obj.restart = script
	return obj


## Advances the animated sprites of box objects (30 frames per second ❓).
func _process(delta: float) -> void:
	_box_time += delta
	for i in range(_box_sprites.size() - 1, -1, -1):
		var sprite := _box_sprites[i]
		if not is_instance_valid(sprite):
			_box_sprites.remove_at(i)
			continue
		sprite.frame = int(_box_time * 30.0) % sprite.vframes


func remove(obj: MDKObject) -> void:
	if obj.attached and not obj.attached.dead:
		remove(obj.attached)
	obj.dead = true
	objects.erase(obj)
	obj.queue_free()


## Kills an object (`object_kill` 0x43d670): it switches to its death script if it has one,
## otherwise it explodes. `yaw` is the direction the explosion faces.
func kill(obj: MDKObject, yaw := 0.0) -> void:
	obj.health = 0
	if obj.death_script:
		obj.move_command = 0
		obj.flags |= MDKObject.FLAG_NOT_TARGET
		obj.restart = obj.death_script
		obj.wait_time = 0.0
		obj.wait_resume = obj.death_script
		obj.death_script = 0
	else:
		explode(obj, yaw)


## Blows an object up (0x43d224): its explosion sound (opcode 25, or `EXPLODE`), and the global
## model 0 (`EXPLODE`, an animated texture) scaled to the object's height and turned to the camera.
## The original also throws the object's parts as debris.
func explode(obj: MDKObject, yaw: float) -> void:
	var bounds := get_world_bounds(obj)
	var center := bounds.get_center() if obj.model else obj.mdk_position
	play_sound_at(obj.labels[0] if not obj.labels[0].is_empty() else "EXPLODE", center)
	remove(obj)
	var effect := spawn_explosion(obj.arena, center, 1.0, yaw)
	if effect:
		effect.model_scale = bounds.size.z / maxf(effect.model.bounds.size.z, 0.1) * 1.5
		effect.update_transform()


## Spawns an explosion (0x43cb2c): the global model 0 (`EXPLODE`), whose animated texture plays
## once, one frame per tick, pitched towards the camera.
func spawn_explosion(arena_name: String, center: Vector3, scale: float, yaw := 0.0) -> MDKObject:
	var model_name: String = level.cmi.model_offsets.keys()[0] if not level.cmi.model_offsets.is_empty() else ""
	var effect := spawn(get_arena_state(arena_name).controller, model_name, center, yaw, -1, 0, false)
	if not effect:
		return null
	effect.flags |= MDKObject.FLAG_NOT_TARGET | MDKObject.FLAG_NOT_SOLID_2
	effect.effect_frames = 26
	var texture := get_resolver(arena_name).find_texture(effect.model.materials[0]) if not effect.model.materials.is_empty() else null
	if texture:
		effect.effect_frames = texture.frame_count
	effect.model_scale = scale
	var camera := get_viewport().get_camera_3d()
	if camera:
		var eye := to_mdk(camera.global_position)
		var horizontal := Vector2(eye.x - center.x, eye.y - center.y).length()
		effect.yaw = fposmod(rad_to_deg(atan2(eye.y - center.y, eye.x - center.x)), 360.0) if yaw == 0.0 else yaw
		effect.pitch = rad_to_deg(atan2(eye.z + 5.0 - center.z, horizontal))
	effect.set_texture_frame(0)
	effect.update_transform()
	return effect


## An object fell far below its arena (0x43d884): it switches to its death script, put back
## above the floor, or it's removed.
func fall_out(obj: MDKObject) -> void:
	if not obj.death_script:
		remove(obj)
		return
	kill(obj)
	obj.velocity.z = 0.0
	obj.mdk_position.z = get_arena_floor(obj.arena) - 150.0
	obj.flags &= ~MDKObject.FLAG_GRAVITY


## Fires the chain gun for one tick (`0x41a304`): it hits the best target in front of Kurt (see
## `_aim_score()`) or, without one, the arena up to 150 units away.
func fire_chain_gun() -> void:
	var origin := kurt_position + Vector3(0, 0, 5)
	# The super chain gun does 6 times the damage while its time lasts.
	var super_gun := kurt.inventory.super_chain_gun > 0
	var damage := CHAIN_GUN_DAMAGE * (6 if super_gun else 1)
	if super_gun:
		kurt.inventory.tick_super_chain_gun(1)
	var best: MDKObject = null
	var best_score := -1.0
	var best_part := -1
	var best_bounds := AABB()
	for obj in objects:
		if obj.dead or obj.arena != current_arena or obj.health == 0 or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		# Weak parts are targets of their own.
		if obj.flags & MDKObject.FLAG_WEAK_PARTS and obj.model:
			var part_bounds := obj.get_part_bounds()
			for i in obj.model.parts.size():
				if obj.hidden_parts & (1 << i) or not _is_weak_part(obj, i):
					continue
				var bounds := get_world_bounds(obj, part_bounds[i])
				var score := _aim_score(bounds, origin, best_score)
				if score >= 0.0:
					best = obj
					best_score = score
					best_part = i
					best_bounds = bounds
			if best == obj:
				continue
		var bounds := get_world_bounds(obj)
		var score := _aim_score(bounds, origin, best_score)
		if score >= 0.0:
			best = obj
			best_score = score
			best_part = -1
			best_bounds = bounds
	if best:
		_chain_gun_hit(best, best_part, best_bounds, origin, damage, super_gun)
		return
	var direction := Vector2.from_angle(deg_to_rad(target_yaw)) * CHAIN_GUN_WALL_REACH
	var hit := raycast(origin, origin + Vector3(direction.x, direction.y, 0.0))
	if not hit.is_empty():
		hit_group_at(hit, damage, HIT_CHAIN_GUN, -2 if super_gun else -1)
		spark(to_mdk(hit.position), 1)


## Kinds of hits on triangle groups (0x40d560), matched against their hit flags and masks.
const HIT_SHOT := 1
const HIT_CHAIN_GUN := 2
const HIT_BLAST := 3
const HIT_OTHER_BLAST := 4


## A hit on the arena triangle that `hit` (a `raycast()` result) found; see `hit_group()`.
func hit_group_at(hit: Dictionary, amount: int, kind: int, weapon: int) -> int:
	var collider: Object = hit.get("collider")
	if not collider or not collider.has_meta(&"group"):
		return 0
	return hit_group(collider.get_meta(&"arena"), collider.get_meta(&"group"), amount, kind, weapon)


## A hit on a triangle of an arena group (0x40d560). `kind` is what hit it (`HIT_SHOT`,
## `HIT_CHAIN_GUN`, `HIT_BLAST`, …), `weapon` the hit type its script sees (`if_hit_weapon`). The
## group's hit flags (opcode 168) and hit script (opcode 99) decide what happens. Returns 1 when
## the hit script ran, | 2 when the group stops such hits (flag 0x20).
func hit_group(arena_name: String, group: int, amount: int, kind: int, weapon: int) -> int:
	if group < 1 or group > 16:
		return 0
	var state := get_arena_state(arena_name)
	var i := group - 1
	var flags := state.group_hit_flags[i]
	var always := false
	var result := 0
	if flags & kind:
		if flags & 0x80:
			# A destructible group: its damaged version appears.
			level.set_group_state(arena_name, group, 3)
		if flags & 0x40:
			always = true
			amount = maxi(amount, 1)
		if flags & 0x20:
			result = 2
	if state.group_hit_scripts[i] and (state.group_hit_masks[i] & kind or always):
		state.group_counters[i] += amount
		# The script runs at once, from its start, in the arena's scratch object (0x45c9a0).
		var scratch := state.hit_scripts
		scratch.hit_type = weapon
		scratch.hit_event = 0
		scratch.wait_time = 0.0
		scratch.gosub_returns.clear()
		scratch.gosub_restarts.clear()
		scratch.restart = state.group_hit_scripts[i]
		vm.run(scratch)
		result |= 1
	return result


## Shakes the screen at least this much (`0x467f7c`).
func raise_shake(amount: float) -> void:
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.raise_shake(amount)


## Aim test of the chain gun (`0x41ab2c`): a box is a target when it's within its size + 140 units
## of `origin`, inside a cone around Kurt's yaw that is wider for big and close boxes, and visible.
## Returns its score (squared distance, height counting double; lower is better), or -1.
func _aim_score(bounds: AABB, origin: Vector3, best_score: float) -> float:
	var size := maxf(bounds.size.length(), 10.0)
	var center := bounds.get_center()
	var distance := origin.distance_to(center)
	if distance > size + CHAIN_GUN_REACH:
		return -1.0
	var angle := fposmod(rad_to_deg(atan2(center.y - origin.y, center.x - origin.x)) - target_yaw, 360.0)
	var cone := (size - 2.0) * 90.0 / (size - 2.0 + distance)
	if angle > cone and angle < 360.0 - cone:
		return -1.0
	var height := center.z - kurt_position.z
	var score := Vector2(center.x - origin.x, center.y - origin.y).length_squared() + 4.0 * height * height
	if best_score >= 0.0 and score > best_score:
		return -1.0
	if not raycast(origin, center).is_empty():
		return -1.0
	return score


## Whether part `index` is one of the object's weak parts (0x462384): its name starts with the
## prefix and has a digit right after it.
static func _is_weak_part(obj: MDKObject, index: int) -> bool:
	var part_name := obj.model.parts[index].name
	if part_name.length() <= obj.weak_prefix_length or not part_name[obj.weak_prefix_length].is_valid_int():
		return false
	return part_name.begins_with(obj.weak_prefix.left(obj.weak_prefix_length))


func _chain_gun_hit(obj: MDKObject, part: int, bounds: AABB, origin: Vector3, damage: int, super_gun: bool) -> void:
	var center := bounds.get_center()
	var direction := rad_to_deg(atan2(center.y - origin.y, center.x - origin.x))
	obj.hit_event = -1
	if part >= 0 and part < obj.part_health.size():
		obj.part_health[part] -= damage
		if obj.part_health[part] <= 0:
			obj.part_health[part] = 0
			obj.hit_event = part + 1
		if obj.part_max_health[part] <= MAX_BAR_HEALTH:
			show_bar_values(obj.part_health[part], obj.part_max_health[part])
	if obj.health < 65000:
		obj.health -= damage
	obj.hit_type = -2 if super_gun else -1
	obj.hit_direction = direction
	if obj.health > 0:
		if part < 0 and obj.max_health <= MAX_BAR_HEALTH:
			bar_object = obj
			bar_time = 1.0
		# Sparks on the side of the box facing Kurt.
		var toward := Vector2.from_angle(deg_to_rad(direction))
		var point := center - Vector3(toward.x * bounds.size.x, toward.y * bounds.size.y, 0.0) * 0.5
		spark(point, 1, obj.labels[1])
		return
	obj.health = 0
	if super_gun:
		# The super chain gun throws what it kills away.
		var push := Vector2.from_angle(deg_to_rad(direction)) * 20.0
		obj.velocity += Vector3(push.x, push.y, 0.0)
	kill(obj, direction + 180.0)


## The minecrawler reached the town: the screen shakes and a message says which town is gone
## (`OOT_L1`, "There goes Laguna Beach!", or `OOT_L1A` for the second town).
func _flatten_town() -> void:
	raise_shake(5.0)
	var text_name := "OOT_L%d" % (GameState.index_of(level.number) + 1)
	if global_flags & FLAG_SECOND_TOWN:
		text_name += "A"
		global_flags |= FLAG_SECOND_TOWN_FLATTENED
	else:
		global_flags |= FLAG_TOWN_FLATTENED
	if messages:
		messages.push(text_name, HUDMessages.FLAG_ZOOM | HUDMessages.FLAG_FRONT, 5.0)


## Shows the health bar with these values for a second (the arena's own object, `boss_bar`).
func show_bar_values(health: int, max_health: int) -> void:
	bar_object = null
	bar_health = health
	bar_max = max_health
	bar_time = 1.0 if health > 0 else 0.0


## The bar's health and maximum, or zeros while it's hidden.
func get_bar() -> Vector2i:
	if bar_time <= 0.0:
		return Vector2i.ZERO
	if bar_object:
		return Vector2i(bar_object.health, bar_object.max_health)
	return Vector2i(bar_health, bar_max)


## The bar goes away after its time, or when its object dies or can't show a bar.
func _update_bar() -> void:
	if bar_time <= 0.0:
		return
	bar_time -= TICK
	if bar_object and (not is_instance_valid(bar_object) or bar_object.dead):
		bar_object = null
		bar_time = 0.0
		return
	var bar := get_bar()
	if bar.y == 0 or bar.y > MAX_BAR_HEALTH or bar.x < 1:
		bar_time = 0.0


## Sparks where a shot hits (`0x41e8f4`); a ricochet sound (the object's, set by opcode 26, or
## `RICO1`–`RICO3`) every 4 ticks.
func spark(point: Vector3, _count: int, sound_name := "") -> void:
	if _tick_count & 3:
		return
	play_sound_at(sound_name if not sound_name.is_empty() else ["RICO1", "RICO2", "RICO3"][randi() % 3], point)


## Starts the object's looping sound (`set_loop_sound`), stopping the previous one; an empty name
## just stops it.
func set_loop_sound(obj: MDKObject, sound_name: String) -> void:
	if obj.loop_sound:
		obj.loop_sound.queue_free()
		obj.loop_sound = null
	var stream := level.get_sound(sound_name) if not sound_name.is_empty() else null
	if not stream:
		return
	stream = stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / ((2 if stream.stereo else 1) * (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1))
	obj.loop_sound = AudioStreamPlayer3D.new()
	obj.loop_sound.stream = stream
	obj.loop_sound.unit_size = 50.0
	obj.add_child(obj.loop_sound)
	obj.loop_sound.play()


## Looks for cover (`find_cover_spot`): a DTI record of type 5 of the object's arena, 9–400 units
## away, no farther than Kurt, closer to Kurt than the object, hidden from Kurt but visible to the
## object. One of the 3 nearest is chosen (nearer ones more likely) and the object goes there
## `wind_zone` (opcode 224, 0x4579e0): while Kurt is inside one of the arena's type-9 hotspot
## boxes, the wind blows him along `yaw` at `speed`, sliding him on his back (`damp_buttslide`);
## in the air without sliding it only pulls him down twice as fast. `enable` 0 ends the slide.
func wind_zone(arena: String, enable: bool, yaw: float, speed: float) -> void:
	if not enable:
		kurt.stop_slide()
		return
	for entry in level.dti.arenas:
		if entry.name != arena:
			continue
		for record: Dictionary in entry.records:
			if record.type != 9 or not AABB(record.position, record.box_end - record.position).has_point(kurt_position):
				continue
			if kurt.sliding or kurt.is_on_floor():
				kurt.start_slide()
				kurt.yaw = deg_to_rad(yaw - 90.0)
				kurt.slide_accel(Vector2.from_angle(deg_to_rad(yaw)) * speed, TICK)
			else:
				kurt.velocity.y -= Kurt.SLIDE_GRAVITY * TICK
			return


## Picks one of the arena's type-8 waypoints at random (`pick_waypoint8` 0x460a6c) and makes it
## the destination (movement command 221). Every waypoint gets a weight of at least 1:
## `500 − distance` (2D), plus `200 − distance to Kurt` when Kurt is closer than 200, plus 250 when
## the object is closer to Kurt than to the waypoint and the waypoint is farther from Kurt than
## from the object, less half the height difference. Mode 0 takes the waypoints 50–500 units away,
## mode 1 those whose id is within 3 of the nearest one.
func pick_waypoint8(obj: MDKObject, mode: int) -> void:
	obj.move_command = 0
	var records: Array[Dictionary] = []
	for entry in level.dti.arenas:
		if entry.name == obj.arena:
			for record: Dictionary in entry.records:
				if record.type == 8:
					records.push_back(record)
	var nearest_id := 0
	if mode == 1:
		var nearest := 999999.0
		for record in records:
			var distance: float = obj.mdk_position.distance_to(record.position)
			if distance < nearest:
				nearest = distance
				nearest_id = record.id
	var weights: Array[int] = []
	var total := 0
	for record in records:
		var spot: Vector3 = record.position
		var distance := _distance_2d(spot, obj.mdk_position)
		var weight := 0
		if mode == 1 and absi(record.id - nearest_id) <= 3 or mode != 1 and distance >= 50.0 and distance <= 500.0:
			var to_kurt := _distance_2d(spot, kurt_position)
			weight = roundi(500.0 - distance)
			if to_kurt < 200.0:
				weight = roundi(weight + 200.0 - to_kurt)
			if _distance_2d(obj.mdk_position, kurt_position) < distance and to_kurt > distance:
				weight += 250
			weight = roundi(weight - absf(spot.z - obj.mdk_position.z) * 0.5)
			weight = maxi(weight, 1)
		weights.push_back(weight)
		total += weight
	if total == 0:
		return
	var pick := randi() % total
	for i in records.size():
		pick -= weights[i]
		if pick < 0:
			obj.move_command = 221
			obj.move_destination = records[i].position
			obj.waypoint = obj.move_destination
			obj.contact_flags &= ~MDKObject.CONTACT_STUCK
			return


static func _distance_2d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()


## Looks for a type-5 waypoint to advance to (`find_advance_spot`, like `find_cover_spot` without
## the visibility tests and with 2D distances): 5–400 units away, no farther from the object than
## Kurt is and closer to Kurt than the object. It becomes the destination (movement command 197).
func find_advance_spot(obj: MDKObject) -> void:
	obj.move_command = 0
	var spots: Array[Vector3] = []
	var to_kurt := _distance_2d(obj.mdk_position, kurt_position)
	for entry in level.dti.arenas:
		if entry.name != obj.arena:
			continue
		for record: Dictionary in entry.records:
			if record.type != 5:
				continue
			var spot: Vector3 = record.position
			var distance := _distance_2d(spot, obj.mdk_position)
			if distance < 5.0 or distance > 400.0 or distance > to_kurt or _distance_2d(spot, kurt_position) >= to_kurt:
				continue
			spots.push_back(spot)
	if spots.is_empty():
		return
	obj.move_command = 197
	obj.move_destination = spots[randi() % spots.size()]
	obj.waypoint = obj.move_destination
	obj.contact_flags &= ~MDKObject.CONTACT_STUCK


## (movement command 43); otherwise the object stops.
func find_cover_spot(obj: MDKObject) -> void:
	var spots: Array[Vector3] = []
	var to_kurt := obj.distance_to(kurt_position)
	for entry in level.dti.arenas:
		if entry.name != obj.arena:
			continue
		for record: Dictionary in entry.records:
			if record.type != 5:
				continue
			var spot: Vector3 = record.position
			var distance := obj.distance_to(spot)
			if distance < 9.0 or distance > 400.0 or distance > to_kurt or spot.distance_to(kurt_position) >= to_kurt:
				continue
			if raycast(kurt_position + Vector3(0, 0, 5), spot + Vector3(0, 0, 5)).is_empty():
				continue
			if not raycast(obj.mdk_position + Vector3(0, 0, 5), spot + Vector3(0, 0, 5)).is_empty():
				continue
			spots.push_back(spot)
	obj.move_command = 0
	if spots.is_empty():
		return
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return obj.distance_to(a) < obj.distance_to(b))
	var choice: int = [0, 0, 0, 1, 1, 2][randi() % 6] if spots.size() >= 3 else randi() % spots.size()
	var destination := spots[mini(choice, spots.size() - 1)]
	obj.move_command = 43
	obj.move_destination = destination
	obj.waypoint = destination
	obj.path = 0


## Plays a sound at a point (MDK coordinates), independently of any object.
func play_sound_at(sound_name: String, point: Vector3) -> void:
	var stream := level.get_sound(sound_name)
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.unit_size = 50.0
	player.position = MDKMeshBuilder.to_godot(point)
	player.finished.connect(player.queue_free)
	player.add_to_group(&"mdk_sounds")
	player.set_meta(&"sound", sound_name.to_upper())
	add_child(player)
	player.play()


## Kurt takes the pickups he runs through (`damp_collect_pickups` 0x46c448): the segment he moved
## along this tick crosses a pickup's bounds, grown by 1 unit (and 5 downwards).
func collect_pickups() -> void:
	for obj in objects:
		if obj.dead or obj.arena != current_arena or not obj.flags & MDKObject.FLAG_PICKUP \
				or obj.flags & (MDKObject.FLAG_COLLECTED | MDKObject.FLAG_NOT_SOLID):
			continue
		var bounds := get_world_bounds(obj)
		bounds = AABB(bounds.position - Vector3(1, 1, 5), bounds.size + Vector3(2, 2, 6))
		if not bounds.has_point(kurt_position) and bounds.intersects_segment(_previous_kurt_position, kurt_position) == null:
			continue
		var sound := kurt.inventory.collect(obj.type_name, kurt)
		if sound.is_empty():
			continue
		play_sound_at(sound, kurt_position)
		obj.flags |= MDKObject.FLAG_COLLECTED | 0x1000
		obj.parameter_timer = 30.0
		obj.velocity = Vector3.ZERO
		obj.flags &= ~MDKObject.FLAG_GRAVITY
		if obj.attached:
			remove(obj.attached)
			obj.attached = null


## Spawns a connector (a door) between `obj`'s arena and `other_arena` (`spawn_connector`). A
## connector of that type already linking both arenas is moved into this arena instead, unless it's
## in Kurt's arena.
func spawn_connector(obj: MDKObject, type_name: String, mdk_position: Vector3, yaw: float, instance: int, other_arena: String, script: int) -> void:
	if other_arena == "NONE":
		return
	for other in objects:
		if not other.dead and other.type_name == type_name and ((other.arena == obj.arena and other.connects == other_arena) or (other.arena == other_arena and other.connects == obj.arena)):
			if other.arena != current_arena:
				other.arena = obj.arena
				other.connects = other_arena
			return
	var door := spawn(obj, type_name, mdk_position, yaw, instance, script, false)
	if door:
		door.flags |= 0x1108000
		door.connects = other_arena
		behaviors.setup_door(door)


## Fires a projectile (`fire`): the global model `bullet_name` starts at a reference point of `obj`
## (`origin` = `[0, index]`) or at the centre of one of its parts (`[1, name]`), flying along the
## object's yaw and pitch, and runs `script`.
func fire(obj: MDKObject, origin: Array, bullet_name: String, script: int) -> MDKObject:
	var start := obj.get_reference_point(origin[1]) if origin[0] == 0 else obj.get_part_center(obj.find_part(origin[1]))
	var bullet := spawn(obj, bullet_name, start, obj.yaw, -1, 0, false)
	if not bullet:
		return null
	bullet.move_command = 61
	bullet.flags |= PROJECTILE_FLAGS
	bullet.pitch = obj.pitch
	bullet.restart = script
	bullet.update_transform()
	return bullet


func hurt_kurt(damage: int) -> void:
	kurt.hurt(damage)


## Whether Kurt looks at an object (0x460730): it's `min_range`–`max_range` away, within a cone around
## his yaw that narrows from 90° next to him to `cone` at `max_range`, and in sight.
func kurt_looks_at(obj: MDKObject, min_range: float, max_range: float, cone: float) -> bool:
	var distance := kurt_position.distance_to(obj.mdk_position)
	if distance < min_range or distance > max_range:
		return false
	var angle := fposmod(absf(kurt_yaw - rad_to_deg(atan2(obj.mdk_position.y - kurt_position.y, obj.mdk_position.x - kurt_position.x))), 360.0)
	var allowed := (cone - 90.0) / max_range * distance + 90.0
	if angle > allowed and angle < 360.0 - allowed:
		return false
	return raycast(kurt_position + Vector3(0, 0, 5), obj.mdk_position + Vector3(0, 0, 2)).is_empty()


## The object Kurt stands on (`0x573b84`), if any.
func get_kurt_platform() -> MDKObject:
	if not kurt.is_on_floor():
		return null
	for i in kurt.get_slide_collision_count():
		var collision := kurt.get_slide_collision(i)
		var body := collision.get_collider() as Node
		if body and collision.get_normal().y > 0.7 and body.get_parent() is MDKObject:
			return body.get_parent()
	return null


## Contact damage of an object (`touch_damage` 0x45cf60): `targets` 1 hurts Kurt once for each
## visible part touching him, 2 hurts the other objects touching its box (hit event −3, hit type
## −4). With `flags` 1 the object dies when it hits. Returns whether it hit.
func touch_damage(obj: MDKObject, targets: int, damage: int, flags: int) -> bool:
	var box := get_world_bounds(obj)
	var hit := false
	if targets & 1:
		var kurt_box := get_kurt_box()
		if box.intersects(kurt_box):
			var part_bounds := obj.get_part_bounds()
			for i in part_bounds.size():
				if not obj.hidden_parts & (1 << i) and get_world_bounds(obj, part_bounds[i]).intersects(kurt_box):
					kurt.hurt(damage)
					hit = true
	if targets & 2:
		for other in objects.duplicate():
			if other == obj or other.dead or other.arena != obj.arena or other.flags & 0x820:
				continue
			if not box.intersects(get_world_bounds(other)):
				continue
			hit = true
			other.hit_event = -3
			other.hit_type = -4
			other.hit_direction = obj.yaw
			if other.health < 65000:
				other.health -= damage
			if other.health < 1:
				kill(other)
	if hit and flags & 1:
		kill(obj)
	return hit


## `push_kurt`: knocks Kurt down (unless he's already down), pushed along the object's frame (mode
## 0: `[0, a, b, up]`) or away from it (`[mode, a, up]`), and `up` added to his vertical speed.
func push_kurt(obj: MDKObject, args: Array) -> void:
	if kurt.state in [Kurt.State.KNOCKED, Kurt.State.DEAD]:
		return
	var push: Vector2
	var up: float
	if args[0] == 0:
		var c := cos(deg_to_rad(obj.yaw))
		var s := sin(deg_to_rad(obj.yaw))
		push = Vector2(-args[1] * c - args[2] * s, -args[2] * c - args[1] * s)
		up = args[3]
	else:
		var away := Vector2(kurt_position.x - obj.mdk_position.x, kurt_position.y - obj.mdk_position.y)
		push = away.normalized() * args[1] if away != Vector2.ZERO else Vector2(args[1], 0.0)
		up = args[2]
	# The push is added once per tick of the frame, in units per tick.
	push *= TICK * 30.0
	kurt.knock_down(Vector2(push.x, -push.y))
	kurt.velocity.y += up


## Kurt's bounding box (MDK coordinates).
func get_kurt_box() -> AABB:
	return AABB(kurt_position - Vector3(0.6, 0.6, 0.0), Vector3(1.2, 1.2, 5.0))


## Lowest point (MDK Z) of an arena's geometry.
func get_arena_floor(arena_name: String) -> float:
	var bounds: Variant = level.arena_bounds.get(arena_name)
	return bounds.position.y if bounds else -1000.0


## Casts a ray against the level geometry (MDK coordinates). Returns the hit as by `intersect_ray`
## (Godot coordinates), or an empty dictionary.
func raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(MDKMeshBuilder.to_godot(from), MDKMeshBuilder.to_godot(to), LEVEL_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query)


## Destination near the target (`move_near_target`): the target position offset by `forward` and
## `side` × 1% of the distance, in the frame of the direction from `obj` to the target.
func near_target_destination(obj: MDKObject, forward: float, side: float) -> Vector3:
	var p := obj.mdk_position
	var direction := Vector2(target_position.x - p.x, target_position.y - p.y).angle()
	var offset := Vector2(forward, side).rotated(direction) * 0.01 * obj.distance_to(target_position)
	return Vector3(target_position.x + offset.x, target_position.y + offset.y, target_position.z + obj.height_offset)


## Whether `sender` may command `receiver` (`command_objects`, `if_count_objects`): the receiver
## has no other leader of a higher priority, and obeys the sender's priority.
static func may_command(sender: MDKObject, receiver: MDKObject) -> bool:
	var leader := receiver.leader
	if leader and leader != sender and not leader.dead and sender.priority <= leader.priority:
		return false
	return receiver.obey_level >= sender.priority


## Sends a command to objects (`command_objects` 0x440384). Commands: 1 join a formation around the
## sender, 7 goto `target`, 0xFC gosub `target`, 43 go to `destination`. Selectors: 2 all of
## `type_name`, 3 all, 4 the first of `type_name`, 5 of `type_name` with instance `id`, 6 of
## `type_name` within `param` with a line of sight, 7 of `type_name` following the sender, 8 all
## following the sender, 9 the linked object, 10 of `type_name` with Y >= `param`.
func command_objects(sender: MDKObject, command: int, target: int, destination: Vector3, selector: int, type_name: String, param: float, id: int) -> void:
	var formation_index := 0
	if selector == 9:
		if sender.linked and not sender.linked.dead:
			_command_object(sender, sender.linked, command, target, destination, formation_index)
		return
	for receiver in get_arena_objects(sender):
		if selector not in [3, 8] and receiver.type_name.to_upper() != type_name.to_upper():
			continue
		if not may_command(sender, receiver):
			continue
		if selector in [7, 8] and receiver.leader != sender:
			continue
		if selector == 5 and receiver.instance_id != id:
			continue
		if selector == 6:
			if sender.distance_to(receiver.mdk_position) > param:
				continue
			if not raycast(sender.mdk_position + Vector3(0, 0, 8), receiver.mdk_position + Vector3(0, 0, 8)).is_empty():
				continue
		if selector == 10 and receiver.mdk_position.y < param:
			continue
		if (command == 7 and receiver.command_target == target) or receiver.health == 0:
			continue
		if _command_object(sender, receiver, command, target, destination, formation_index):
			formation_index += 1
		if selector == 4:
			return


## Applies a command to one object (0x4405d0). Returns true when it joined a formation.
func _command_object(sender: MDKObject, receiver: MDKObject, command: int, target: int, destination: Vector3, formation_index: int) -> bool:
	match command:
		1:
			# Formation places alternate left and right, 5 units apart (wider for XE).
			var wide := receiver.type_name.to_upper() == "XE"
			var spread := 4.0 if wide else 1.0
			var back := 2.5 if wide else 1.0
			var side := 1.0 if formation_index & 1 else -1.0
			receiver.waypoint = Vector3(side * (formation_index / 2 + 1) * 5.0 * spread, back * -4.0, 8.0)
			receiver.move_destination = MDKObjectMotion.formation_position(sender, receiver.waypoint)
			receiver.leader = sender
			receiver.move_command = 1
			receiver.path = 0
			return true
		7:
			receiver.wait_time = 0.0
			receiver.restart = target
			receiver.wait_resume = target
			receiver.leader = sender
			receiver.gosub_returns.clear()
			receiver.gosub_restarts.clear()
			receiver.level_timers[0] = 0.0
			receiver.command_target = target
		0xFC:
			if receiver.gosub_returns.size() < MDKScriptVM.GOSUB_DEPTH:
				receiver.gosub_returns.push_back(receiver.restart)
				receiver.gosub_restarts.push_back(receiver.restart)
				receiver.wait_time = 0.0
				receiver.restart = target
				receiver.wait_resume = target
				receiver.leader = sender
				receiver.level_timers[receiver.gosub_returns.size()] = 0.0
		43:
			if receiver.arena == current_arena:
				receiver.move_destination = destination
				receiver.leader = sender
				receiver.move_command = 43
				receiver.path = 0
				motion.plan_move(receiver)
	return false


## World bounds (MDK) of an object in its current pose (`obj+0x198`), or of `bounds` (model space),
## turned by its yaw.
func get_world_bounds(obj: MDKObject, bounds: Variant = null) -> AABB:
	if bounds == null:
		if not obj.model:
			return AABB(obj.mdk_position, Vector3.ZERO)
		bounds = obj.get_pose_bounds()
	var box: AABB = bounds
	var out := AABB()
	for i in 8:
		var corner := obj.mdk_position + (box.get_endpoint(i) * obj.model_scale).rotated(Vector3.BACK, deg_to_rad(obj.yaw))
		out = AABB(corner, Vector3.ZERO) if i == 0 else out.expand(corner)
	return out


## Objects of the arena of `obj`, alive, other than `obj` (for commands and counts).
func get_arena_objects(obj: MDKObject) -> Array[MDKObject]:
	var out: Array[MDKObject] = []
	for other in objects:
		if other != obj and not other.dead and other.arena == obj.arena:
			out.push_back(other)
	return out


## Returns the animation referenced by a script operand: an animation stored in the CMI file, or
## (when its first `u32` is 0) the arena animation named after it.
func get_animation(obj: MDKObject, offset: int) -> MDKModelAnimation:
	if offset == 0:
		return null
	var bytes := level.cmi.bytes
	if bytes.decode_u32(offset) == 0:
		return find_arena_animation(obj.arena, bytes.slice(offset + 4, offset + 12).get_string_from_ascii())
	if not _animations.has(offset):
		_animations[offset] = MDKModelAnimation.parse("CMI_%x" % offset, bytes, offset)
	return _animations[offset]


## An animation of an arena's models, by name (`arena_find_animation` 0x440adc).
func find_arena_animation(arena_name: String, animation_name: String) -> MDKModelAnimation:
	var arena := level.mto.get_arena(arena_name) if level.mto.arena_offsets.has(arena_name) else null
	return arena.animations.get(animation_name) if arena else null


func find_model(arena_name: String, type_name: String) -> MDKModel:
	var model := level.cmi.get_model(type_name)
	if model:
		return model
	if level.mto.arena_offsets.has(arena_name):
		return level.mto.get_arena(arena_name).models.get(type_name)
	return null


## The materials and palette of an arena.
func get_resolver(arena_name: String) -> MDKMeshBuilder.MaterialResolver:
	if not _resolvers.has(arena_name):
		var arena := level.mto.get_arena(arena_name) if level.mto.arena_offsets.has(arena_name) else null
		var palette := level.dti.palette.with_arena_colors(arena.palette_rgb) if arena else level.dti.palette
		var archives: Array[MDKTextureArchive] = [level.level_textures]
		if arena:
			archives.push_front(arena.textures)
		_resolvers[arena_name] = MDKMeshBuilder.MaterialResolver.new(palette, archives)
		# Some models have flat parts seen from both sides (e.g. the petals of iris doors).
		_resolvers[arena_name].double_sided = true
	return _resolvers[arena_name]


## `can_see_kurt`: Kurt within `range`, inside a cone around the object's yaw, with a clear line of
## sight. The cone's exact formula isn't reverse engineered; `cone` is used as a half angle in degrees.
func can_see_kurt(obj: MDKObject, range: float, cone: float) -> bool:
	if obj.distance_to(kurt_position) > range:
		return false
	if cone < 180.0 and absf(wrapf(obj.yaw_to(kurt_position) - obj.yaw, -180.0, 180.0)) > maxf(cone, 10.0):
		return false
	return raycast(obj.mdk_position + Vector3(0, 0, 5), kurt_position + Vector3(0, 0, 4)).is_empty()


## `play_sound`: plays a sound at the object (3D) or without position (flag 0x80). `flags & 3`:
## 0 play, 1 restart, 2 play unless it's already playing, 3 stop.
func play_sound(obj: MDKObject, sound_name: String, flags: int, _position: Variant) -> void:
	var mode := flags & 3
	if flags & 4:
		obj.tracked_sound = sound_name
	var existing := obj.get_node_or_null(NodePath("Sound_" + sound_name))
	if existing:
		if mode == 2 and existing.playing:
			return
		if mode == 3 or mode == 1:
			existing.stop()
			if mode == 3:
				return
		existing.play()
		return
	if mode == 3:
		return
	var stream := level.get_sound(sound_name)
	if not stream:
		return
	var player: Node
	if flags & 0x80:
		player = AudioStreamPlayer.new()
	else:
		player = AudioStreamPlayer3D.new()
		player.unit_size = 50.0
	player.name = "Sound_" + sound_name
	player.stream = stream
	player.add_to_group(&"mdk_sounds")
	player.set_meta(&"sound", sound_name.to_upper())
	obj.add_child(player)
	player.play()

## A loaded MDK level: arena meshes, collision, sky and level data.
class_name Level
extends Node3D

const SKY_SHADER := preload("res://mdk/shaders/sky.gdshader")
## Triangle flags changed by scripts (`group_set_state`): hidden, and not solid.
const TRIANGLE_HIDDEN := 0x10
const TRIANGLE_NOT_SOLID := 0x20


## The triangles of an arena that share a group number (the top byte of their flags), which scripts
## show, hide, retexture or make destructible together. Group 0 is the rest of the arena.
class TriangleGroup:
	var triangles := PackedInt32Array()
	var mesh: MeshInstance3D
	var shape: CollisionShape3D
	## `TRIANGLE_HIDDEN` and `TRIANGLE_NOT_SOLID`.
	var flags := 0


var number := 0
var dti: MDKDti
var mto: MDKMto
var level_textures: MDKTextureArchive
var cmi: MDKCmi
## `TRAVERSE.SNI`, `LEVELnS.SNI` and `LEVELnO.SNI` (searched in reverse order by `get_sound()`).
var sound_archives: Array[MDKSni] = []
var triangle_count := 0
## Bounds of each arena's geometry (Godot coordinates) and its camera pitch in degrees (DTI).
var arena_bounds := {}
var arena_pitch := {}
## Arena name to its triangle groups (group number to `TriangleGroup`).
var arena_groups := {}

var _arenas := {}
var _resolvers := {}


## Loads level `p_number` (3–8) and builds its arenas.
func load_level(p_number: int) -> void:
	number = p_number
	var dir := "TRAVERSE/LEVEL%d/" % number
	dti = MDKDti.load_file(MDKData.path(dir + "LEVEL%d.DTI" % number))
	mto = MDKMto.load_file(MDKData.path(dir + "LEVEL%dO.MTO" % number))
	level_textures = MDKTextureArchive.load_file(MDKData.path(dir + "LEVEL%dS.MTI" % number))
	cmi = MDKCmi.load_file(MDKData.path(dir + "LEVEL%d.CMI" % number))
	var overlays := MDKSni.load_file(MDKData.path(dir + "LEVEL%dO.SNI" % number))
	sound_archives = [MDKSni.load_file(MDKData.path("TRAVERSE/TRAVERSE.SNI")),
			MDKSni.load_file(MDKData.path(dir + "LEVEL%dS.SNI" % number)), overlays]

	var all_archives: Array[MDKTextureArchive] = []
	for arena_name: String in mto.get_arena_names():
		all_archives.push_back(mto.get_arena(arena_name).textures)

	var arenas: Array[MDKArena] = []
	for arena_name: String in mto.get_arena_names():
		arenas.push_back(mto.get_arena(arena_name))
	# Corridors between arenas (`CHMO_1` follows `HMO_1`) are stored in `LEVELnO.SNI`.
	for entry_name: String in overlays.entries:
		if not overlays.is_sound(entry_name):
			var corridor := MDKArena.parse_world(entry_name, overlays.bytes, overlays.entries[entry_name][0])
			# Empty corridors are a placeholder quad with the `NONE` material.
			if corridor.materials != ["NONE"]:
				arenas.push_back(corridor)

	for arena in arenas:
		var arena_name := arena.name
		var palette_arena := arena
		if arena.palette_rgb.is_empty():
			palette_arena = mto.get_arena(arena_name.substr(1)) if mto.arena_offsets.has(arena_name.substr(1)) else arenas[0]
		var palette := dti.palette.with_arena_colors(palette_arena.palette_rgb)
		# Some arenas use textures of another arena (e.g. `O3_*` in level 6), so search them last.
		var archives: Array[MDKTextureArchive] = [arena.textures, level_textures]
		archives.append_array(all_archives)
		var resolver := MDKMeshBuilder.MaterialResolver.new(palette, archives)
		_arenas[arena_name] = arena
		_resolvers[arena_name] = resolver
		var root := Node3D.new()
		root.name = arena_name
		add_child(root)
		var groups := {}
		for tri in arena.triangle_flags.size():
			var group_number := (arena.triangle_flags[tri] >> 24) & 0xFF
			if not groups.has(group_number):
				groups[group_number] = TriangleGroup.new()
			groups[group_number].triangles.push_back(tri)
		for group_number: int in groups:
			_build_group(arena, root, group_number, groups[group_number])
		arena_groups[arena_name] = groups
		if not resolver.missing.is_empty():
			push_warning("%s: materials not found: %s" % [arena_name, ", ".join(resolver.missing)])
		triangle_count += arena.triangle_materials.size()
		var aabb := AABB(MDKMeshBuilder.to_godot(arena.vertices[0]), Vector3.ZERO)
		for v in arena.vertices:
			aabb = aabb.expand(MDKMeshBuilder.to_godot(v))
		arena_bounds[arena_name] = aabb

	for entry in dti.arenas:
		arena_pitch[entry.name] = entry.value

	_setup_sky()


func _build_group(arena: MDKArena, root: Node3D, group_number: int, group: TriangleGroup) -> void:
	var suffix := "" if group_number == 0 else "_%d" % group_number
	group.mesh = MeshInstance3D.new()
	group.mesh.name = "Mesh" + suffix
	group.mesh.mesh = MDKMeshBuilder.build_arena_mesh(arena, _resolvers[arena.name], group.triangles)
	root.add_child(group.mesh)
	var body := StaticBody3D.new()
	body.name = "Collision" + suffix
	body.set_meta(&"arena", arena.name)
	body.set_meta(&"group", group_number)
	group.shape = CollisionShape3D.new()
	group.shape.shape = MDKMeshBuilder.build_arena_collision(arena, group.triangles)
	body.add_child(group.shape)
	root.add_child(body)


## Changes the flags of a triangle group (`group_set_state` op): 0 hides it and makes it not solid,
## 1 (and others) shows it and makes it solid, 2/3 hide/show, 4/5 not solid/solid.
func set_group_state(arena_name: String, group_number: int, op: int) -> void:
	var group: TriangleGroup = arena_groups.get(arena_name, {}).get(group_number)
	if not group or group_number == 0:
		return
	match op:
		0:
			group.flags |= TRIANGLE_HIDDEN | TRIANGLE_NOT_SOLID
		2:
			group.flags |= TRIANGLE_HIDDEN
		3:
			group.flags &= ~TRIANGLE_HIDDEN
		4:
			group.flags |= TRIANGLE_NOT_SOLID
		5:
			group.flags &= ~TRIANGLE_NOT_SOLID
		_:
			group.flags &= ~(TRIANGLE_HIDDEN | TRIANGLE_NOT_SOLID)
	group.mesh.visible = not group.flags & TRIANGLE_HIDDEN
	group.shape.set_deferred(&"disabled", group.flags & TRIANGLE_NOT_SOLID != 0)


## Gives every triangle of a group the material `value` (`group_set_texture`).
func set_group_texture(arena_name: String, group_number: int, value: int) -> void:
	var group: TriangleGroup = arena_groups.get(arena_name, {}).get(group_number)
	if group and group_number != 0:
		group.mesh.mesh = MDKMeshBuilder.build_arena_mesh(_arenas[arena_name], _resolvers[arena_name], group.triangles, value)


## Returns the group of the arena floor below `position` (Godot coordinates), or 0.
func get_floor_group(position: Vector3, exclude: Array[RID]) -> int:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP, position + Vector3.DOWN * 10.0, 1)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_meta(&"group", 0) if not hit.is_empty() else 0


## Returns the name of the (smallest) arena whose bounds contain `position`, or an empty string.
func get_arena_at(position: Vector3) -> String:
	var best := ""
	var best_volume := INF
	for arena_name: String in arena_bounds:
		var aabb: AABB = arena_bounds[arena_name]
		if aabb.grow(2.0).has_point(position) and aabb.get_volume() < best_volume:
			best = arena_name
			best_volume = aabb.get_volume()
	return best


## Returns the camera pitch (degrees, positive looks down) of the arena containing `position`.
func get_camera_pitch(position: Vector3) -> float:
	return arena_pitch.get(get_arena_at(position), 4.0)


## Returns a sound by name (loaded on first use), or `null`.
func get_sound(sound_name: String) -> AudioStreamWAV:
	for i in range(sound_archives.size() - 1, -1, -1):
		if sound_archives[i].entries.has(sound_name):
			return sound_archives[i].get_sound(sound_name)
	return null


## Returns the music of an arena (an AudioStreamWAV), or `null`.
func get_arena_music(arena_name: String) -> AudioStream:
	return get_sound(cmi.arena_music.get(arena_name, "NONE"))


## Player start position (Godot coordinates).
func get_start_position() -> Vector3:
	return MDKMeshBuilder.to_godot(dti.start_position)


## Player start yaw (Godot convention: 0 faces -Z).
func get_start_yaw() -> float:
	return deg_to_rad(dti.start_angle - 90.0)


## Returns the level's base palette (indices 0–63 are the same in every arena, used by sprites).
func get_palette() -> MDKPalette:
	return dti.palette


func _setup_sky() -> void:
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter(&"sky_index", dti.sky.get_index_texture())
	material.set_shader_parameter(&"palette", dti.palette.get_texture())
	material.set_shader_parameter(&"texture_width", float(dti.sky.width))
	material.set_shader_parameter(&"wrap_width", float(dti.sky_wrap_width))
	material.set_shader_parameter(&"horizon_row", float(dti.sky_horizon_row))
	material.set_shader_parameter(&"offset", float(dti.sky_offset))
	material.set_shader_parameter(&"top_color", dti.sky_top_color)
	material.set_shader_parameter(&"bottom_color", dti.sky_bottom_color)
	var sky := Sky.new()
	sky.sky_material = material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

## A loaded MDK level: arena meshes, collision, sky and level data.
class_name Level
extends Node3D

const SKY_SHADER := preload("res://mdk/shaders/sky.gdshader")

var number := 0
var dti: MDKDti
var mto: MDKMto
var level_textures: MDKTextureArchive
var triangle_count := 0
## Bounds of each arena's geometry (Godot coordinates) and its camera pitch in degrees (DTI).
var arena_bounds := {}
var arena_pitch := {}


## Loads level `p_number` (3–8) and builds its arenas.
func load_level(p_number: int) -> void:
	number = p_number
	var dir := "TRAVERSE/LEVEL%d/" % number
	dti = MDKDti.load_file(MDKData.path(dir + "LEVEL%d.DTI" % number))
	mto = MDKMto.load_file(MDKData.path(dir + "LEVEL%dO.MTO" % number))
	level_textures = MDKTextureArchive.load_file(MDKData.path(dir + "LEVEL%dS.MTI" % number))

	var all_archives: Array[MDKTextureArchive] = []
	for arena_name: String in mto.get_arena_names():
		all_archives.push_back(mto.get_arena(arena_name).textures)

	for arena_name: String in mto.get_arena_names():
		var arena := mto.get_arena(arena_name)
		var palette := dti.palette.with_arena_colors(arena.palette_rgb)
		# Some arenas use textures of another arena (e.g. `O3_*` in level 6), so search them last.
		var archives: Array[MDKTextureArchive] = [arena.textures, level_textures]
		archives.append_array(all_archives)
		var resolver := MDKMeshBuilder.MaterialResolver.new(palette, archives)
		var instance := MeshInstance3D.new()
		instance.name = arena_name
		instance.mesh = MDKMeshBuilder.build_arena_mesh(arena, resolver)
		add_child(instance)
		if not resolver.missing.is_empty():
			push_warning("%s: materials not found: %s" % [arena_name, ", ".join(resolver.missing)])

		var body := StaticBody3D.new()
		body.name = "Collision"
		var shape := CollisionShape3D.new()
		shape.shape = MDKMeshBuilder.build_arena_collision(arena)
		body.add_child(shape)
		instance.add_child(body)
		triangle_count += arena.triangle_materials.size()
		var aabb := AABB(MDKMeshBuilder.to_godot(arena.vertices[0]), Vector3.ZERO)
		for v in arena.vertices:
			aabb = aabb.expand(MDKMeshBuilder.to_godot(v))
		arena_bounds[arena_name] = aabb

	for entry in dti.arenas:
		arena_pitch[entry.name] = entry.value

	_setup_sky()


## Returns the camera pitch (degrees, positive looks down) of the arena containing `position`.
func get_camera_pitch(position: Vector3) -> float:
	var best := ""
	var best_volume := INF
	for arena_name: String in arena_bounds:
		var aabb: AABB = arena_bounds[arena_name]
		if aabb.grow(2.0).has_point(position) and aabb.get_volume() < best_volume:
			best = arena_name
			best_volume = aabb.get_volume()
	return arena_pitch.get(best, 4.0)


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

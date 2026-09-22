## Builds Godot meshes from MDK geometry.
class_name MDKMeshBuilder
extends RefCounted

const PALETTE_SHADER := preload("res://mdk/shaders/palette.gdshader")

## Special material values (palette "colors" ≥ 256, named in the level's MTI archive).
const SPECIAL_NONE := 256  # Invisible.
const SPECIAL_ENV := 257  # `PEN_ENV` ❓
const SPECIAL_MIRROR_FIRST := 990  # `MIRRLOW` (990), `MIRRMED` (1000), `MIRRHIGH` (1010).
const SPECIAL_MIRROR_LAST := 1010
const SPECIAL_GLASS_FIRST := 1024  # `GLASS1`–`GLASS4`.
const SPECIAL_GLASS_LAST := 1027
const SPECIAL_RIPPLE := 1028  # Water.


## Resolves MDK material references (texture names, palette colors) to Godot materials.
class MaterialResolver:
	var palette: MDKPalette
	## Archives searched for textures, in order (e.g. the arena's, then the level's).
	var archives: Array[MDKTextureArchive] = []
	## Special material values (≥ 256) that were skipped, with their triangle counts.
	var skipped_special := {}
	var missing: Array[String] = []

	var _texture_materials := {}
	var _color_materials := {}


	func _init(p_palette: MDKPalette, p_archives: Array[MDKTextureArchive]) -> void:
		palette = p_palette
		archives = p_archives


	## Returns the texture used by a material name, or `null`.
	func find_texture(material_name: String) -> MDKTexture:
		for archive in archives:
			if archive.textures.has(material_name):
				return archive.textures[material_name]
		return null


	## Returns the Godot material for a triangle material value (see `MDKArena.triangle_materials`),
	## or `null` if the triangle shouldn't be drawn.
	func get_material(value: int, material_names: Array[String]) -> Material:
		if value < 0:
			return _get_color_material(-value)
		var material_name := material_names[value]
		var texture := find_texture(material_name)
		if texture:
			if not _texture_materials.has(texture):
				_texture_materials[texture] = MDKMeshBuilder.make_palette_material(texture, palette)
			return _texture_materials[texture]
		for archive in archives:
			if archive.colors.has(material_name):
				return _get_color_material(archive.colors[material_name])
		if material_name.begins_with("PEN_"):
			return _get_color_material(int(material_name.substr(4)))
		if material_name != "NONE" and material_name not in missing:
			missing.push_back(material_name)
		return null


	func _get_color_material(index: int) -> Material:
		if not _color_materials.has(index):
			if index < 256:
				_color_materials[index] = MDKMeshBuilder.make_color_material(palette.get_color(index))
			else:
				_color_materials[index] = MDKMeshBuilder.make_special_material(index)
		if not _color_materials[index]:
			skipped_special[index] = skipped_special.get(index, 0) + 1
		return _color_materials[index]


## Converts MDK coordinates (Z up) to Godot coordinates (Y up).
static func to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## Builds the world mesh of an arena, with one surface per material.
static func build_arena_mesh(arena: MDKArena, resolver: MaterialResolver) -> ArrayMesh:
	var by_material := {}
	for tri in arena.triangle_materials.size():
		var material := resolver.get_material(arena.triangle_materials[tri], arena.materials)
		if not material:
			continue
		if not by_material.has(material):
			by_material[material] = PackedInt32Array()
		by_material[material].push_back(tri)

	var mesh := ArrayMesh.new()
	for material: Material in by_material:
		var uv_scale: Vector2 = material.get_meta(&"uv_scale", Vector2.ZERO)
		var triangles: PackedInt32Array = by_material[material]
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		positions.resize(triangles.size() * 3)
		uvs.resize(triangles.size() * 3)
		var i := 0
		for tri in triangles:
			for k in 3:
				positions[i] = to_godot(arena.vertices[arena.triangle_indices[tri * 3 + k]])
				uvs[i] = arena.triangle_uvs[tri * 3 + k] * uv_scale
				i += 1

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Builds the mesh of a model in a given pose (the vertices of each part, see `MDKModel.get_rest_pose()`
## and `MDKModelAnimation.bake()`), with one surface per material.
static func build_model_mesh(model: MDKModel, pose: Array, resolver: MaterialResolver) -> ArrayMesh:
	var by_material := {}
	for p in model.parts.size():
		var part := model.parts[p]
		for tri in part.triangle_materials.size():
			var material := resolver.get_material(part.triangle_materials[tri], model.materials)
			if not material:
				continue
			if not by_material.has(material):
				by_material[material] = []
			by_material[material].push_back(Vector2i(p, tri))

	var mesh := ArrayMesh.new()
	for material: Material in by_material:
		var uv_scale: Vector2 = material.get_meta(&"uv_scale", Vector2.ZERO)
		var triangles: Array = by_material[material]
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		positions.resize(triangles.size() * 3)
		uvs.resize(triangles.size() * 3)
		var i := 0
		for key: Vector2i in triangles:
			var part := model.parts[key.x]
			var vertices: PackedVector3Array = pose[key.x]
			for k in 3:
				positions[i] = to_godot(vertices[part.triangle_indices[key.y * 3 + k]])
				uvs[i] = part.triangle_uvs[key.y * 3 + k] * uv_scale
				i += 1
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Builds the collision shape of an arena (every triangle, including invisible ones).
static func build_arena_collision(arena: MDKArena) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	faces.resize(arena.triangle_indices.size())
	for i in arena.triangle_indices.size():
		faces[i] = to_godot(arena.vertices[arena.triangle_indices[i]])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


static func make_palette_material(texture: MDKTexture, palette: MDKPalette) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PALETTE_SHADER
	material.set_shader_parameter(&"index_texture", texture.get_index_texture())
	material.set_shader_parameter(&"palette", palette.get_texture())
	material.set_shader_parameter(&"frame_count", texture.frame_count)
	# UVs are in texels of one frame.
	material.set_meta(&"uv_scale", Vector2(1.0 / texture.width, 1.0 / texture.height))
	return material


## Placeholder materials for special surfaces, until their effects are reverse engineered.
static func make_special_material(value: int) -> Material:
	var color: Color
	if value >= SPECIAL_MIRROR_FIRST and value <= SPECIAL_MIRROR_LAST:
		color = Color(0.25, 0.3, 0.35, 0.75)
	elif value >= SPECIAL_GLASS_FIRST and value <= SPECIAL_GLASS_LAST:
		color = Color(0.7, 0.85, 1.0, 0.2 + 0.1 * (value - SPECIAL_GLASS_FIRST))
	elif value == SPECIAL_RIPPLE:
		color = Color(0.2, 0.45, 0.6, 0.7)
	elif value == SPECIAL_ENV:
		color = Color(0.6, 0.6, 0.65)
	else:
		return null
	var material := make_color_material(color)
	# Glass, mirrors and water are visible from both sides.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func make_color_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = color
	return material

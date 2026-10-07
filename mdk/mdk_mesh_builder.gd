## Builds Godot meshes from MDK geometry.
class_name MDKMeshBuilder
extends RefCounted

const PALETTE_SHADER := preload("res://mdk/shaders/palette.gdshader")
const PALETTE_DOUBLE_SIDED_SHADER := preload("res://mdk/shaders/palette_double_sided.gdshader")
const PALETTE_LIT_SHADER := preload("res://mdk/shaders/palette_lit.gdshader")
const PALETTE_LIT_DOUBLE_SIDED_SHADER := preload("res://mdk/shaders/palette_lit_double_sided.gdshader")

## The original look (unlit, nearest texels) or the enhanced one (lit, filtered).
enum Look { ORIGINAL, ENHANCED }
## Which sides of a face stop what collides with it.
enum Sides { BOTH, FRONT }

## Special material values (palette "colors" ≥ 256, named in the level's MTI archive).
const SPECIAL_NONE := 256  # Invisible.
const SPECIAL_ENV := 257  # `PEN_ENV` ❓
const SPECIAL_MIRROR_FIRST := 990  # `MIRRLOW` (990), `MIRRMED` (1000), `MIRRHIGH` (1010).
const SPECIAL_MIRROR_LAST := 1010
const SPECIAL_GLASS_FIRST := 1024  # `GLASS1`–`GLASS4`.
const SPECIAL_GLASS_LAST := 1027
const SPECIAL_RIPPLE := 1028  # Water.
## Lift of a detail above the triangle it lies on, per layer (see `arena_positions`), and how
## finely planes are told apart (1/64 of a unit).
const LAYER_LIFT := 0.03
const PLANE_STEPS := 64.0
## The highest layer, so lifts stay small.
const LAYER_HIGHEST := 3
## Overlaps below this area (square units) are rounding: neighbours sharing an edge.
const MIN_OVERLAP := 1e-3

static var _positions_cache := {}

## Arena triangle flags (0x40b7f0): bit 23 outlines the triangle in its own colour, along the edges
## bits 20 (v0–v1), 21 (v1–v2) and 22 (v2–v0) pick.
const OUTLINE := 1 << 23
const OUTLINE_EDGES := [[1 << 20, 0, 1], [1 << 21, 1, 2], [1 << 22, 2, 0]]
## Normals at most ~2.5° apart: one flat surface.
const COPLANAR_COS := 0.999


## Resolves MDK material references (texture names, palette colors) to Godot materials.
class MaterialResolver:
	var palette: MDKPalette
	## Archives searched for textures, in order (e.g. the arena's, then the level's).
	var archives: Array[MDKTextureArchive] = []
	## Special material values (≥ 256) that were skipped, with their triangle counts.
	var skipped_special := {}
	var missing: Array[String] = []
	## Draw both faces of triangles (models).
	var double_sided := false
	## The level's glass and mirrors; without them special values get placeholder colours.
	var specials: MDKSpecialMaterials
	var look := Look.ORIGINAL

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


	## The material made for a texture, or `null` if no triangle uses it.
	func get_texture_material(texture_name: String) -> Material:
		var texture := find_texture(texture_name)
		return _texture_materials.get(texture) if texture else null


	## Returns the Godot material for a triangle material value (see `MDKArena.triangle_materials`),
	## or `null` if the triangle shouldn't be drawn.
	func get_material(value: int, material_names: Array[String]) -> Material:
		if value < 0:
			return _get_color_material(-value)
		var material_name := material_names[value]
		var texture := find_texture(material_name)
		if texture:
			if not _texture_materials.has(texture):
				_texture_materials[texture] = MDKMeshBuilder.make_palette_material(texture, palette, double_sided, look)
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
				_color_materials[index] = MDKMeshBuilder.make_color_material(palette.get_color(index), double_sided, look)
			elif specials:
				_color_materials[index] = specials.get_material(index)
			else:
				_color_materials[index] = MDKMeshBuilder.make_special_material(index)
		if not _color_materials[index]:
			skipped_special[index] = skipped_special.get(index, 0) + 1
		return _color_materials[index]


## Converts MDK coordinates (Z up) to Godot coordinates (Y up).
static func to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## The corners of every triangle of an arena (Godot coordinates), three per triangle. The original
## draws without a depth buffer, back to front, so details lying on a wall in its plane (windows,
## posters) simply cover it; with a depth buffer they'd flicker. So a triangle is lifted off its
## plane, towards its front, by `LAYER_LIFT` per depth layer (`arena_layers`).
##
##   wall ──────────────  layer 0
##   poster   ────        layer 1 (+0.03 towards the viewer, also when only partly on the wall)
##   sticker   ──         layer 2
static func arena_positions(arena: MDKArena) -> PackedVector3Array:
	var key := arena.get_instance_id()
	if _positions_cache.has(key):
		return _positions_cache[key]
	var positions := PackedVector3Array()
	positions.resize(arena.triangle_indices.size())
	for i in positions.size():
		positions[i] = to_godot(arena.vertices[arena.triangle_indices[i]])
	_lift_layers(arena, positions)
	_positions_cache[key] = positions
	return positions


## Lifts each triangle by its layer (see `arena_positions`).
static func _lift_layers(arena: MDKArena, positions: PackedVector3Array) -> void:
	var layers := arena_layers(arena)
	for t in layers.size():
		if layers[t] == 0:
			continue
		var normal := (positions[t * 3 + 2] - positions[t * 3]).cross(positions[t * 3 + 1] - positions[t * 3]).normalized()
		for k in 3:
			positions[t * 3 + k] += normal * LAYER_LIFT * layers[t]


## The depth layer of each arena triangle: one above the highest bigger triangle of its plane it
## overlaps (by area; of equal ones, the later in the data goes on top), at most `LAYER_HIGHEST`.
static func arena_layers(arena: MDKArena) -> PackedInt32Array:
	var count := arena.triangle_indices.size() / 3
	var layers := PackedInt32Array()
	layers.resize(count)
	layers.fill(0)
	var areas := PackedFloat32Array()
	areas.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var boxes: Array[AABB] = []
	boxes.resize(count)
	var planes := {}
	for t in count:
		var a := _corner(arena, t, 0)
		var cross := (_corner(arena, t, 2) - a).cross(_corner(arena, t, 1) - a)
		areas[t] = cross.length()
		if areas[t] == 0.0:
			continue
		normals[t] = cross / areas[t]
		boxes[t] = AABB(a, Vector3.ZERO).expand(_corner(arena, t, 1)).expand(_corner(arena, t, 2))
		var key := Vector4(roundf(normals[t].x * PLANE_STEPS), roundf(normals[t].y * PLANE_STEPS),
				roundf(normals[t].z * PLANE_STEPS), roundf(normals[t].dot(a) * PLANE_STEPS))
		if not planes.has(key):
			planes[key] = []
		planes[key].push_back(t)

	# Biggest first: each triangle goes one layer above the highest bigger one it overlaps.
	var bigger_first := func(x: int, y: int) -> bool: return areas[x] > areas[y] or (areas[x] == areas[y] and x < y)
	for plane: Array in planes.values():
		plane.sort_custom(bigger_first)
		for i in range(1, plane.size()):
			var t: int = plane[i]
			for j in i:
				var under: int = plane[j]
				if layers[under] < layers[t] or not boxes[under].grow(MIN_OVERLAP).intersects(boxes[t]):
					continue
				if _overlap(arena, t, under, normals[t]) > MIN_OVERLAP:
					layers[t] = mini(layers[under] + 1, LAYER_HIGHEST)
	return layers


static func _corner(arena: MDKArena, t: int, k: int) -> Vector3:
	return arena.vertices[arena.triangle_indices[t * 3 + k]]


## The area two triangles of a plane share: one clipped by the other's edges (Sutherland-Hodgman),
## in the plane's 2D coordinates around the first corner.
static func _overlap(arena: MDKArena, t: int, other: int, normal: Vector3) -> float:
	var origin := _corner(arena, t, 0)
	var u := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := normal.cross(u)
	var flat := func(p: Vector3) -> Vector2: return Vector2((p - origin).dot(u), (p - origin).dot(v))
	var polygon := PackedVector2Array([flat.call(origin), flat.call(_corner(arena, t, 1)), flat.call(_corner(arena, t, 2))])
	var clip := PackedVector2Array([flat.call(_corner(arena, other, 0)), flat.call(_corner(arena, other, 1)), flat.call(_corner(arena, other, 2))])
	var winding := signf((clip[1] - clip[0]).cross(clip[2] - clip[0]))
	for e in 3:
		if polygon.is_empty():
			break
		polygon = _clip_by(polygon, clip[e], clip[(e + 1) % 3], winding)

	var twice := 0.0
	for k in polygon.size():
		twice += polygon[k].cross(polygon[(k + 1) % polygon.size()])
	return absf(twice) / 2.0


## The part of a polygon on the inner side of the edge from `a` to `b`.
static func _clip_by(polygon: PackedVector2Array, a: Vector2, b: Vector2, winding: float) -> PackedVector2Array:
	var kept := PackedVector2Array()
	for k in polygon.size():
		var p := polygon[k]
		var q := polygon[(k + 1) % polygon.size()]
		var sp := winding * (b - a).cross(p - a)
		var sq := winding * (b - a).cross(q - a)
		if sp >= 0.0:
			kept.push_back(p)
		if (sp >= 0.0) != (sq >= 0.0):
			kept.push_back(p + (q - p) * (sp / (sp - sq)))
	return kept


## Builds the world mesh of an arena (or of some of its triangles), with one surface per material.
## `material_override` replaces the material value of every triangle (`group_set_texture`).
static func build_arena_mesh(arena: MDKArena, resolver: MaterialResolver, triangles := PackedInt32Array(), material_override: Variant = null) -> ArrayMesh:
	if triangles.is_empty():
		triangles = PackedInt32Array(range(arena.triangle_materials.size()))
	var by_material := {}
	for tri in triangles:
		var value: int = arena.triangle_materials[tri] if material_override == null else material_override
		var material := resolver.get_material(value, arena.materials)
		if not material:
			continue
		if not by_material.has(material):
			by_material[material] = PackedInt32Array()
		by_material[material].push_back(tri)

	var all_positions := arena_positions(arena)
	var mesh := ArrayMesh.new()
	for material: Material in by_material:
		var uv_scale: Vector2 = material.get_meta(&"uv_scale", Vector2.ZERO)
		var surface_triangles: PackedInt32Array = by_material[material]
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		positions.resize(surface_triangles.size() * 3)
		uvs.resize(surface_triangles.size() * 3)
		var i := 0
		for tri in surface_triangles:
			for k in 3:
				positions[i] = all_positions[tri * 3 + k]
				uvs[i] = arena.triangle_uvs[tri * 3 + k] * uv_scale
				i += 1

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = flat_normals(positions)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		_add_outlines(mesh, arena, surface_triangles, material, resolver.look)
	return mesh


## The outlined edges of untextured triangles (glass panes get coloured frames), as lines in the
## triangles' material.
## The enhanced look skips flagged edges two coplanar triangles share: the editor flagged some
## diagonals inside glass panes (LEVEL7's DANT_7 columns); the original draws them (0x40b7f0).
static func _add_outlines(mesh: ArrayMesh, arena: MDKArena, triangles: PackedInt32Array, material: Material, look: Look) -> void:
	if material.has_meta(&"uv_scale"):
		return
	var inner := _inner_edges(arena, triangles) if look == Look.ENHANCED else {}
	var lines := PackedVector3Array()
	for tri in triangles:
		var flags := arena.triangle_flags[tri]
		if not flags & OUTLINE:
			continue
		for edge: Array in OUTLINE_EDGES:
			var a := arena.triangle_indices[tri * 3 + edge[1]]
			var b := arena.triangle_indices[tri * 3 + edge[2]]
			if not flags & edge[0] or inner.has(Vector2i(mini(a, b), maxi(a, b))):
				continue
			lines.push_back(to_godot(arena.vertices[a]))
			lines.push_back(to_godot(arena.vertices[b]))
	if lines.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## The edges (vertex index pairs, lower first) two coplanar triangles share.
##
##   v2 ┌──┐ v3     v1-v2 is inner: both halves lie in one plane
##      │╲ │
##   v0 └──┘ v1
static func _inner_edges(arena: MDKArena, triangles: PackedInt32Array) -> Dictionary:
	var normals := {}
	var inner := {}
	for tri in triangles:
		var v0 := arena.vertices[arena.triangle_indices[tri * 3]]
		var normal := (arena.vertices[arena.triangle_indices[tri * 3 + 1]] - v0).cross(
				arena.vertices[arena.triangle_indices[tri * 3 + 2]] - v0).normalized()
		for edge: Array in OUTLINE_EDGES:
			var a := arena.triangle_indices[tri * 3 + edge[1]]
			var b := arena.triangle_indices[tri * 3 + edge[2]]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not normals.has(key):
				normals[key] = normal
				continue
			if absf((normals[key] as Vector3).dot(normal)) > COPLANAR_COS:
				inner[key] = true
	return inner


## Builds the mesh of a model in a given pose (the vertices of each part, see `MDKModel.get_rest_pose()`
## and `MDKModelAnimation.bake()`), with one surface per material.
static func build_model_mesh(model: MDKModel, pose: Array, resolver: MaterialResolver) -> ArrayMesh:
	var by_material := {}
	for p in model.parts.size():
		var part := model.parts[p]
		# Hidden parts have no vertices in the pose.
		if (pose[p] as PackedVector3Array).is_empty():
			continue
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
		arrays[Mesh.ARRAY_NORMAL] = flat_normals(positions)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Builds the collision shape of an arena (every triangle, including invisible ones).
static func build_arena_collision(arena: MDKArena, triangles := PackedInt32Array(), sides := Sides.BOTH) -> ConcavePolygonShape3D:
	if triangles.is_empty():
		triangles = PackedInt32Array(range(arena.triangle_materials.size()))
	var faces := PackedVector3Array()
	faces.resize(triangles.size() * 3)
	for t in triangles.size():
		for k in 3:
			faces[t * 3 + k] = to_godot(arena.vertices[arena.triangle_indices[triangles[t] * 3 + k]])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = sides == Sides.BOTH
	shape.set_faces(faces)
	return shape


## A triangle's normal for each of its corners (the original has none: only the enhanced look is
## lit). Godot's front faces wind clockwise.
static func flat_normals(positions: PackedVector3Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for i in range(0, positions.size() - 2, 3):
		var normal := (positions[i + 2] - positions[i]).cross(positions[i + 1] - positions[i]).normalized()
		normals[i] = normal
		normals[i + 1] = normal
		normals[i + 2] = normal
	return normals


static func make_palette_material(texture: MDKTexture, palette: MDKPalette, double_sided := false, look := Look.ORIGINAL) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if look == Look.ENHANCED:
		material.shader = PALETTE_LIT_DOUBLE_SIDED_SHADER if double_sided else PALETTE_LIT_SHADER
	else:
		material.shader = PALETTE_DOUBLE_SIDED_SHADER if double_sided else PALETTE_SHADER
	material.set_shader_parameter(&"index_texture", texture.get_index_texture())
	material.set_shader_parameter(&"palette", palette.get_texture())
	material.set_shader_parameter(&"frame_count", texture.frame_count)
	# UVs are in texels of one frame.
	material.set_meta(&"uv_scale", Vector2(1.0 / texture.width, 1.0 / texture.height))
	return material


## Placeholder materials for special surfaces where the level's (`MDKSpecialMaterials`) aren't
## known (the fall, the stream, the statistics, the model viewer).
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


static func make_color_material(color: Color, double_sided := false, look := Look.ORIGINAL) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if look == Look.ENHANCED else BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	material.albedo_color = color
	return material

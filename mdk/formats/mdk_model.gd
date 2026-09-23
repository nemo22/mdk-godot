## A model (object, alien, weapon…) from an arena's models section or the level's CMI file.
## See `docs/formats.md` ("Model").
class_name MDKModel
extends RefCounted


class Part:
	var name := ""
	## Unused by the game.
	var pivot := Vector3()
	## Model space (MDK coordinates).
	var vertices := PackedVector3Array()
	## Same layout as `MDKArena`: 3 vertex indices per triangle, material values, 3 UVs (texels).
	var triangle_indices := PackedInt32Array()
	var triangle_materials := PackedInt32Array()
	var triangle_uvs := PackedVector2Array()
	## Bounding box of the rest pose (model space).
	var bounds := AABB()


var name := ""
## Material names (texture names, or `PEN_n`).
var materials: Array[String] = []
var parts: Array[Part] = []
var reference_points := PackedVector3Array()
## Bounding box of the rest pose (model space).
var bounds := AABB()


## `has_flags` false: the model has no leading flags word and a single unnamed part (`XGHEAD` of
## `STATS.BNI`, the fall's models).
static func parse(p_name: String, bytes: PackedByteArray, offset: int, has_flags := true) -> MDKModel:
	var model := MDKModel.new()
	model.name = p_name
	var r := BinReader.new(bytes, offset)
	var named_parts := r.u32() != 0 if has_flags else false
	var material_count := r.u32()
	for i in material_count:
		# The game keeps the first 10 characters.
		model.materials.push_back(r.name(16).left(10))
	var part_count := r.u32() if named_parts else 1
	for i in part_count:
		var part := Part.new()
		if named_parts:
			part.name = r.name(12)
			part.pivot = r.vec3()
		var vertex_count := r.u32()
		part.vertices.resize(vertex_count)
		for v in vertex_count:
			part.vertices[v] = r.vec3()
		var triangle_count := r.u32()
		part.triangle_indices.resize(triangle_count * 3)
		part.triangle_materials.resize(triangle_count)
		part.triangle_uvs.resize(triangle_count * 3)
		for t in triangle_count:
			part.triangle_indices[t * 3] = r.s16()
			part.triangle_indices[t * 3 + 1] = r.s16()
			part.triangle_indices[t * 3 + 2] = r.s16()
			part.triangle_materials[t] = r.s16()
			for k in 3:
				var u := r.f32()
				part.triangle_uvs[t * 3 + k] = Vector2(u, r.f32())
			r.skip(4)
		if named_parts:
			part.bounds = _read_bounds(r)
		model.parts.push_back(part)
	model.bounds = _read_bounds(r)
	var reference_count := r.u32()
	for i in reference_count:
		model.reference_points.push_back(r.vec3())
	return model


## Bounds are stored as `min x, max x, min y, max y, min z, max z`.
static func _read_bounds(r: BinReader) -> AABB:
	var x := Vector2(r.f32(), r.f32())
	var y := Vector2(r.f32(), r.f32())
	var z := Vector2(r.f32(), r.f32())
	return AABB(Vector3(x.x, y.x, z.x), Vector3(x.y - x.x, y.y - y.x, z.y - z.x))


## Returns a copy of every part's vertices (an animation pose), in part order.
func get_rest_pose() -> Array[PackedVector3Array]:
	var pose: Array[PackedVector3Array] = []
	for part in parts:
		pose.push_back(part.vertices.duplicate())
	return pose

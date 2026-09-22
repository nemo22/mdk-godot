## One arena of a level (`HMO_n` in `LEVELnO.MTO`): textures, palette colors and world geometry.
## See `docs/formats.md` for the layout.
class_name MDKArena
extends RefCounted

var name := ""

## The arena's 112 palette colors (RGB), placed at palette indices 64–175.
var palette_rgb := PackedByteArray()

## The arena's `HMO_n.MAT` texture archive.
var textures: MDKTextureArchive

## Models, animations and sounds of the arena's models section (name to MDKModel,
## MDKModelAnimation and RIFF WAV bytes).
var models := {}
var animations := {}
var sounds := {}

## World material names (textures, or `PEN_n` for flat palette colors).
var materials: Array[String] = []

## World vertices, in MDK coordinates (Z up).
var vertices := PackedVector3Array()

## World triangles: 3 vertex indices per triangle.
var triangle_indices := PackedInt32Array()
## Per triangle: index into `materials`, or `-n` for palette color `n` (`n` ≥ 256 is special ❓).
var triangle_materials := PackedInt32Array()
## 3 UVs per triangle, in texels.
var triangle_uvs := PackedVector2Array()
## Per triangle flags (bits 20–22 look like a light level ❓).
var triangle_flags := PackedInt32Array()

var bsp_node_count := 0


## Parses an arena from the MTO file. `offset` points to the arena's size field.
static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKArena:
	var arena := MDKArena.new()
	arena.name = p_name
	# The game loads `size` bytes after the size field; offsets are relative to that buffer.
	var buf := offset + 4
	var section_models := buf + bytes.decode_u32(buf)
	var section_palette := buf + bytes.decode_u32(buf + 4)
	var section_world := buf + bytes.decode_u32(buf + 8)
	arena.palette_rgb = bytes.slice(section_palette, section_palette + 112 * 3)
	arena.textures = MDKTextureArchive.parse(bytes, buf + 0x10)
	arena._parse_world(bytes, section_world)
	arena._parse_models(bytes, section_models + 4)
	return arena


## Parses a world section on its own (corridors in `LEVELnO.SNI` have no textures, palette or models).
static func parse_world(p_name: String, bytes: PackedByteArray, offset: int) -> MDKArena:
	var arena := MDKArena.new()
	arena.name = p_name
	arena.textures = MDKTextureArchive.new()
	arena._parse_world(bytes, offset)
	return arena


## Parses the models section. `base` is right after its size.
func _parse_models(bytes: PackedByteArray, base: int) -> void:
	var r := BinReader.new(bytes, base)
	var animation_count := r.u32()
	var model_count := r.u32()
	var sound_count := r.u32()
	for i in animation_count:
		var animation_name := r.name(8)
		animations[animation_name] = MDKModelAnimation.parse(animation_name, bytes, base + r.u32())
	for i in model_count:
		var model_name := r.name(8)
		models[model_name] = MDKModel.parse(model_name, bytes, base + r.u32())
	for i in sound_count:
		var sound_name := r.name(12)
		r.skip(4)
		var offset := base + r.u32()
		sounds[sound_name] = bytes.slice(offset, offset + r.u32())


func _parse_world(bytes: PackedByteArray, base: int) -> void:
	var r := BinReader.new(bytes, base)
	var material_count := r.u32()
	for i in material_count:
		materials.push_back(r.name(10))
	if material_count % 2 == 1:
		r.skip(2)

	bsp_node_count = r.u32()
	r.skip(bsp_node_count * 44)

	var triangle_count := r.u32()
	triangle_indices.resize(triangle_count * 3)
	triangle_materials.resize(triangle_count)
	triangle_uvs.resize(triangle_count * 3)
	triangle_flags.resize(triangle_count)
	for i in triangle_count:
		triangle_indices[i * 3] = r.s16()
		triangle_indices[i * 3 + 1] = r.s16()
		triangle_indices[i * 3 + 2] = r.s16()
		triangle_materials[i] = r.s16()
		for k in 3:
			var u := r.f32()
			triangle_uvs[i * 3 + k] = Vector2(u, r.f32())
		triangle_flags[i] = r.u32()

	var vertex_count := r.u32()
	vertices.resize(vertex_count)
	for i in vertex_count:
		vertices[i] = r.vec3()

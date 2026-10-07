## Triangle groups shattered into flying pieces (`shatter_group*`, opcodes 137–139, 0x40c828; once named `light_group*`).
##
## Each triangle of the group is split in two at the middle of its longest side until it's no
## larger than `size / 4` (0x40cbe0, 0x40d014); every piece becomes a double-sided effect
## (0x40564c) that flies away from the point (or along the direction), spins, falls, bounces off the
## arena and vanishes after its lifetime (0x4061d8).
##
## The same movement carries sparks (0x4052d4: small tetrahedra in one palette colour, brighter
## when facing the camera) and the pieces an object breaks into when it explodes (0x405900: the
## parts of its `<model>D` break-up model). Some of them leave a smoke trail (0x406004).
class_name MDKDebris
extends Node3D

## Gravity of the pieces in units per tick² (about 64 units/s²).
const GRAVITY := 0.284444 * 0.25
## Speed kept along the surface normal when bouncing (restitution 0.4: `v -= 1.4 (v·n) n`).
const BOUNCE := 1.4
## Life lost at each bounce, in ticks.
const BOUNCE_TICKS := 20
## A hit this close to the start is the surface the piece rests on.
const ON_SURFACE := 1e-3
## Most pieces alive at once (the original shares a pool of effects).
const MAX_PIECES := 600
## A spark's tetrahedron (0x404b00), jittered by ±0.33 and scaled by its size.
const SPARK_CORNERS := [Vector3(0, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)]
const SPARK_FACES := [0, 2, 1, 0, 3, 2, 0, 1, 3, 1, 2, 3]
## Sparks and pieces live 60–123 ticks; one in 4 leaves a smoke trail every 1–2 ticks.
const LIFE_MIN := 60
const RAND_HALF := 0x4000
## Pieces start 2 units above the object.
const BREAK_UP_RISE := 2.0
const TICKS := 30.0

## How a spark starts: flying off at random, or still at its point (the fans' sparks).
enum Launch { RANDOM, STILL }


class Piece:
	## A material per triangle, or none for a spark (drawn in palette colours `base … base + range`).
	var materials: Array[Material] = []
	var colour_base := 0
	var colour_range := 0
	## Corners relative to the centre (MDK space, 3 per triangle), and their UVs.
	var corners := PackedVector3Array()
	var uvs := PackedVector2Array()
	var arena := ""
	## A smoke trail every this many ticks (0: none).
	var trail_every := 0
	var trail_ticks := 0
	var center := Vector3()
	## Units per tick.
	var velocity := Vector3()
	var orientation := Basis()
	## Turn per tick.
	var spin := Basis()
	var ticks := 0


var level: Level
var _spark_material := StandardMaterial3D.new()
## Leaves a smoke puff: `(arena name, point)` (see `MDKEffects.spawn_trail()`).
var trail: Callable
## The fans' push: `(arena name, point, vertical speed in u/s, seconds)` → the new speed, or NAN
## outside every fan (`MDKFans.query` with mask 8).
var updraft: Callable
var _pieces: Array[Piece] = []
var _mesh := MeshInstance3D.new()


func _ready() -> void:
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.vertex_color_use_as_albedo = true
	_spark_material.vertex_color_is_srgb = true
	_mesh.mesh = ArrayMesh.new()
	add_child(_mesh)


## Shatters a triangle group: `life` in seconds, pieces no larger than `size / 4`, speed `speed`
## (units per tick) at `point`, falling off to 0 at the group's farthest corner; the pieces fly along
## `direction`, or away from `point` when it's zero.
func shatter(arena_name: String, group: int, life: float, size: float, speed: float, point: Vector3, direction: Vector3) -> void:
	var triangles := level.get_group_triangles(arena_name, group)
	if triangles.is_empty():
		return
	var bounds := AABB(triangles[0][0][0], Vector3.ZERO)
	for triangle: Array in triangles:
		for corner: Vector3 in triangle[0]:
			bounds = bounds.expand(corner)
	# The squared distance to the farthest corner of the box, axis by axis.
	var far := Vector3(maxf(absf(bounds.position.x - point.x), absf(bounds.end.x - point.x)),
			maxf(absf(bounds.position.y - point.y), absf(bounds.end.y - point.y)),
			maxf(absf(bounds.position.z - point.z), absf(bounds.end.z - point.z))).length_squared()
	var max_cross := size * size * 0.25
	var radial := direction == Vector3.ZERO
	if not radial:
		direction = direction.normalized()
	for triangle: Array in triangles:
		_split(triangle[0], triangle[1], triangle[2], max_cross, life, speed, point, direction, radial, far)


func _split(corners: PackedVector3Array, uvs: PackedVector2Array, material: Material, max_cross: float,
		life: float, speed: float, point: Vector3, direction: Vector3, radial: bool, far: float) -> void:
	if _pieces.size() >= MAX_PIECES:
		return
	if (corners[1] - corners[0]).cross(corners[1] - corners[2]).length_squared() > max_cross:
		var longest := 0
		for k in 3:
			if corners[(k + 1) % 3].distance_squared_to(corners[k]) > corners[(longest + 1) % 3].distance_squared_to(corners[longest]):
				longest = k
		var a := longest
		var b := (longest + 1) % 3
		var c := (longest + 2) % 3
		var middle := (corners[a] + corners[b]) * 0.5
		var middle_uv := (uvs[a] + uvs[b]) * 0.5
		_split(PackedVector3Array([corners[a], middle, corners[c]]), PackedVector2Array([uvs[a], middle_uv, uvs[c]]),
				material, max_cross, life, speed, point, direction, radial, far)
		_split(PackedVector3Array([middle, corners[b], corners[c]]), PackedVector2Array([middle_uv, uvs[b], uvs[c]]),
				material, max_cross, life, speed, point, direction, radial, far)
		return
	var piece := Piece.new()
	piece.materials = [material]
	piece.center = (corners[0] + corners[1] + corners[2]) / 3.0
	for corner in corners:
		piece.corners.push_back(corner - piece.center)
	piece.uvs = uvs
	var f := 1.0 - piece.center.distance_squared_to(point) / far if far > 0.0 else 1.0
	if not radial:
		piece.velocity = direction * speed * f
	elif piece.center == point:
		piece.velocity = Vector3(0.0, 0.0, speed * f)
	else:
		piece.velocity = (piece.center - point).normalized() * speed * f
	# Up to about ±14° per tick about each axis (0x46de70).
	var angles := Vector3(randi() % 32768 - 0x41c2, randi() % 32768 - 0x41c2, randi() % 32768 - 0x41c2) * 0.000854492 * f
	piece.spin = Basis.from_euler(angles * PI / 180.0)
	piece.ticks = roundi(life * 30.0)
	_pieces.push_back(piece)


## Sparks (0x41e8f4, 0x4052d4) at `point`: `size` 0.5 or 1.0, palette colours `base` to
## `base + range` (e.g. 3, 3: green), velocity scaled by `speed`.
func spark(arena_name: String, point: Vector3, count: int, size: float, base: int, range: int, speed := 1.0, launch := Launch.RANDOM) -> void:
	for i in count:
		if _pieces.size() >= MAX_PIECES:
			return
		var piece := Piece.new()
		var s := (1.0 + _rand_half() / 32768.0) * size
		var corners: Array[Vector3] = []
		for corner: Vector3 in SPARK_CORNERS:
			corners.push_back((corner + Vector3(_rand_half(), _rand_half(), _rand_half()) * 2e-5) * s)
		for k: int in SPARK_FACES:
			piece.corners.push_back(corners[k])
		piece.colour_base = base
		piece.colour_range = range
		piece.center = point + Vector3(_rand_half() / 16384.0, _rand_half() / 16384.0, _rand_half() / 32768.0)
		_launch(piece, arena_name, speed)
		# The fans' sparks stand exactly at their point (0x414230 sets it after 0x4052d4).
		if launch == Launch.STILL:
			piece.velocity = Vector3.ZERO
			piece.center = point
		# Only the bigger sparks can trail.
		if s < 1.0:
			piece.trail_every = 0
		_pieces.push_back(piece)


## An object's break-up (0x405900): one piece per part of its break-up model, placed like the
## object (yaw and bank) 2 units higher, thrown with its velocity plus a spark's; parts hidden on
## the object stay behind.
func break_up(obj: MDKObject, model: MDKModel, resolver: MDKMeshBuilder.MaterialResolver) -> void:
	var basis := Basis(Vector3.BACK, deg_to_rad(obj.yaw)) * Basis(Vector3.RIGHT, deg_to_rad(obj.roll))
	var velocity := obj.mdk_position - obj.previous_position
	for part in model.parts:
		if _pieces.size() >= MAX_PIECES:
			return
		var index := obj.find_part(part.name)
		if index >= 0 and obj.hidden_parts & (1 << index):
			continue
		var piece := Piece.new()
		for t in part.triangle_materials.size():
			var material := resolver.get_material(part.triangle_materials[t], model.materials)
			# UVs are in texels of the texture.
			var uv_scale: Vector2 = material.get_meta(&"uv_scale", Vector2.ZERO) if material else Vector2.ZERO
			piece.materials.push_back(material)
			for k in 3:
				piece.corners.push_back(basis * part.vertices[part.triangle_indices[t * 3 + k]])
				piece.uvs.push_back(part.triangle_uvs[t * 3 + k] * uv_scale)
		piece.center = obj.mdk_position + Vector3(0, 0, BREAK_UP_RISE)
		_launch(piece, obj.arena, 1.0)
		piece.velocity += velocity
		_pieces.push_back(piece)


## A spark's start (0x4052d4): thrown mostly upwards (±1, ±1, −0.125…1.875 units per tick), a
## random spin of about ±14° per tick, 60–123 ticks of life, one in 4 trailing smoke.
func _launch(piece: Piece, arena_name: String, speed: float) -> void:
	piece.arena = arena_name
	piece.velocity = Vector3(_rand_half() / 16384.0, _rand_half() / 16384.0, (randi() % 32768 - 0x800) / 16384.0) * speed
	var angles := Vector3(randi() % 32768 - 0x41c2, randi() % 32768 - 0x41c2, randi() % 32768 - 0x41c2) * 28.0 / 32768.0
	piece.spin = Basis.from_euler(angles * PI / 180.0)
	piece.ticks = ((randi() % 32768) >> 9) + LIFE_MIN
	if randi() & 3 == 0:
		piece.trail_every = (randi() & 1) + 1


func _rand_half() -> int:
	return randi() % 32768 - RAND_HALF


## Whether an arena has any piece or spark.
func has_pieces(arena_name: String) -> bool:
	return _pieces.any(func(piece: Piece) -> bool: return piece.arena == arena_name)


func piece_count() -> int:
	return _pieces.size()


## Moves the pieces by a tick (0x4061d8) and rebuilds the mesh.
func update(ticks: float) -> void:
	if _pieces.is_empty():
		if _mesh.mesh.get_surface_count() > 0:
			_mesh.mesh.clear_surfaces()
		return
	var space := get_world_3d().direct_space_state
	for i in range(_pieces.size() - 1, -1, -1):
		var piece := _pieces[i]
		piece.orientation = piece.orientation * piece.spin
		var motion := piece.velocity * ticks
		var query := PhysicsRayQueryParameters3D.create(MDKMeshBuilder.to_godot(piece.center),
				MDKMeshBuilder.to_godot(piece.center + motion), MDKScriptRuntime.LEVEL_LAYER)
		var hit := space.intersect_ray(query) if motion != Vector3.ZERO else {}
		# A segment starting on a plane crosses nothing (0x421470): a piece resting on the fan's
		# grate goes on through it.
		if not hit.is_empty() and MDKScriptRuntime.to_mdk(hit.position).distance_to(piece.center) <= ON_SURFACE:
			hit = {}
		if hit.is_empty():
			piece.center += motion
			piece.velocity.z -= GRAVITY * ticks
		else:
			piece.center = MDKScriptRuntime.to_mdk(hit.position)
			var normal := MDKScriptRuntime.to_mdk(hit.normal)
			piece.velocity -= normal * piece.velocity.dot(normal) * BOUNCE
			piece.ticks -= BOUNCE_TICKS

		# Fans push sparks and pieces (mask 8), after a bounce too: their speed is in units per tick.
		if updraft.is_valid():
			var vz: float = updraft.call(piece.arena, piece.center, piece.velocity.z * TICKS, ticks / TICKS)
			if not is_nan(vz):
				piece.velocity.z = vz / TICKS
		piece.ticks -= roundi(ticks)
		if piece.ticks <= 0:
			_pieces.remove_at(i)
			continue

		# The smoke trail (0x406070).
		if piece.trail_every > 0 and trail.is_valid():
			piece.trail_ticks += roundi(ticks)
			if piece.trail_ticks >= piece.trail_every:
				piece.trail_ticks = 0
				trail.call(piece.arena, piece.center)
	_build_mesh()


func _build_mesh() -> void:
	var mesh: ArrayMesh = _mesh.mesh
	mesh.clear_surfaces()

	# Textured triangles by material, both windings (the pieces are double-sided).
	var positions_by := {}
	var uvs_by := {}
	var sparks: Array[Piece] = []
	for piece in _pieces:
		if piece.materials.is_empty():
			sparks.push_back(piece)
			continue
		for t in piece.materials.size():
			var material := piece.materials[t]
			if not material:
				continue
			if not positions_by.has(material):
				positions_by[material] = PackedVector3Array()
				uvs_by[material] = PackedVector2Array()
			for k: int in [0, 1, 2, 0, 2, 1]:
				positions_by[material].push_back(MDKMeshBuilder.to_godot(piece.center + piece.orientation * piece.corners[t * 3 + k]))
				uvs_by[material].push_back(piece.uvs[t * 3 + k])
	for material: Material in positions_by:
		var positions: PackedVector3Array = positions_by[material]
		var uvs: PackedVector2Array = uvs_by[material]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	_build_sparks(mesh, sparks)


## Sparks (0x406e24): flat triangles, palette colour `base + range × |facing|` where `facing` is how
## much the face turns to the camera (face-on: `base + range`, edge-on: `base`).
func _build_sparks(mesh: ArrayMesh, sparks: Array[Piece]) -> void:
	var camera := get_viewport().get_camera_3d()
	if sparks.is_empty() or not camera or not level:
		return
	var view := MDKScriptRuntime.to_mdk(-camera.global_basis.z)
	var palette := level.get_palette()
	var positions := PackedVector3Array()
	var colours := PackedColorArray()
	for piece in sparks:
		for t in piece.corners.size() / 3:
			var a := piece.orientation * piece.corners[t * 3]
			var b := piece.orientation * piece.corners[t * 3 + 1]
			var c := piece.orientation * piece.corners[t * 3 + 2]
			var facing := absf((b - a).cross(c - a).normalized().dot(view))
			var colour := palette.get_color(clampi(roundi(piece.colour_base + piece.colour_range * facing), 0, 255))
			for corner: Vector3 in [a, b, c, a, c, b]:
				positions.push_back(MDKMeshBuilder.to_godot(piece.center + corner))
				colours.push_back(colour)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colours
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _spark_material)

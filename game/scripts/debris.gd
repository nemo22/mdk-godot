## Triangle groups shattered into flying pieces (`shatter_group*`, opcodes 137–139, 0x40c828; once named `light_group*`).
##
## Each triangle of the group is split in two at the middle of its longest side until it's no
## larger than `size / 4` (0x40cbe0, 0x40d014); every piece becomes a double-sided effect
## (0x40564c) that flies away from the point (or along the direction), spins, falls, bounces off the
## arena and vanishes after its lifetime (0x4061d8).
class_name MDKDebris
extends Node3D

## Gravity of the pieces in units per tick² (about 64 units/s²).
const GRAVITY := 0.284444 * 0.25
## Speed kept along the surface normal when bouncing (restitution 0.4: `v -= 1.4 (v·n) n`).
const BOUNCE := 1.4
## Life lost at each bounce, in ticks.
const BOUNCE_TICKS := 20
## Most pieces alive at once (the original shares a pool of effects).
const MAX_PIECES := 600


class Piece:
	var material: Material
	## Corners relative to the centre (MDK space), and their UVs.
	var corners := PackedVector3Array()
	var uvs := PackedVector2Array()
	var center := Vector3()
	## Units per tick.
	var velocity := Vector3()
	var orientation := Basis()
	## Turn per tick.
	var spin := Basis()
	var ticks := 0


var level: Level
var _pieces: Array[Piece] = []
var _mesh := MeshInstance3D.new()


func _ready() -> void:
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
	piece.material = material
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
		if hit.is_empty():
			piece.center += motion
			piece.velocity.z -= GRAVITY * ticks
		else:
			piece.center = MDKScriptRuntime.to_mdk(hit.position)
			var normal := MDKScriptRuntime.to_mdk(hit.normal)
			piece.velocity -= normal * piece.velocity.dot(normal) * BOUNCE
			piece.ticks -= BOUNCE_TICKS
		piece.ticks -= roundi(ticks)
		if piece.ticks <= 0:
			_pieces.remove_at(i)
	_build_mesh()


func _build_mesh() -> void:
	var mesh: ArrayMesh = _mesh.mesh
	mesh.clear_surfaces()
	var by_material := {}
	for piece in _pieces:
		if not by_material.has(piece.material):
			by_material[piece.material] = []
		by_material[piece.material].push_back(piece)
	for material: Material in by_material:
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		for piece: Piece in by_material[material]:
			var corners: Array[Vector3] = []
			for corner in piece.corners:
				corners.push_back(MDKMeshBuilder.to_godot(piece.center + piece.orientation * corner))
			# Both windings: the pieces are double-sided.
			for k: int in [0, 1, 2, 0, 2, 1]:
				positions.push_back(corners[k])
				uvs.push_back(piece.uvs[k])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)

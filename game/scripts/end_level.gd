## The end of a level (`endlev.c`: 0x40a9e0, 0x40ad9c each frame, pieces 0x40b280, Kurt 0x40b558).
## See docs/gameplay.md ("Level flow").
##
## The visible triangles of Kurt's arena are taken from the highest down: each tick 0–7 more are
## torn off and fly up (`vz += 0.025` per tick) spinning around Kurt (the spin grows by 0.15° per
## tick up to 2.5°), until they're 500 above him. Kurt takes off (`K_TAKEOF`, then `K_FLOATC`) and
## rises with them; once he rises faster than 3 units per tick his rise doubles, the view tilts up
## and the screen goes white (8 per tick); past 300 the level is over.
class_name MDKEndLevel
extends Node3D

const RISE := 0.025
const SPIN_GROWTH := 0.15
const SPIN_MAX := 2.5
const LIMIT := 500.0
const PIECES_PER_TICK := 8
const FAST_RISE := 3.0
const FLASH_STEP := 8.0
const FLASH_END := 300.0
## The arena meshes are rebuilt without the torn-off triangles this often (ticks).
const REBUILD_TICKS := 4

signal finished


class Piece:
	var material: Material
	var corners := PackedVector3Array()
	var uvs := PackedVector2Array()
	var center := Vector3()
	var vz := 0.0
	var spin := 0.0
	var angle := 0.0


var runtime: MDKScriptRuntime
var _arena := ""
var _queue: Array = []
var _pieces: Array[Piece] = []
var _mesh := MeshInstance3D.new()
var _kurt_vz := 0.0
var _flash := 0.0
var _ticks := 0
var _takeoff := 0.0
var _done := false


func _ready() -> void:
	_mesh.mesh = ArrayMesh.new()
	add_child(_mesh)


## Starts the effect in Kurt's arena.
func start(p_runtime: MDKScriptRuntime) -> void:
	runtime = p_runtime
	_arena = runtime.current_arena
	_queue = runtime.level.get_arena_triangles(_arena)
	# Highest first.
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return _top(a) > _top(b))
	runtime.kurt.frozen = true
	runtime.raise_shake(5.0)


static func _top(triangle: Array) -> float:
	var corners: PackedVector3Array = triangle[1]
	return maxf(corners[0].z, maxf(corners[1].z, corners[2].z))


func update(ticks: float) -> void:
	if _done:
		return
	_ticks += 1
	var kurt := runtime.kurt
	var kurt_position := MDKScriptRuntime.to_mdk(kurt.global_position)
	# Tear off the highest triangles.
	var torn := PackedInt32Array()
	for i in randi() % PIECES_PER_TICK:
		if _queue.is_empty():
			break
		var triangle: Array = _queue.pop_front()
		torn.push_back(triangle[0])
		var piece := Piece.new()
		piece.material = triangle[3]
		var corners: PackedVector3Array = triangle[1]
		piece.center = (corners[0] + corners[1] + corners[2]) / 3.0
		for corner in corners:
			piece.corners.push_back(corner - piece.center)
		piece.uvs = triangle[2]
		_pieces.push_back(piece)
	if not torn.is_empty():
		runtime.level.hide_triangles(_arena, torn, _ticks % REBUILD_TICKS == 0)
	elif _ticks % REBUILD_TICKS == 0:
		runtime.level.hide_triangles(_arena, torn, true)
	# The pieces rise and spin around Kurt.
	var limit := kurt_position.z + LIMIT
	for i in range(_pieces.size() - 1, -1, -1):
		var piece := _pieces[i]
		piece.vz += RISE * ticks
		piece.spin = minf(piece.spin + SPIN_GROWTH * ticks, SPIN_MAX)
		var around := Vector2(piece.center.x - kurt_position.x, piece.center.y - kurt_position.y).rotated(deg_to_rad(piece.spin * ticks))
		piece.center = Vector3(kurt_position.x + around.x, kurt_position.y + around.y, piece.center.z + piece.vz * ticks)
		piece.angle += piece.spin * ticks
		if piece.center.z > limit:
			_pieces.remove_at(i)
	_build_mesh()
	# Kurt takes off and rises.
	_kurt_vz += RISE * ticks * (2.0 if _kurt_vz > FAST_RISE else 1.0)
	kurt.global_position.y += _kurt_vz * ticks
	_takeoff += ticks
	var takeoff := kurt.sprites.get_animation("K_TAKEOF")
	if _takeoff < takeoff.frame_count:
		kurt.sprite.show_frame(takeoff, int(_takeoff))
	else:
		kurt.sprite.show_frame(kurt.sprites.get_animation("K_FLOATC"), int(_takeoff))
	if _kurt_vz > FAST_RISE:
		_flash += FLASH_STEP * ticks
		kurt.white_flash = minf(_flash, 255.0)
		if _flash > FLASH_END:
			_done = true
			finished.emit()


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
			var turn := Basis(Vector3.BACK, deg_to_rad(piece.angle))
			for k: int in [0, 1, 2, 0, 2, 1]:
				positions.push_back(MDKMeshBuilder.to_godot(piece.center + turn * piece.corners[k]))
				uvs.push_back(piece.uvs[k])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)

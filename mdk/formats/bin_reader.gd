## Sequential little-endian reader over a PackedByteArray.
class_name BinReader
extends RefCounted

var bytes: PackedByteArray
var pos := 0


func _init(p_bytes: PackedByteArray, p_pos := 0) -> void:
	bytes = p_bytes
	pos = p_pos


func size() -> int:
	return bytes.size()


func eof() -> bool:
	return pos >= bytes.size()


func seek(p_pos: int) -> void:
	pos = p_pos


func skip(count: int) -> void:
	pos += count


func u8() -> int:
	pos += 1
	return bytes[pos - 1]


func u16() -> int:
	pos += 2
	return bytes.decode_u16(pos - 2)


func s16() -> int:
	pos += 2
	return bytes.decode_s16(pos - 2)


func u32() -> int:
	pos += 4
	return bytes.decode_u32(pos - 4)


func s32() -> int:
	pos += 4
	return bytes.decode_s32(pos - 4)


func f32() -> float:
	pos += 4
	return bytes.decode_float(pos - 4)


func vec3() -> Vector3:
	pos += 12
	return Vector3(bytes.decode_float(pos - 12), bytes.decode_float(pos - 8), bytes.decode_float(pos - 4))


## Reads a fixed-length, NUL-padded ASCII string.
func name(length: int) -> String:
	pos += length
	return bytes.slice(pos - length, pos).get_string_from_ascii()


## Reads a string prefixed by its length as a `u8` (the length includes the terminating NUL).
func pascal_name() -> String:
	var length := u8()
	return name(length)


func buffer(length: int) -> PackedByteArray:
	pos += length
	return bytes.slice(pos - length, pos)

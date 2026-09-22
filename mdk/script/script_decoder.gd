## Decodes MDK script instructions (LEVELn.CMI bytecode). Mirrors `tools/python/mdk_script_dis.py`,
## which is validated against every script of the game. See `docs/scripts.md`.
class_name MDKScriptDecoder
extends RefCounted


## A decoded instruction. Offsets (`code32`/`data32` operands, branch targets) are absolute file
## offsets (0 stays 0).
class Instruction:
	var pc := 0
	var opcode := 0
	var operands := []
	## Offset of the next instruction.
	var next := 0
	## Branch action (`["goto", target]`, `["gosub", target]`, `["gosub_else", then, else]`,
	## `["return"]`), if the instruction has one.
	var action := []


var bytes: PackedByteArray
var _cache := {}
var _p := 0


func _init(p_bytes: PackedByteArray) -> void:
	bytes = p_bytes


## Decodes the instruction at file offset `pc` (cached). Returns `null` for invalid opcodes.
func decode(pc: int) -> Instruction:
	if _cache.has(pc):
		return _cache[pc]
	var ins := Instruction.new()
	ins.pc = pc
	ins.opcode = bytes[pc]
	_p = pc + 1
	if ins.opcode != 0xFF:
		if not MDKScriptOpcodes.OPERANDS.has(ins.opcode):
			_cache[pc] = null
			return null
		for code: String in MDKScriptOpcodes.OPERANDS[ins.opcode]:
			var value: Variant = _read(code, ins)
			ins.operands.push_back(value)
	ins.next = _p
	_cache[pc] = ins
	return ins


func _u8() -> int:
	_p += 1
	return bytes[_p - 1]


func _f32() -> float:
	_p += 4
	return bytes.decode_float(_p - 4)


func _u32() -> int:
	_p += 4
	return bytes.decode_u32(_p - 4)


func _offset() -> int:
	var value := _u32()
	return value + 4 if value != 0 else 0


func _pstr() -> String:
	var length := _u8()
	_p += length
	return bytes.slice(_p - length, _p).get_string_from_ascii()


func _floats(count: int) -> Array:
	var out := []
	for i in count:
		out.push_back(_f32())
	return out


func _action() -> Array:
	var action := _u8()
	match action:
		0xFE:
			var then_target := _offset()
			return ["gosub_else", then_target, _offset()]
		0xFC:
			return ["gosub", _offset()]
		0x0C:
			return ["goto", _offset()]
		0xFD:
			return ["return"]
	return ["none", action]


## Value operand: `[kind, index]` for a variable, or a float literal.
func _value() -> Variant:
	var kind := _u8()
	if kind == 3:
		return _f32()
	return [kind, _u8()]


func _read(code: String, ins: Instruction) -> Variant:
	var prev := ins.operands
	match code:
		"u8":
			return _u8()
		"s8":
			var v := _u8()
			return v - 256 if v >= 128 else v
		"u16":
			_p += 2
			return bytes.decode_u16(_p - 2)
		"s16":
			_p += 2
			return bytes.decode_s16(_p - 2)
		"u32":
			return _u32()
		"s32":
			_p += 4
			return bytes.decode_s32(_p - 4)
		"f32":
			return _f32()
		"pstr":
			return _pstr()
		"code32", "data32":
			return _offset()
		"action":
			ins.action = _action()
			return ins.action
		"value":
			return _value()
		"cond":
			var op := _u8()
			var cond := [op, _f32()]
			if op == 7 or op == 8:
				cond.push_back(_f32())
			return cond
		# Layouts depending on earlier operands (see `complex_operand()` in the Python tool).
		"op4_command_args":
			if prev[0] == 7:
				ins.action = _action()
				return ins.action
			return _floats(2) if prev[0] == 43 else null
		"op4_selector_args":
			var selector: int = prev[2]
			var out := []
			if selector in [6, 10]:
				out.push_back(_f32())
			if selector in [2, 4, 5, 6, 7, 10]:
				out.push_back(_pstr())
			if selector == 5:
				out.push_back(_u32())
			return out
		"op2_origin":
			return _floats(3) if prev[4] == 0 else null
		"op164_params":
			return _floats(4) if prev[0] != 0 else null
		"op42_part":
			var part := _pstr()
			return ["", _pstr()] if part.is_empty() else part
		"op249_sound":
			return _pstr() if prev[0] == 1 else null
		"op250_type_name":
			return _pstr() if prev[0] == 0xFF else null
		"op250_box":
			return _floats(4 if prev[2] == 2 else 6)
		"op174_b", "op175_b":
			return _f32() if prev[1] in [7, 8] else null
		"op129_parts":
			if prev[0] in [0, 1, 2]:
				var names := []
				for i in _u8():
					names.push_back(_pstr())
				return names
			return null
		"op132_position":
			return _floats(3) if prev[1] == 0xFF else null
		"op89_position":
			var flags: int = prev[0]
			if flags & 0x10:
				return _floats(3)
			if flags & 0x20:
				return _u8()
			if flags & 0x40:
				return _floats(3)
			return null
		"op61_origin":
			var mode := _u8()
			return [mode, _u8() if mode == 0 else _pstr()]
		"op83_args":
			if bytes[_p] == 0xFF:
				_p += 1
				return _floats(2)
			return _value()
		"op159_position":
			var mode := _u8()
			return [mode] + (_floats(3) if mode in [1, 2] else [])
		"op189_args":
			var mode := _u8()
			if mode == 0:
				return [mode] + _floats(2)
			if mode == 1:
				return [mode, _f32()]
			return [mode]
		"op193_mode":
			var mode := _u8()
			return [mode, _pstr()] if mode == 3 else [mode]
		"op245_args":
			if bytes[_p] == 0:
				_p += 1
				return [_u8(), _pstr()]
			return [_pstr()]
		"op248_args":
			var mode := _u8()
			var x := _f32()
			return [mode, x] + _floats(2 if mode == 0 else 1)
		"op172_position", "op178_position":
			var mode := _u8()
			return [mode, _u8()] if mode == 3 else [mode] + _floats(3)
		"op173_target":
			var name := _pstr()
			return [name] if not name.is_empty() else ["", _pstr()] + _floats(4)
		"op180_offset":
			var mode := _u8()
			return [mode] + (_floats(3) if mode != 0 else [])
		"op181_source":
			var mode := _u8()
			if mode == 0:
				return [mode, _u8(), _u32()]
			if mode == 1:
				return [mode, _u8()] + _floats(2) + [_u32()]
			return [mode]
		"op203_height":
			var mode := _u8()
			return [mode, _f32()] if mode == 1 else [mode]
		"op224_params":
			var mode := _u8()
			return [mode] + (_floats(2) if mode != 0 else [])
		"op228_type_name":
			if bytes[_p] == 0:
				_p += 1
				return ["", _u8()]
			return _pstr()
		"op242_params":
			var mode := _u8()
			return [mode] + (_floats(12) if mode != 0 else [])
		"op158_hit_target":
			return _offset() if prev[2] & 2 else null
	if code.begins_with("repeat:"):
		var items := code.substr(7).split(",")
		var out := []
		for i in _u8():
			var item := []
			for item_code in items:
				item.push_back(_read(item_code, ins))
			out.push_back(item)
		return out
	push_error("Unknown operand code %s" % code)
	return null


## Returns the code offsets an instruction can continue to besides the next instruction (for
## disassembly and validation).
func get_targets(ins: Instruction) -> Array[int]:
	var targets: Array[int] = []
	var codes: Array = MDKScriptOpcodes.OPERANDS.get(ins.opcode, [])
	for i in codes.size():
		var code: String = codes[i]
		if code == "code32" and ins.operands[i] != 0:
			targets.push_back(ins.operands[i])
		elif code.begins_with("repeat:"):
			var item_codes := code.substr(7).split(",")
			for item in ins.operands[i]:
				for k in item_codes.size():
					if item_codes[k] == "code32" and item[k] != 0:
						targets.push_back(item[k])
		elif code == "op158_hit_target" and ins.operands[i] != null and ins.operands[i] != 0:
			targets.push_back(ins.operands[i])
	for k in range(1, ins.action.size()):
		if ins.action[0] != "none" and ins.action[k] is int and ins.action[k] != 0:
			targets.push_back(ins.action[k])
	return targets

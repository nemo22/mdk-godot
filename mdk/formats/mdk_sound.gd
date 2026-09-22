## MDK sounds: RIFF WAV data, stand-alone (`MAINSONG`, `SND_PUSH`) or in SNI archives (see `MDKSni`).
class_name MDKSound
extends RefCounted


## Loads a WAV sound. `loop` makes it loop forever (for music).
static func load_wav(wav: PackedByteArray, loop := false) -> AudioStreamWAV:
	return AudioStreamWAV.load_from_buffer(_clean_wav(wav), {
		"compress/mode": 0,
		# 1: disabled, 2: forward.
		"edit/loop_mode": 2 if loop else 1,
	})


## Rebuilds a WAV file with only its `fmt ` and `data` chunks. Some of MDK's files have headers that
## don't count a final pad byte (`GATTFIRE`) or truncated `LIST` chunks.
static func _clean_wav(wav: PackedByteArray) -> PackedByteArray:
	var format := PackedByteArray()
	var data := PackedByteArray()
	var pos := 12
	while pos + 8 <= wav.size():
		var chunk_id := wav.slice(pos, pos + 4).get_string_from_ascii()
		var size := wav.decode_u32(pos + 4)
		var end := mini(pos + 8 + size, wav.size())
		if chunk_id == "fmt ":
			format = wav.slice(pos + 8, end)
		elif chunk_id == "data":
			data = wav.slice(pos + 8, end)
		pos += 8 + size + (size & 1)
	if format.is_empty() or data.is_empty():
		return wav
	var pad := data.size() & 1
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46464952)  # "RIFF"
	out.encode_u32(4, 4 + 8 + format.size() + 8 + data.size() + pad)
	out.encode_u32(8, 0x45564157)  # "WAVE"
	out.encode_u32(12, 0x20746D66)  # "fmt "
	out.encode_u32(16, format.size())
	out.append_array(format)
	var data_header := PackedByteArray()
	data_header.resize(8)
	data_header.encode_u32(0, 0x61746164)  # "data"
	data_header.encode_u32(4, data.size())
	out.append_array(data_header)
	out.append_array(data)
	# Chunks are padded to an even size.
	if pad:
		out.append(0)
	return out

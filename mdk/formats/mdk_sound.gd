## MDK sounds: RIFF WAV data, stand-alone (`MAINSONG`, `SND_PUSH`) or in SNI archives.
##
## SNI layout: common header, `u32 count`, then per entry `char[12] name, u16 ?, u16 ?, u32 offset,
## u32 length` (offset relative to file offset 4).
class_name MDKSound
extends RefCounted


## Loads a WAV sound. `loop` makes it loop forever (for music).
static func load_wav(wav: PackedByteArray, loop := false) -> AudioStreamWAV:
	# Some RIFF headers (such as `GATTFIRE`'s) don't count the pad byte after an odd-sized data chunk.
	if wav.decode_u32(4) + 8 == wav.size() - 1:
		wav = wav.duplicate()
		wav.encode_u32(4, wav.size() - 8)
	return AudioStreamWAV.load_from_buffer(wav, {
		"compress/mode": 0,
		# 1: disabled, 2: forward.
		"edit/loop_mode": 2 if loop else 1,
	})


## Loads all sounds of an SNI archive. Returns a Dictionary of name to AudioStreamWAV.
static func load_sni(path: String) -> Dictionary:
	var sounds := {}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return sounds
	var r := BinReader.new(bytes, 0x14)
	var count := r.u32()
	for i in count:
		var sound_name := r.name(12)
		r.skip(4)
		var offset := 4 + r.u32()
		var length := r.u32()
		sounds[sound_name] = load_wav(bytes.slice(offset, offset + length))
	return sounds

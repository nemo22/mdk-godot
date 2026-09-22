## An SNI archive (`TRAVERSE.SNI`, `LEVELnS.SNI`, `LEVELnO.SNI`).
##
## Layout: common header, `u32 count`, then per entry `char[12] name, u16 flags, u16 ?, u32 offset,
## u32 length` (offset relative to file offset 4). Most entries are RIFF WAV sounds (flags 3: music);
## in `LEVELnO.SNI`, the corridor entries (`CHMO_n`, `CMEAT_n`, …) hold the corridors' world geometry
## instead (same layout as an arena's world section).
class_name MDKSni
extends RefCounted

var bytes := PackedByteArray()
## Entry name to `[offset, length, flags]`.
var entries := {}

var _sounds := {}
var _animations := {}


static func load_file(path: String) -> MDKSni:
	var sni := MDKSni.new()
	sni.bytes = FileAccess.get_file_as_bytes(path)
	if sni.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(sni.bytes, 0x14)
	var count := r.u32()
	for i in count:
		var entry_name := r.name(12)
		var flags := r.u16()
		r.skip(2)
		var offset := 4 + r.u32()
		sni.entries[entry_name] = [offset, r.u32(), flags]
	return sni


func is_sound(entry_name: String) -> bool:
	var offset: int = entries[entry_name][0]
	return bytes.slice(offset, offset + 4).get_string_from_ascii() == "RIFF"


## Returns a sound (AudioStreamWAV), or `null` if the entry isn't a sound.
func get_sound(entry_name: String) -> AudioStreamWAV:
	if not _sounds.has(entry_name):
		if not entries.has(entry_name) or not is_sound(entry_name):
			return null
		var entry: Array = entries[entry_name]
		_sounds[entry_name] = MDKSound.load_wav(bytes.slice(entry[0], entry[0] + entry[1]))
	return _sounds[entry_name]


## Returns a sprite animation of the archive (Kurt's extra frames in `LEVELnS.SNI`), or `null`.
func get_animation(entry_name: String) -> MDKSpriteAnimation:
	if not entries.has(entry_name) or is_sound(entry_name):
		return null
	if not _animations.has(entry_name):
		_animations[entry_name] = MDKSpriteAnimation.parse(entry_name, bytes, entries[entry_name][0] + 4)
	return _animations[entry_name]


## Returns every sound of the archive, by name.
func get_sounds() -> Dictionary:
	var sounds := {}
	for entry_name: String in entries:
		if is_sound(entry_name):
			sounds[entry_name] = get_sound(entry_name)
	return sounds

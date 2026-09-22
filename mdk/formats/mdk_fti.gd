## `MISC/MDKFONT.FTI`: user interface resources (texts, fonts, palette, sounds).
##
## Layout: `u32 size, u32 count`, then per entry `char[8] name, u32 offset` (relative to file offset 4).
## Entries include:
## - Texts (`OPT0`–`OPT4` main menu, `OM_*` options, `KM_*` key names, …): NUL-terminated,
##   with `\n` escapes for line breaks.
## - `SYS_PAL`: the first 64 palette colors used by the interface.
## - `FONTBIG`, `FONTSML`: fonts (see `MDKFont`).
## - `F8`: 8×8 bitmap font (128 characters, 8 bytes each).
## - `SND_PUSH`: menu sound (RIFF WAV).
class_name MDKFti
extends RefCounted

var bytes := PackedByteArray()
## Entry name to `[offset, size]`.
var entries := {}


static func load_file(path: String) -> MDKFti:
	var fti := MDKFti.new()
	fti.bytes = FileAccess.get_file_as_bytes(path)
	if fti.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(fti.bytes, 4)
	var count := r.u32()
	var offsets := []
	for i in count:
		var entry_name := r.name(8)
		offsets.push_back([4 + r.u32(), entry_name])
	offsets.sort()
	for i in offsets.size():
		var end: int = offsets[i + 1][0] if i + 1 < offsets.size() else fti.bytes.size()
		fti.entries[offsets[i][1]] = [offsets[i][0], end - offsets[i][0]]
	return fti


func get_bytes(entry_name: String) -> PackedByteArray:
	var entry: Array = entries[entry_name]
	return bytes.slice(entry[0], entry[0] + entry[1])


## Returns a text entry, or `fallback` if it doesn't exist.
func get_text(entry_name: String, fallback := "") -> String:
	if not entries.has(entry_name):
		return fallback
	var offset: int = entries[entry_name][0]
	var end := bytes.find(0, offset)
	return bytes.slice(offset, end).get_string_from_ascii().replace("\\n", "\n")


## Returns a text entry as bytes (the fonts' character set), `\n` escapes included, or an empty
## array if it doesn't exist.
func get_text_bytes(entry_name: String) -> PackedByteArray:
	if not entries.has(entry_name):
		return PackedByteArray()
	var offset: int = entries[entry_name][0]
	return bytes.slice(offset, bytes.find(0, offset))

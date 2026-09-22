## A BNI archive (`TRAVSPRT.BNI`, `OPTIONS.BNI`, …): images and sprite animations.
##
## Layout: `u32 size, u32 count`, then per entry `char[12] name, u32 offset` (relative to file
## offset 4). Entry sizes are the difference between consecutive offsets.
class_name MDKBni
extends RefCounted

var bytes := PackedByteArray()
## Entry name to `[offset, size]`.
var entries := {}

var _animations := {}
var _images := {}


static func load_file(path: String) -> MDKBni:
	var bni := MDKBni.new()
	bni.bytes = FileAccess.get_file_as_bytes(path)
	if bni.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(bni.bytes, 4)
	var count := r.u32()
	var offsets := []
	for i in count:
		var entry_name := r.name(12)
		offsets.push_back([4 + r.u32(), entry_name])
	offsets.sort()
	for i in offsets.size():
		var end: int = offsets[i + 1][0] if i + 1 < offsets.size() else bni.bytes.size()
		bni.entries[offsets[i][1]] = [offsets[i][0], end - offsets[i][0]]
	return bni


func has(entry_name: String) -> bool:
	return entries.has(entry_name)


## Returns a plain image entry (`u16 width, u16 height`, palette indices).
func get_image(entry_name: String) -> MDKTexture:
	if not _images.has(entry_name):
		_images[entry_name] = MDKTexture.parse(entry_name, bytes, entries[entry_name][0])
	return _images[entry_name]


## Returns a sprite animation entry (`u32 size`, then the animation).
func get_animation(entry_name: String) -> MDKSpriteAnimation:
	if not _animations.has(entry_name):
		_animations[entry_name] = MDKSpriteAnimation.parse(entry_name, bytes, entries[entry_name][0] + 4)
	return _animations[entry_name]

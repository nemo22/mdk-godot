## `LEVELn.DTI`: level settings, arena list, base palette and sky.
## The game loads the file without its first 4 bytes; block offsets are relative to that.
class_name MDKDti
extends RefCounted

var bytes := PackedByteArray()
var palette: MDKPalette

## Player start position (MDK coordinates) and angle (degrees; 90 faces +Y).
var start_position := Vector3()
var start_angle := 0.0

## Sky panorama. Rows are `sky.width` pixels, of which the first `sky_wrap_width` cover 360°
## (the remaining columns repeat the start, for wrapping).
var sky: MDKTexture
var sky_wrap_width := 0
## Panorama row at eye level.
var sky_horizon_row := 0
## Horizontal panorama offset in pixels.
var sky_offset := 0
## Palette indices used to fill the screen above and below the panorama.
var sky_top_color := 0
var sky_bottom_color := 0
## Arenas and corridors (`HMO_n`, `CHMO_n`), in file order. Each is a Dictionary with
## `name`, `value` (f32 ❓) and `records` (Array of Dictionaries with `type`, `id`, `position`, `name`).
var arenas: Array[Dictionary] = []


static func load_file(path: String) -> MDKDti:
	var dti := MDKDti.new()
	dti.bytes = FileAccess.get_file_as_bytes(path)
	if dti.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	dti._parse()
	return dti


func _block(index: int) -> int:
	return 4 + bytes.decode_u32(4 + 0x10 + index * 4)


func _parse() -> void:
	# Block 3: u32 (number of arena colors, 112), then the 256-color palette.
	var palette_offset := _block(3) + 4
	palette = MDKPalette.from_rgb(bytes.slice(palette_offset, palette_offset + 768))

	# Block 0: level settings.
	var r0 := BinReader.new(bytes, _block(0))
	var _unknown := r0.u32()
	start_position = r0.vec3()
	start_angle = r0.f32()
	sky_top_color = r0.u32()
	sky_bottom_color = r0.u32()
	sky_horizon_row = r0.u32()
	sky_offset = r0.u32()
	sky_wrap_width = r0.u32()
	var sky_height := r0.u32()
	# If positive, the level has a second panorama (levels 5 and 6); the Direct3D renderer uses it.
	var second_sky_top_color := r0.s32()
	var _second_sky_bottom_color := r0.s32()

	# Block 4: sky panorama(s) (each row has 4 extra pixels for wrapping).
	sky = MDKTexture.new()
	sky.name = "SKY"
	sky.width = sky_wrap_width + 4
	sky.height = sky_height
	var sky_pixels := _block(4)
	if second_sky_top_color > 0:
		sky_pixels += sky.width * sky.height
	sky.indices = bytes.slice(sky_pixels, sky_pixels + sky.width * sky.height)

	# Block 2: arenas and corridors, with their object records.
	var r := BinReader.new(bytes, _block(2))
	var count := r.u32()
	for i in count:
		var arena := {name = r.name(8)}
		var records_offset := 4 + r.u32()
		arena.value = r.f32()
		arena.records = _parse_records(records_offset)
		arenas.push_back(arena)


func _parse_records(offset: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var r := BinReader.new(bytes, offset)
	var count := r.u32()
	for i in count:
		var record := {type = r.u32(), id = r.s32(), angle = r.f32()}
		record.position = r.vec3()
		record.name = r.name(12)
		records.push_back(record)
	return records

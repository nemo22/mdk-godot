## Locates the original MDK game data and provides access to its files.
extends Node

## The path to the MDK installation folder (contains `TRAVERSE`, `MISC`, …).
var data_dir := ""


func _ready() -> void:
	data_dir = find_data_dir()
	if data_dir.is_empty():
		OS.alert("Couldn't find the MDK game data. You need the full version of MDK (GOG or Steam).\n"
				+ "Place this project folder within the MDK installation folder, or install MDK in the default GOG location.")
		get_tree().quit(1)
		return
	print("MDK data: %s" % data_dir)


## Returns the MDK installation folder, or an empty string if it can't be found.
static func find_data_dir() -> String:
	var candidates: Array[String] = [
		# Parent folder of the project (the project folder is placed within the MDK installation folder).
		ProjectSettings.globalize_path("res://").path_join("..").simplify_path(),
		"C:/GOG Games/MDK",
		"C:/Program Files (x86)/GOG Galaxy/Games/MDK",
		"C:/Program Files (x86)/Steam/steamapps/common/MDK",
		OS.get_environment("HOME").path_join(".wine/drive_c/GOG Games/MDK"),
	]
	if OS.has_feature("template"):
		# Exported project placed within the MDK installation folder.
		candidates.push_front(OS.get_executable_path().get_base_dir())
	var env_dir := OS.get_environment("MDK_DATA_DIR")
	if not env_dir.is_empty():
		candidates.push_front(env_dir)

	for candidate in candidates:
		if FileAccess.file_exists(candidate.path_join("TRAVERSE/TRAVSPRT.BNI")):
			return candidate
	return ""


## Returns the absolute path of a file within the MDK data folder (such as `TRAVERSE/LEVEL3/LEVEL3O.MTO`).
func path(relative_path: String) -> String:
	return data_dir.path_join(relative_path)


## Reads a whole MDK data file. Returns an empty array (and prints an error) on failure.
func read_file(relative_path: String) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(path(relative_path))
	if bytes.is_empty():
		push_error("Couldn't read MDK data file: %s (%s)" % [path(relative_path), error_string(FileAccess.get_open_error())])
	return bytes

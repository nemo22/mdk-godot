## Command line options (after `--`), such as `--level=4 --screenshot=out.png`.
class_name Args
extends RefCounted


static func get_all() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


static func parse_vector(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## Saves a screenshot after the next frames are drawn, then quits.
static func screenshot_and_quit(tree: SceneTree, path: String, frames := 2) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(path)
	print("Saved screenshot: %s" % path)
	tree.quit()

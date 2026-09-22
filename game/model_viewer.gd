## Shows the models of an arena side by side, playing a matching animation for each.
##
## Command line (after `--`):
##   --models                  Open this viewer (from the main scene).
##   --level=N                 Level (3–8, default 3).
##   --arena=NAME              Arena (default: the first one).
##   --screenshot=path.png     Save a screenshot and quit.
extends Node3D

const FRAMES_PER_SECOND := 30.0

## Per model instance: `[MeshInstance3D, Array of ArrayMesh frames, speed]`.
var _animated := []
var _time := 0.0

@onready var camera: Camera3D = $Camera
@onready var info: Label = $Info


func _ready() -> void:
	var args := Args.get_all()
	var level := int(args.get("level", "3"))
	var dir := "TRAVERSE/LEVEL%d/" % level
	var dti := MDKDti.load_file(MDKData.path(dir + "LEVEL%d.DTI" % level))
	var mto := MDKMto.load_file(MDKData.path(dir + "LEVEL%dO.MTO" % level))
	var level_textures := MDKTextureArchive.load_file(MDKData.path(dir + "LEVEL%dS.MTI" % level))
	var arena_name: String = args.get("arena", mto.get_arena_names()[0])
	var arena := mto.get_arena(arena_name)
	var palette := dti.palette.with_arena_colors(arena.palette_rgb)
	var resolver := MDKMeshBuilder.MaterialResolver.new(palette, [arena.textures, level_textures])

	var x := 0.0
	var names := []
	for model_name: String in arena.models:
		var model: MDKModel = arena.models[model_name]
		var animation := _find_animation(arena, model)
		var frames := []
		if animation:
			for pose in animation.bake(model):
				frames.push_back(MDKMeshBuilder.build_model_mesh(model, pose, resolver))
		else:
			frames.push_back(MDKMeshBuilder.build_model_mesh(model, model.get_rest_pose(), resolver))
		var instance := MeshInstance3D.new()
		instance.mesh = frames[0]
		var aabb := instance.mesh.get_aabb()
		x += aabb.size.x * 0.5 + 4.0
		instance.position = Vector3(x - aabb.get_center().x, -aabb.position.y, 0.0)
		x += aabb.size.x * 0.5 + 4.0
		add_child(instance)
		_animated.push_back([instance, frames, animation.speed if animation else 1.0])
		names.push_back("%s%s" % [model_name, " (%s)" % animation.name if animation else ""])

	info.text = "Level %d, %s: %s" % [level, arena_name, ", ".join(names)]
	camera.position = Vector3(x * 0.5, x * 0.18, x * 0.55)
	camera.look_at(Vector3(x * 0.5, 2.0, 0.0))
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot, 10)


## Returns the first animation of the arena named after the model whose tracks match its parts.
func _find_animation(arena: MDKArena, model: MDKModel) -> MDKModelAnimation:
	for animation_name: String in arena.animations:
		if animation_name == model.name or animation_name.begins_with(model.name + "_"):
			return arena.animations[animation_name]
	return null


func _process(delta: float) -> void:
	_time += delta
	for entry in _animated:
		var frames: Array = entry[1]
		entry[0].mesh = frames[int(_time * FRAMES_PER_SECOND * entry[2]) % frames.size()]

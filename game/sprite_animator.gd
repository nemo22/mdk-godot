## Plays MDK sprite animations (MDKSpriteAnimation) at a fixed screen size (see `sprite.gdshader`).
class_name SpriteAnimator
extends MeshInstance3D

const SPRITE_SHADER := preload("res://mdk/shaders/sprite.gdshader")

## Added to each frame's hotspot to get the pixel placed on the node's origin.
## Kurt's frames are drawn 101 pixels above his projected feet.
@export var anchor_offset := Vector2(0, 101)

var animation: MDKSpriteAnimation
var frame := 0
var flip_h := false:
	set(value):
		flip_h = value
		if _material:
			_material.set_shader_parameter(&"flip_h", flip_h)

var _material: ShaderMaterial


func setup(palette: MDKPalette) -> void:
	mesh = QuadMesh.new()
	# The quad is repositioned in the shader, so its bounds must cover the whole sprite.
	custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	_material = ShaderMaterial.new()
	_material.shader = SPRITE_SHADER
	_material.set_shader_parameter(&"palette", palette.get_texture())
	material_override = _material


## Shows `p_frame` of `p_animation` (wrapped to the animation length).
func show_frame(p_animation: MDKSpriteAnimation, p_frame: int) -> void:
	animation = p_animation
	frame = posmod(p_frame, animation.frame_count)
	var texture := animation.get_frame(frame)
	_material.set_shader_parameter(&"index_texture", texture.get_index_texture())
	_material.set_shader_parameter(&"frame_size", Vector2(texture.width, texture.height))
	_material.set_shader_parameter(&"anchor", Vector2(animation.get_hotspot(frame)) + anchor_offset)

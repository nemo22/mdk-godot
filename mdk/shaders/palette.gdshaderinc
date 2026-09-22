// Shared by palette.gdshader (arenas, culls back faces) and palette_double_sided.gdshader (models).
uniform sampler2D index_texture : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;
// Animated textures: frames are stacked vertically in `index_texture`.
uniform int frame_count = 1;
uniform float frames_per_second = 15.0;
// Per object frame of animated textures (explosions follow their object's frame), -1 = by time.
instance uniform int frame_index = -1;

void fragment() {
	vec2 uv = UV;
	if (frame_count > 1) {
		float frame = frame_index >= 0 ? float(min(frame_index, frame_count - 1)) : mod(floor(TIME * frames_per_second), float(frame_count));
		uv.y = (fract(uv.y) + frame) / float(frame_count);
	}
	int index = int(round(texture(index_texture, uv).r * 255.0));
	// Palette index 0 is transparent (used by effect textures: explosions, fire, trails…).
	if (index == 0) {
		discard;
	}
	ALBEDO = texelFetch(palette, ivec2(index, 0), 0).rgb * COLOR.rgb;
}

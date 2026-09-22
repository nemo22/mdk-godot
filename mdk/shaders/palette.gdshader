// Renders an 8-bit paletted texture: `index_texture` holds palette indices (R8), `palette` is 256×1.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D index_texture : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;
// Animated textures: frames are stacked vertically in `index_texture`.
uniform int frame_count = 1;
uniform float frames_per_second = 15.0;

void fragment() {
	vec2 uv = UV;
	if (frame_count > 1) {
		float frame = mod(floor(TIME * frames_per_second), float(frame_count));
		uv.y = (fract(uv.y) + frame) / float(frame_count);
	}
	float index = texture(index_texture, uv).r;
	ALBEDO = texelFetch(palette, ivec2(int(round(index * 255.0)), 0), 0).rgb * COLOR.rgb;
}

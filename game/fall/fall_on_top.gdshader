// The fall's explosions, sorted at camera z + 5 (0x411aa4): palette.gdshaderinc's colours drawn
// over everything, without the depth test, after the opaque models (ALPHA puts them in the
// transparent pass).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D index_texture : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;
uniform int frame_count = 1;
instance uniform int frame_index = -1;

void fragment() {
	vec2 uv = UV;
	if (frame_count > 1) {
		uv.y = (fract(uv.y) + float(clamp(frame_index, 0, frame_count - 1))) / float(frame_count);
	}
	int index = int(round(texture(index_texture, uv).r * 255.0));
	// Palette index 0 is transparent.
	if (index == 0) {
		discard;
	}
	ALBEDO = texelFetch(palette, ivec2(index, 0), 0).rgb * COLOR.rgb;
	ALPHA = 1.0;
}

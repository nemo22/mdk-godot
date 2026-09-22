// Renders an 8-bit paletted texture: `index_texture` holds palette indices (R8), `palette` is 256×1.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D index_texture : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;

void fragment() {
	float index = texture(index_texture, UV).r;
	ALBEDO = texelFetch(palette, ivec2(int(round(index * 255.0)), 0), 0).rgb * COLOR.rgb;
}

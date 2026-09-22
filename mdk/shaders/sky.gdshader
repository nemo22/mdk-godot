// MDK sky. The original blits a panorama as a 2D backdrop: it scrolls horizontally with the yaw
// (`wrap_width` pixels for 360°) and vertically with the pitch, with `horizon_row` at eye level.
// The screen above and below the panorama is filled with `top_color` and `bottom_color`.
shader_type sky;

uniform sampler2D sky_index : filter_nearest, repeat_disable;
uniform sampler2D palette : source_color, filter_nearest;
uniform float texture_width = 1804.0;
uniform float wrap_width = 1800.0;
uniform float horizon_row = 240.0;
uniform float offset = 300.0;
uniform int top_color = 0;
uniform int bottom_color = 0;

void sky() {
	float pixels_per_radian = wrap_width / TAU;
	float azimuth = atan(EYEDIR.x, -EYEDIR.z);
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0));
	float column = mod(azimuth * pixels_per_radian + offset, wrap_width);
	float row = horizon_row - elevation * pixels_per_radian;
	vec2 size = vec2(textureSize(sky_index, 0));
	int index;
	if (row < 0.0) {
		index = top_color;
	} else if (row >= size.y) {
		index = bottom_color;
	} else {
		index = int(round(texture(sky_index, vec2((column + 0.5) / texture_width, row / size.y)).r * 255.0));
	}
	COLOR = texelFetch(palette, ivec2(index, 0), 0).rgb;
}

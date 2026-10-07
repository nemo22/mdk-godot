// Outlines of glass panes: the original draws them after the triangles, without a depth buffer, so
// they cover the edges they lie on. Here they're pulled towards the eye by a share of their
// distance: the same place on screen, nearer in depth, so the edge doesn't hide them by halves.
//
//   eye ●─────────────────────○── edge
//                          ◄──┘ outline: 1/128 of the distance
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float pull = 0.0078125;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * (1.0 - pull);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
}

// Renders an 8-bit paletted texture: `index_texture` holds palette indices (R8), `palette` is 256×1.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://mdk/shaders/palette.gdshaderinc"

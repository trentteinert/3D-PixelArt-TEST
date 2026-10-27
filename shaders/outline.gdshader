shader_type spatial;
render_mode cull_front, unshaded;
// Inverted-hull outline. Use as the next_pass of another material (smooth-normal meshes only).

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float width : hint_range(0.0, 0.1) = 0.025;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

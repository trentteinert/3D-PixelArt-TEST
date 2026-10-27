shader_type spatial;
// World-space grid so you can judge scale and speed while testing movement.

uniform vec4 base_color : source_color = vec4(0.45, 0.5, 0.55, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.28, 0.32, 1.0);
uniform float cell_size = 1.0;
uniform float line_width : hint_range(0.005, 0.2) = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Use XZ for flat surfaces, XY/ZY for walls, picked from the world-space normal.
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec2 g = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float line = step(min(g.x, g.y), line_width);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 1.0;
}

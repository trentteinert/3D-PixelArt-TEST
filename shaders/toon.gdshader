shader_type spatial;
// Stepped (cel) lighting with a rim highlight. Tweak the uniforms live in the Inspector.

uniform vec4 albedo : source_color = vec4(1.0);
uniform int bands : hint_range(2, 8) = 3;
uniform float shade_floor : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	ALBEDO = albedo.rgb;
	// Marks this surface as "character" in the normal/roughness buffer so edge_highlight can skip it.
	// Level shaders leave roughness at 1.0.
	ROUGHNESS = 0.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * rim * rim_strength;
}

void light() {
	float d = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = floor(d * float(bands)) / float(bands);
	float lit = mix(shade_floor, 1.0, stepped);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit / PI;
}

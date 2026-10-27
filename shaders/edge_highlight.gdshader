shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;
// Full-screen post effect: lightens convex edges, darkens concave edges and silhouettes,
// using the depth + normal buffers. Put it on a 2x2 QuadMesh under the Camera3D, inside
// the low-res SubViewport so every edge is exactly one pixel wide.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform float depth_threshold : hint_range(0.0, 0.2) = 0.03;
uniform float normal_threshold : hint_range(0.0, 2.0) = 0.4;
uniform float convex_highlight : hint_range(1.0, 2.0) = 1.4;
uniform float concave_shadow : hint_range(0.0, 1.0) = 0.7;
uniform float silhouette_shade : hint_range(0.0, 2.0) = 0.6;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float depth = texture(depth_tex, uv).x;
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return p.xyz / p.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	vec3 p0 = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d0 = -p0.z;
	vec3 n0 = view_normal(SCREEN_UV);

	vec2 offs[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	float max_depth_step = 0.0;
	float normal_sum = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offs[i] * px;
		float d = -view_pos(uv, INV_PROJECTION_MATRIX).z;
		max_depth_step = max(max_depth_step, d - d0);
		// UV y points down, view-space y points up.
		normal_sum += dot(n0 - view_normal(uv), vec3(offs[i].x, -offs[i].y, 0.0));
	}

	// Surfaces seen at a grazing angle have big depth steps between pixels; relax the threshold.
	float facing = max(abs(dot(n0, normalize(p0))), 0.15);
	float thresh = depth_threshold * d0 / facing;

	if (max_depth_step > thresh) {
		col *= silhouette_shade;
	} else if (normal_sum < -normal_threshold) {
		col *= convex_highlight;
	} else if (normal_sum > normal_threshold) {
		col *= concave_shadow;
	}
	ALBEDO = col;
}

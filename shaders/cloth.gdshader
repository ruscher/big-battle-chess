shader_type spatial;
// Wind-driven cloth for capes, tabards and banners. The mesh is a subdivided
// plane hanging from its top edge (UV.y = 0 at the anchor). Displacement
// grows toward the free edge so the attachment never moves.

uniform vec4 albedo : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 trim_color : source_color = vec4(0.9, 0.7, 0.3, 1.0);
uniform float trim_width = 0.04;
uniform float roughness = 0.82;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.6;
uniform float phase = 0.0;
uniform vec3 sway_axis = vec3(0.0, 0.0, 1.0);
uniform float weave_scale = 180.0;

varying float v_fold;

void vertex() {
	float free_amount = UV.y * UV.y;
	float t = TIME * wind_speed + phase;
	float wave = sin(t + UV.y * 4.0 + UV.x * 2.5) * 0.6 + sin(t * 1.7 + UV.y * 7.0 - UV.x * 3.0) * 0.4;
	VERTEX += sway_axis * wave * wind_strength * free_amount;
	VERTEX.x += sin(t * 0.8 + UV.y * 3.0) * wind_strength * 0.35 * free_amount;
	v_fold = wave * free_amount;
}

void fragment() {
	float edge = step(1.0 - trim_width, UV.y) + step(UV.x, trim_width * 0.6) + step(1.0 - trim_width * 0.6, UV.x);
	vec3 base = mix(albedo.rgb, trim_color.rgb, clamp(edge, 0.0, 1.0));
	// Woven fabric micro pattern and fold shading.
	float weave = sin(UV.x * weave_scale) * sin(UV.y * weave_scale * 1.3) * 0.04;
	ALBEDO = base * (0.92 + weave + v_fold * 0.25);
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	METALLIC = edge > 0.5 ? 0.6 : 0.0;
}

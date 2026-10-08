shader_type spatial;
// Procedural board surface for all board themes (marble, wood, stone, gold,
// obsidian...). One draw for the whole 8x8 playing field: the checker
// pattern is computed from UV, so themes are just uniform sets.

uniform vec4 light_color : source_color = vec4(0.88, 0.85, 0.78, 1.0);
uniform vec4 dark_color : source_color = vec4(0.12, 0.11, 0.12, 1.0);
uniform vec4 vein_color : source_color = vec4(0.6, 0.6, 0.62, 1.0);
uniform float vein_strength = 0.5;
uniform float vein_scale = 3.0;
uniform float grain = 0.0;          // 1 = wood grain instead of marble veins
uniform float light_roughness = 0.18;
uniform float dark_roughness = 0.22;
uniform float light_metallic = 0.0;
uniform float dark_metallic = 0.0;
uniform float groove_width = 0.012;
uniform vec4 groove_color : source_color = vec4(0.05, 0.04, 0.03, 1.0);
uniform float clearcoat_amount = 0.6;
uniform bool invert_pattern = false;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void fragment() {
	vec2 cell = UV * 8.0;
	vec2 id = floor(cell);
	vec2 local = fract(cell);
	bool is_light = (mod(id.x + id.y, 2.0) > 0.5) != invert_pattern;
	// Each square gets its own slab orientation/offset like real cut stone.
	vec2 seed = id * 3.17 + vec2(hash(id) * 10.0);
	vec2 q = (local + seed) * vec2(vein_scale, vein_scale * 0.6);
	float pattern;
	if (grain > 0.5) {
		float rings = fbm(vec2(q.x * 0.3, q.y * 6.0)) * 6.0 + q.y * 3.0;
		pattern = smoothstep(0.3, 0.7, abs(fract(rings) - 0.5) * 2.0);
	} else {
		float n = fbm(q + fbm(q * 1.7) * 2.0);
		pattern = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
	}
	vec3 base = is_light ? light_color.rgb : dark_color.rgb;
	vec3 veined = mix(base, vein_color.rgb * (is_light ? 1.0 : 0.6), pattern * vein_strength);
	veined *= 0.94 + fbm(UV * 90.0) * 0.12;
	float groove = 1.0 - smoothstep(0.0, groove_width, min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y)));
	ALBEDO = mix(veined, groove_color.rgb, groove * 0.85);
	ROUGHNESS = mix(is_light ? light_roughness : dark_roughness, 0.9, groove) + pattern * 0.08;
	METALLIC = is_light ? light_metallic : dark_metallic;
	CLEARCOAT = clearcoat_amount * (1.0 - groove);
	CLEARCOAT_ROUGHNESS = 0.15;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Fresnel energy shell used for auras, orbs, light pillars and shockwaves.

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float intensity = 2.0;
uniform float fresnel_power = 2.5;
uniform float scroll = 1.5;
uniform float noise_amount = 0.6;
uniform float fade = 1.0;
uniform float ring_mode = 0.0; // 1: thin expanding ring (uses UV.y as radius)

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);
	float n = noise(UV * vec2(8.0, 4.0) + vec2(0.0, -TIME * scroll)) * noise(UV * vec2(3.0, 9.0) + vec2(TIME * scroll * 0.5, 0.0));
	float a = mix(fres, fres + n * 1.5, noise_amount);
	if (ring_mode > 0.5) {
		float r = abs(UV.y - 0.5) * 2.0;
		a = (1.0 - smoothstep(0.0, 1.0, r)) * (0.6 + n);
	}
	a *= fade;
	ALBEDO = color.rgb * intensity * a;
	ALPHA = clamp(a, 0.0, 1.0);
}

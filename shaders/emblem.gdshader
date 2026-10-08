shader_type spatial;
render_mode cull_disabled;
// Procedural heraldry. emblem 0: radiant sun (Kingdom of Dawn),
// emblem 1: crescent with slit eye (Umbral Dominion).

uniform int emblem = 0;
uniform vec4 field : source_color = vec4(0.1, 0.2, 0.5, 1.0);
uniform vec4 charge : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float glow = 0.0;

float sun(vec2 p) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float rays = smoothstep(0.0, 0.08, cos(a * 12.0) * 0.5 + 0.5 - 0.35) * step(r, 0.42) * step(0.2, r);
	float disc = 1.0 - smoothstep(0.17, 0.19, r);
	return max(disc, rays);
}

float umbral(vec2 p) {
	float outer = 1.0 - smoothstep(0.36, 0.38, length(p));
	float inner = 1.0 - smoothstep(0.3, 0.32, length(p - vec2(0.12, 0.05)));
	float crescent = clamp(outer - inner, 0.0, 1.0);
	vec2 e = p - vec2(-0.02, -0.02);
	float eye = 1.0 - smoothstep(0.0, 0.02, abs(e.y) - 0.07 * (1.0 - pow(abs(e.x) / 0.2, 2.0)));
	eye *= step(abs(e.x), 0.2);
	float pupil = 1.0 - smoothstep(0.02, 0.035, length(e * vec2(2.5, 1.0)));
	return clamp(crescent + eye - pupil, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	p.y = -p.y;
	float m = emblem == 0 ? sun(p) : umbral(p);
	ALBEDO = mix(field.rgb, charge.rgb, m);
	METALLIC = m * 0.8;
	ROUGHNESS = mix(0.8, 0.3, m);
	EMISSION = charge.rgb * m * glow;
}

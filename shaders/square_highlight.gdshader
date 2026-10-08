shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Overlay marker drawn on a board square.
// kind 0: soft fill (last move), 1: dot (quiet move), 2: ring (capture),
// 3: pulsing fill (check), 4: corner brackets (cursor / selection).

uniform vec4 color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform int kind = 0;
uniform float intensity = 1.0;
uniform float pulse_speed = 3.0;

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p);
	float a = 0.0;
	if (kind == 0) {
		float edge = max(abs(p.x), abs(p.y));
		a = 0.28 + smoothstep(0.38, 0.5, edge) * 0.5;
	} else if (kind == 1) {
		a = 1.0 - smoothstep(0.1, 0.13, d);
		a += (1.0 - smoothstep(0.13, 0.22, d)) * 0.35;
	} else if (kind == 2) {
		a = smoothstep(0.33, 0.36, d) * (1.0 - smoothstep(0.43, 0.46, d));
		a += (1.0 - smoothstep(0.0, 0.45, d)) * 0.15;
	} else if (kind == 3) {
		float pulse = 0.55 + 0.45 * sin(TIME * pulse_speed);
		a = (1.0 - smoothstep(0.0, 0.55, d)) * pulse;
	} else {
		float edge = max(abs(p.x), abs(p.y));
		float frame = smoothstep(0.42, 0.44, edge) * (1.0 - smoothstep(0.48, 0.5, edge));
		float corner = step(0.28, abs(p.x)) * step(0.28, abs(p.y));
		a = frame * corner + frame * 0.25;
		a *= 0.75 + 0.25 * sin(TIME * pulse_speed);
	}
	ALBEDO = color.rgb * a * intensity;
	ALPHA = clamp(a * intensity, 0.0, 1.0);
}

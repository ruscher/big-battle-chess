shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Crescent weapon trail. UV.x runs along the arc (0 = tail, 1 = head),
// UV.y across the blade. `progress` sweeps the visible window.

uniform vec4 color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float intensity = 3.0;
uniform float progress = 1.0;
uniform float length_fraction = 0.6;
uniform float fade = 1.0;

void fragment() {
	float head = progress;
	float tail = progress - length_fraction;
	float along = clamp((UV.x - tail) / max(length_fraction, 0.001), 0.0, 1.0);
	float visible = step(tail, UV.x) * step(UV.x, head);
	float core = 1.0 - abs(UV.y - 0.5) * 2.0;
	float a = visible * pow(along, 1.5) * pow(core, 0.8) * fade;
	vec3 c = mix(color.rgb, vec3(1.0), pow(core, 6.0) * along);
	ALBEDO = c * intensity * a;
	ALPHA = clamp(a, 0.0, 1.0);
}

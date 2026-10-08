shader_type spatial;
// PBR surface for imported characters with per-faction art direction.
// One texture set is shared by both armies; the faction look comes from
// physically-motivated remapping instead of a flat tint:
//   * metal (from the metallic map) is re-toned (polished silver-gold for
//     Dawn, blackened iron for Umbral) while keeping wear and scratches,
//   * non-metal fabric/leather is re-coloured toward the faction cloth colour,
//   * saturated heraldic accents (e.g. painted crosses) become the faction
//     accent colour,
//   * a subtle rim keeps silhouettes readable on the board.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_orm = true;
uniform bool has_normal = true;
uniform float fallback_metallic = 0.0;
uniform float fallback_roughness = 0.6;

uniform vec3 metal_tint : source_color = vec3(1.0);
uniform float metal_tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float metal_gain = 1.0;
uniform float metal_lum_scale = 1.7;        // brightness of re-toned metal relative to source luminance
uniform float metal_roughness_mul = 1.0;
uniform vec3 cloth_tint : source_color = vec3(1.0);
uniform float cloth_tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cloth_gain = 1.0;
uniform float cloth_lum_scale = 1.6;        // recoloured fabric brightness = floor + lum * scale
uniform float cloth_floor = 0.35;
uniform float metal_mask_lo = 0.0;          // remaps the metallic map into the metal/fabric mask
uniform float metal_mask_hi = 1.0;
uniform vec3 accent_color : source_color = vec3(1.0, 0.0, 0.0);
uniform float accent_amount : hint_range(0.0, 1.0) = 0.0;
uniform float accent_hue = 0.0;            // hue (0..1) of the source accent to replace
uniform float accent_hue_width = 0.06;
uniform float accent_sat_min = 0.35;
uniform float accent_val_min = 0.15;
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float rim_amount = 0.12;
uniform float normal_strength = 1.0;
uniform float uv_offset_u = 0.0;            // selects a UDIM-style tile packed in U

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec2 uv = UV + vec2(uv_offset_u, 0.0);
	vec3 base = texture(albedo_tex, uv).rgb;
	vec4 orm = has_orm ? texture(orm_tex, uv) : vec4(1.0, fallback_roughness, fallback_metallic, 1.0);
	float metal = clamp(orm.b, 0.0, 1.0);
	float metal_mask = smoothstep(metal_mask_lo, max(metal_mask_hi, metal_mask_lo + 0.001), metal);
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	// Classify colours in sRGB (the space the texture was measured/authored in).
	vec3 hsv = rgb2hsv(pow(max(base, vec3(0.0)), vec3(1.0 / 2.2)));

	// Metal: keep the luminance detail, move the hue toward the faction metal.
	vec3 metal_col = mix(base, metal_tint * clamp(lum * metal_lum_scale, 0.0, 1.0), metal_tint_amount) * metal_gain;
	// Fabric / leather: recolour by luminance (keeps weave, dirt and folds).
	vec3 cloth_col = mix(base, cloth_tint * (cloth_floor + lum * cloth_lum_scale), cloth_tint_amount) * cloth_gain;
	vec3 col = mix(cloth_col, metal_col, metal_mask);
	// Painted heraldry: saturated pixels near accent_hue.
	float hue_d = min(abs(hsv.x - accent_hue), 1.0 - abs(hsv.x - accent_hue));
	float accent_mask = (1.0 - smoothstep(accent_hue_width, accent_hue_width * 2.0, hue_d)) * smoothstep(accent_sat_min, accent_sat_min + 0.15, hsv.y) * smoothstep(accent_val_min, accent_val_min + 0.08, hsv.z);
	col = mix(col, accent_color * (0.4 + hsv.z * 0.9), accent_mask * accent_amount);

	ALBEDO = clamp(col, 0.0, 1.0);
	METALLIC = metal;
	ROUGHNESS = clamp(orm.g * mix(1.0, metal_roughness_mul, metal), 0.04, 1.0);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	RIM = rim_amount;
	RIM_TINT = 0.5;
	SPECULAR = 0.5;
}

// RuinsCrystal.shader — 时晶（六棱柱网格）：半透感的冷蓝本色 + 菲涅尔边光 + 缓慢呼吸的内发光
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);
uniform vec3 base_color = vec3(0.30, 0.48, 0.95);
uniform vec3 glow_color = vec3(0.30, 0.55, 1.0);
uniform float glow = 1.2;
uniform float ore_mode = 0.0;
uniform float night_k = 0.0;

varying vec3 tint;
varying vec4 vcol;
varying vec3 opos;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
    tint = INSTANCE_COLOR.rgb;
    vcol = COLOR;
    opos = VERTEX;
}

void fragment() {
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(CAMERA_POSITION_WORLD - VERTEX);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.6);
    float breathe = 0.78 + 0.22 * sin(TIME * 1.3 + VERTEX.x * 0.7 + VERTEX.z * 0.5);

    if (ore_mode > 0.5) {
        float facet = clamp(vcol.a, 0.0, 1.0);
        vec3 base_hue = mix(vec3(0.14, 0.42, 0.96), srgb_to_linear(clamp(vcol.rgb, 0.0, 1.0)), 0.38);
        vec3 deep = base_hue * 0.08;
        vec3 mid = base_hue * 0.68;
        vec3 lit = mix(base_hue, vec3(0.65, 0.88, 1.0), 0.58);
        vec3 gem = mix(deep, mid, smoothstep(0.0, 0.50, facet));
        gem = mix(gem, lit, smoothstep(0.45, 1.0, facet));
        gem = mix(gem, vec3(0.62, 0.84, 1.0), fres * 0.52);

        vec3 r = reflect(-v, n);
        float rl = max(clamp(dot(r, -MAIN_LIGHT_DIRECTION), 0.0, 1.0),
                       clamp(dot(r, MAIN_LIGHT_DIRECTION), 0.0, 1.0));
        float glint = pow(rl, 48.0) * (0.4 + 0.6 * facet);
        float auto_night = smoothstep(-0.05, 0.25, MAIN_LIGHT_DIRECTION.z);
        float nk = clamp(max(night_k, auto_night), 0.0, 1.0);

        vec3 day_emit = base_hue * (0.28 + 0.16 * breathe) * (0.35 + 0.65 * facet) + vec3(1.0) * glint * 1.05;
        vec3 ash_core = mix(vec3(0.46, 0.51, 0.58), vec3(0.66, 0.72, 0.80), 0.5 * facet + 0.5 * fres);
        vec3 night_emit = ash_core * (0.42 + 0.28 * breathe) * (0.45 + 0.55 * facet) + vec3(0.80, 0.85, 0.92) * glint * 0.65;

        ALBEDO = mix(gem, mix(gem, ash_core * 0.55, 0.40), nk) * daynight_tint;
        ROUGHNESS = 0.045 + 0.03 * (1.0 - facet);
        METALLIC = 0.0;
        SPECULAR = 0.92;
        EMISSION = mix(day_emit, night_emit, nk);
    } else {
        // INSTANCE_COLOR.rgb 区分蓝 / 蓝紫两种晶体
        ALBEDO = base_color * tint * daynight_tint;
        ROUGHNESS = 0.12;
        METALLIC = 0.0;
        SPECULAR = 0.8;
        EMISSION = glow_color * tint * (0.35 + fres * 1.6) * glow * breathe;
    }
}

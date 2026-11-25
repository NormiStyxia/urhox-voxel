// W only. RGB = white blade / gold / accent, remainder = grip; A = face shade.
// UV.x remains 0 body, .35 core, 1 gem. UV.y = full weapon height 0..1.
// Opaque sapphire illusion: real cut normals + absorption + internal reflection.
// No screen sampling, alpha blending, axial white stripe or tiled facet noise.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
// Night readability (driven by WeaponRig from DayNight): at 1 a weak share of
// the albedo is self-lit and a cool rim traces the silhouette, so the weapon
// stays visible in the dark without glowing; existing glow is damped to match.
uniform float night_fill = 0.0;
uniform vec4 primary_color : source_color = vec4(0.885, 0.911, 0.928, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.878, 0.698, 0.325, 1.0);
uniform vec4 accent_color : source_color = vec4(0.236, 0.538, 0.855, 1.0);
uniform vec4 grip_color : source_color = vec4(0.08, 0.15, 0.36, 1.0);
uniform float gold_metal = 0.35;
uniform float metal_dark = 0.7;
uniform float metal_env = 1.0;
uniform float blade_rim = 0.5;
uniform float blade_glint = 0.7;
uniform float blade_emit = 0.2;
uniform float core_glow = 0.6;          // weak coloured floor, NOT a white core
uniform float crystal_amt = 1.0;        // blend of sapphire vs ordinary material
uniform float crystal_glow = 0.08;      // small base self-light only
uniform float sapphire_saturation = 0.88; // subtract this fraction of min RGB
uniform float sapphire_absorption = 2.0;  // optical density; higher = deeper
uniform float sapphire_depth = 0.043;     // reference half-thickness, metres
uniform float sapphire_deep = 0.18;       // linear darkest palette level
uniform float sapphire_mid = 0.62;        // linear middle palette level
uniform float sapphire_bright = 0.95;     // saturated internal-return level
uniform float sapphire_roughness = 0.09;  // polished dielectric surface
uniform float sapphire_internal = 0.32;   // two broad rear-plane returns
uniform float sapphire_reflection = 0.24; // coloured studio reflection strength
uniform float sapphire_highlight = 0.50;  // localized neutral surface glints
uniform float sapphire_fresnel = 0.18;    // grazing sky reflection, not white fill
uniform float flow_strength : hint_range(0.0, 2.0) = 0.7;
uniform float flow_speed = 0.10;          // sweep cycles/sec; full reset off blade
varying vec3 obj_pos;
varying vec3 obj_normal;
void vertex() {
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
void fragment() {
    float grip_w = clamp(1.0 - COLOR.r - COLOR.g - COLOR.b, 0.0, 1.0);
    vec3 base = primary_color.rgb * COLOR.r + secondary_color.rgb * COLOR.g + accent_color.rgb * COLOR.b + grip_color.rgb * grip_w;
    float gem_m = step(0.75, UV.x);
    float core_m = step(0.30, UV.x) * (1.0 - gem_m);
    // Include the ENTIRE .6r/.4b shoulder. Do not turn the b=1, glow=0
    // dark feather trim into sapphire. Keep all existing channel semantics.
    float shoulder_m = step(0.32, COLOR.b) * (1.0 - step(0.80, COLOR.b)) * step(0.50, COLOR.r);
    float cw = clamp(core_m + shoulder_m + gem_m, 0.0, 1.0) * clamp(crystal_amt, 0.0, 1.0);
    base = base * (1.0 - metal_dark * COLOR.g);
    METALLIC = gold_metal * COLOR.g;
    float ordinary_roughness = clamp(0.62 - 0.30 * COLOR.g - 0.50 * COLOR.b - 0.14 * COLOR.r + 0.18 * grip_w, 0.12, 0.8);
    ROUGHNESS = mix(ordinary_roughness, clamp(sapphire_roughness, 0.04, 0.35), cw);
    SPECULAR = mix(0.45, 0.72, cw);

    vec3 n = normalize(NORMAL);
    // Denominator guard also covers a camera exactly on this vertex.
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (dot(view_delta, view_delta) > 0.00000001) {
        v = normalize(view_delta);
    }
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    vec3 r = 2.0 * dot(n, v) * n - v;
    vec3 l = MAIN_LIGHT_DIRECTION;
    float rl = clamp(dot(r, l), 0.0, 1.0);
    float glint_wide = pow(rl, 18.0);
    float glint_tight = pow(rl, 60.0);
    float fres = pow(1.0 - ndv, 3.0);
    // Gold retains the previous faceted environment response.
    float up = r.y * 0.5 + 0.5;
    float sky = smoothstep(0.40, 0.46, up) * 0.55 + smoothstep(0.62, 0.68, up) * 0.45;
    vec3 gold = secondary_color.rgb;
    vec3 env = mix(gold * 0.10, gold * 1.0, sky) + gold * glint_wide * 0.6 + vec3(1.0, 0.96, 0.85) * glint_tight * 0.7;
    env = env + mix(gold, vec3(1.0), 0.5) * fres * 0.20;
    vec3 metal_light = COLOR.g * env * metal_env;

    // Normalize brightness FIRST. Dark palette presets keep their hue, not
    // their low value; subtract neutral contamination before building 3 tones.
    vec3 clean_accent = max(accent_color.rgb, vec3(0.0));
    float amax = max(max(clean_accent.r, clean_accent.g), clean_accent.b);
    vec3 hue = clean_accent / max(amax, 0.001);
    float neutral = min(min(hue.r, hue.g), hue.b);
    hue = max(hue - vec3(neutral * clamp(sapphire_saturation, 0.0, 0.98)), vec3(0.0));
    hue = hue / max(max(max(hue.r, hue.g), hue.b), 0.001);
    vec3 deep_tone = hue * hue * max(sapphire_deep, 0.0);
    vec3 mid_tone = mix(hue * hue, hue, 0.60) * max(sapphire_mid, 0.0);
    vec3 bright_tone = hue * max(sapphire_bright, 0.0);

    // Thickness and oblique path length absorb light. The centre is deeper,
    // never whiter. Rational Beer-Lambert approximation avoids exp intrinsics.
    float thickness = clamp(abs(obj_pos.z) / max(sapphire_depth, 0.001), 0.0, 1.0);
    float optical_path = thickness / max(ndv, 0.28);
    float transmission = 1.0 / (1.0 + max(sapphire_absorption, 0.0) * optical_path);
    float cut_facing = clamp(0.50 + obj_normal.x * 0.70 + obj_normal.y * 0.22, 0.0, 1.0);
    vec3 stone_body = mix(deep_tone, mid_tone, clamp(transmission * 1.25, 0.0, 1.0));

    // Two broad internal planes with a view-shifted secondary return. The real
    // flat normals/shade make each of the five long cuts respond differently.
    // No repeating cells, noise or lines painted along the middle of the blade.
    float internal_plane = 0.50 + obj_pos.x * 6.0 + (UV.y - 0.64) * 0.80 + obj_normal.x * 0.40;
    float rear_plane = smoothstep(0.44, 0.49, internal_plane + obj_normal.y * 1.8 + (COLOR.a - 0.90) * 0.50);
    float rear_echo = smoothstep(0.57, 0.63, internal_plane - ndv * 0.16 + obj_normal.x * 0.12);
    float return_amount = clamp(sapphire_internal, 0.0, 0.70) * (rear_plane * 0.65 + rear_echo * 0.35) * (0.30 + cut_facing * 0.70);
    stone_body = mix(stone_body, bright_tone, return_amount);
    ALBEDO = mix(base * COLOR.a, stone_body * (0.78 + COLOR.a * 0.22), cw);

    // Reflected sky is coloured; white is restricted to a small sun patch and
    // a thin, view-gated diagonal surface streak. Neither follows the axis.
    vec3 reflected_tone = mix(deep_tone, mid_tone, sky);
    float sun_patch = 1.0 - smoothstep(0.025, 0.13, abs(obj_pos.y - 1.08 + obj_pos.x * 1.8));
    float sun_flash = pow(rl, 96.0) * mix(sun_patch, 1.0, gem_m);
    float reflected_strip = 1.0 - smoothstep(0.018, 0.055, abs(r.x * 0.70 + r.y * 0.18 - r.z * 0.18 - 0.15));
    float diagonal_strip = 1.0 - smoothstep(0.002, 0.008, abs(obj_pos.x + obj_pos.y * 0.08 - 0.07 - obj_normal.x * 0.008));
    float strip_window = smoothstep(0.60, 0.72, obj_pos.y) * (1.0 - smoothstep(1.20, 1.35, obj_pos.y));
    float strip_flash = reflected_strip * diagonal_strip * strip_window * 0.35;
    vec3 surface_light = reflected_tone * max(sapphire_reflection, 0.0)
                       + mix(hue, vec3(1.0), 0.28) * fres * max(sapphire_fresnel, 0.0)
                       + vec3(1.0) * (sun_flash + strip_flash) * max(sapphire_highlight, 0.0);

    // White blade glow must not wash over the old pale-cyan shoulder band.
    float blade_w = clamp(COLOR.r, 0.0, 1.0) * (1.0 - cw);
    vec3 blade_light = blade_w * (accent_color.rgb * fres * blade_rim + vec3(1.0) * glint_tight * blade_glint + primary_color.rgb * blade_emit);

    // One slow oblique sweep. Face-normal/shade offsets break the flash at
    // actual cuts; amplitude is blue and low, without a permanent light strip.
    float head = fract(TIME * flow_speed) * 1.40 - 0.20;
    float sweep_phase = UV.y + obj_pos.x * 0.90 + (COLOR.a - 0.90) * 0.07 + obj_normal.x * 0.012;
    float sweep = 1.0 - smoothstep(0.008, 0.025, abs(sweep_phase - head));
    float sweep_gain = 0.25 + cut_facing * 0.75;
    float gem_pulse = 0.025 + 0.015 * sin(TIME * 1.2);
    vec3 flow_light = bright_tone * max(flow_strength, 0.0) * ((1.0 - gem_m) * sweep * sweep_gain * 0.16 + gem_m * gem_pulse);
    vec3 faint_body = stone_body * max(crystal_glow, 0.0) + mid_tone * max(core_glow, 0.0) * mix(0.035, 0.065, gem_m);
    EMISSION = metal_light + blade_light + cw * (surface_light + flow_light + faint_body);
    {
        vec3 nf_n = normalize(NORMAL);
        vec3 nf_v = normalize(CAMERA_POSITION_WORLD - VERTEX);
        float nf_rim = pow(1.0 - clamp(dot(nf_n, nf_v), 0.0, 1.0), 3.0);
        vec3 nf_base = max(ALBEDO, vec3(0.04));
        EMISSION = EMISSION * (1.0 - 0.45 * night_fill)
                 + night_fill * (nf_base * 0.16 + mix(nf_base, vec3(0.55, 0.65, 0.85), 0.5) * nf_rim * 0.22);
    }
}

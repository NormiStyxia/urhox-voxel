// Whole anime weapon. Vertex RGB = body / metal / accent weights; remainder (1-r-g-b) = grip.
// Alpha = planar shade. UV.x = emission mask (0 body, .3-.35 core strip, 1 gem); UV.y = height 0..1.
// Metal is faked per face (hard normals => crisp facets): procedural studio sky + sun glint + fresnel,
// so it reads as gold regardless of the zone's IBL. All tints follow the 4 colour uniforms.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 primary_color : source_color = vec4(0.885, 0.911, 0.928, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.878, 0.698, 0.325, 1.0);
uniform vec4 accent_color : source_color = vec4(0.236, 0.538, 0.855, 1.0);
uniform vec4 grip_color : source_color = vec4(0.08, 0.15, 0.36, 1.0);
uniform float gold_metal = 0.35;     // real PBR metallic on the metal channel
uniform float metal_dark = 0.7;      // darkens metal diffuse so the fake reflection carries the colour
uniform float metal_env = 1.0;       // strength of the faceted fake reflection on metal
uniform float blade_rim = 0.5;       // accent fresnel rim on the blade
uniform float blade_glint = 0.7;     // sun glint streak on the blade
uniform float blade_emit = 0.2;      // faint self-light so white stays luminous
uniform float core_glow = 0.6;       // constant emission on core strip / gems
uniform float crystal_amt = 1.0;     // faceted crystal look on the accent (b) channel: strip, cyan band, gems
uniform float crystal_glow = 0.6;    // self-light of the crystal facets
uniform float flow_strength : hint_range(0.0, 2.0) = 0.7;
uniform float flow_speed = 0.28;
varying vec3 obj_pos;
void vertex() {
    obj_pos = VERTEX;
}
void fragment() {
    float grip_w = clamp(1.0 - COLOR.r - COLOR.g - COLOR.b, 0.0, 1.0);
    vec3 base = primary_color.rgb * COLOR.r + secondary_color.rgb * COLOR.g + accent_color.rgb * COLOR.b + grip_color.rgb * grip_w;
    float cw = clamp(COLOR.b, 0.0, 1.0) * crystal_amt;
    base = mix(base, accent_color.rgb * 0.35, cw * 0.7);
    base = base * (1.0 - metal_dark * COLOR.g);
    ALBEDO = base * COLOR.a;
    METALLIC = gold_metal * COLOR.g;
    ROUGHNESS = clamp(0.62 - 0.30 * COLOR.g - 0.50 * COLOR.b - 0.14 * COLOR.r + 0.18 * grip_w, 0.12, 0.8);
    SPECULAR = 0.45;

    vec3 n = normalize(NORMAL);
    vec3 v = normalize(CAMERA_POSITION_WORLD - VERTEX);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    vec3 r = 2.0 * dot(n, v) * n - v;
    vec3 l = MAIN_LIGHT_DIRECTION;
    float rl = clamp(dot(r, l), 0.0, 1.0);
    float glint_wide = pow(rl, 18.0);
    float glint_tight = pow(rl, 60.0);
    float fres = pow(1.0 - ndv, 3.0);
    // Stylised studio: dark ground -> warm horizon -> bright sky, two hard steps.
    float up = r.y * 0.5 + 0.5;
    float sky = smoothstep(0.40, 0.46, up) * 0.55 + smoothstep(0.62, 0.68, up) * 0.45;
    vec3 gold = secondary_color.rgb;
    vec3 env = mix(gold * 0.10, gold * 1.0, sky) + gold * glint_wide * 0.6 + vec3(1.0, 0.96, 0.85) * glint_tight * 0.7;
    env = env + mix(gold, vec3(1.0), 0.5) * fres * 0.20;
    vec3 metal_light = COLOR.g * env * metal_env;


    // Crystal: object-space slanted prism cells, three tones (deep / accent / frosty),
    // bright cut lines, frosty grazing rim and sharp glints. Static on the sword, lit by the camera angle.
    vec2 q = vec2(obj_pos.x * 46.0 + obj_pos.y * 9.0, obj_pos.y * 7.0 - obj_pos.x * 14.0 + obj_pos.z * 40.0);
    vec2 cell = floor(q);
    float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float tone = floor(h * 3.0) / 2.0;
    vec2 fq = fract(q);
    float edge = 1.0 - smoothstep(0.0, 0.10, min(min(fq.x, 1.0 - fq.x), min(fq.y, 1.0 - fq.y)));
    vec3 deep_c = accent_color.rgb * 0.45;
    vec3 lite_c = mix(accent_color.rgb, vec3(1.0), 0.65);
    vec3 ccol = mix(deep_c, accent_color.rgb, clamp(tone * 2.0, 0.0, 1.0));
    ccol = mix(ccol, lite_c, clamp(tone * 2.0 - 1.0, 0.0, 1.0));
    ccol = ccol + lite_c * fres * 0.7 + vec3(1.0) * edge * 0.45 + vec3(1.0) * glint_tight * 1.2;
    vec3 crystal_light = cw * ccol * crystal_glow;

    // Blade: accent rim + glint, and a little self-light so the white band glows.
    float blade_w = clamp(COLOR.r, 0.0, 1.0);
    vec3 blade_light = blade_w * (accent_color.rgb * fres * blade_rim + vec3(1.0) * glint_tight * blade_glint + primary_color.rgb * blade_emit);

    // Travel entirely off the tip before resetting below the root. No seam flash.
    float head = fract(TIME * flow_speed) * 1.30 - 0.15;
    float band = 1.0 - smoothstep(0.025, 0.085, abs(UV.y - head));
    float pulse = 0.18 + 0.12 * (0.5 + 0.5 * sin(TIME * 2.4));
    float gem = step(0.75, UV.x);
    float spine = step(0.15, UV.x);
    float core = spine * (1.0 - gem);
    EMISSION = metal_light + blade_light + crystal_light
             + flow_strength * accent_color.rgb * (spine * band * 1.9 + gem * pulse)
             + core_glow * accent_color.rgb * (core * 0.35 + gem * 0.9);
}

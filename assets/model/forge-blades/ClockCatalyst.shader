// Time catalyst (generated mesh from art/weapon_gen/clock_catalyst_v6_blender.py).
// UV.x = kind/10: 0 star-metal band, 1 silver, 2 gold sparkle, 3 white numeral, 4 glass blade,
// 5 sapphire core (COLOR.a = facet brightness), 6 ice shard. Opaque: crystal depth comes from the cut
// normals, fresnel rim and a pulsing inner glow, no screen sampling (same approach as the wing-sword sapphire).
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 navy_color : source_color = vec4(0.050, 0.110, 0.360, 1.0);
uniform vec4 star_color : source_color = vec4(0.800, 0.900, 1.000, 1.0);
uniform vec4 silver_color : source_color = vec4(0.800, 0.840, 0.930, 1.0);
uniform vec4 gold_color : source_color = vec4(1.000, 0.760, 0.340, 1.0);
uniform vec4 glass_color : source_color = vec4(0.560, 0.740, 1.000, 1.0);
uniform vec4 sapphire_color : source_color = vec4(0.150, 0.420, 1.000, 1.0);
uniform float glow = 0.0;          // 0..1 cast intensity, driven by the caster (cached steps)
uniform float fade = 1.0;          // 0..1 materialise
varying vec3 obj_pos;
varying vec3 obj_normal;
void vertex() {
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
void fragment() {
    float kind = floor(UV.x * 10.0 + 0.5);
    float k_band = step(-0.5, kind) * (1.0 - step(0.5, kind));
    float k_silver = step(0.5, kind) * (1.0 - step(1.5, kind));
    float k_gold = step(1.5, kind) * (1.0 - step(2.5, kind));
    float k_num = step(2.5, kind) * (1.0 - step(3.5, kind));
    float k_glass = step(3.5, kind) * (1.0 - step(4.5, kind));
    float k_gem = step(4.5, kind) * (1.0 - step(5.5, kind));
    float k_ice = step(5.5, kind);

    vec3 n = normalize(NORMAL);
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (dot(view_delta, view_delta) > 0.00000001) {
        v = normalize(view_delta);
    }
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 3.0);
    vec3 r = 2.0 * dot(n, v) * n - v;
    float rl = clamp(dot(r, MAIN_LIGHT_DIRECTION), 0.0, 1.0);

    // star metal: deep navy with soft nebula patches and fine white stars fixed to the part
    float neb = 0.5 + 0.5 * sin(obj_pos.x * 31.0 + sin(obj_pos.y * 23.0 + obj_pos.z * 17.0) * 1.7)
                    * sin(obj_pos.y * 19.0 + obj_pos.x * 11.0);
    vec3 band = navy_color.rgb * (0.55 + 0.9 * neb);
    float star_cell = hash13(floor(obj_pos * 110.0));
    float star = step(0.975, star_cell);
    float twinkle = 0.55 + 0.45 * sin(TIME * 2.0 + star_cell * 60.0);
    vec3 band_emit = star_color.rgb * star * twinkle * 1.3 + navy_color.rgb * 0.22 * neb;

    // sapphire: per-facet blue level, icy grazing rim, sparse white glints, pulsing heart
    float facet = clamp(COLOR.a, 0.0, 1.0);
    vec3 deep = sapphire_color.rgb * 0.10;
    vec3 mid = sapphire_color.rgb * 0.75;
    vec3 lit = mix(sapphire_color.rgb, vec3(0.65, 0.88, 1.0), 0.6);
    vec3 gem = mix(deep, mid, smoothstep(0.0, 0.5, facet));
    gem = mix(gem, lit, smoothstep(0.45, 1.0, facet));
    gem = mix(gem, vec3(0.62, 0.84, 1.0), fres * 0.55);
    float glint = pow(rl, 48.0) * (0.4 + 0.6 * step(0.5, hash13(floor(obj_pos * 90.0))));
    float pulse = 0.5 + 0.5 * sin(TIME * 1.7);
    vec3 gem_emit = sapphire_color.rgb * (0.30 + 0.22 * pulse + 0.9 * glow) * (0.35 + 0.65 * facet) + vec3(1.0) * glint * 1.1;
    // Sapphire is mostly solid: facets and grazing light create the sense of
    // depth/transmission without reading as a hollow transparent glass ball.
    float gem_alpha_value = clamp(0.68 + facet * 0.18 + fres * 0.22 + glint * 0.12, 0.68, 1.0);

    // glass blade: pale blue that thickens toward the edges
    vec3 glass = mix(glass_color.rgb * 0.55, glass_color.rgb, fres + 0.25);
    vec3 glass_emit = glass_color.rgb * (0.45 + 0.8 * fres + 0.5 * glow);

    float metal_k = k_silver * 0.85 + k_band * 0.30 + k_gold * 0.6;
    ALBEDO = (band * k_band + silver_color.rgb * k_silver + gold_color.rgb * k_gold + vec3(0.96, 0.98, 1.0) * k_num
              + glass * k_glass + gem * k_gem + glass_color.rgb * k_ice) * fade;
    ROUGHNESS = clamp(0.38 * k_band + 0.25 * k_silver + 0.30 * k_gold + 0.50 * k_num + 0.10 * k_glass + 0.035 * k_gem + 0.10 * k_ice, 0.025, 0.9);
    METALLIC = metal_k;
    SPECULAR = 0.78 + 0.18 * k_gem;
    EMISSION = (band_emit * k_band + silver_color.rgb * 0.22 * k_silver
              + gold_color.rgb * (1.5 + 1.0 * glow) * k_gold + vec3(1.0, 1.0, 1.0) * (0.85 + 0.6 * glow) * k_num
              + glass_emit * k_glass + gem_emit * k_gem + glass_color.rgb * (0.9 + 0.4 * glow) * k_ice) * fade;
    ALPHA = mix(1.0, gem_alpha_value, k_gem) * fade;
}

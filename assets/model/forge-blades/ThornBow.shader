// Thorn-flower bow (generated mesh from art/weapon_gen/thornbow_blender.py).
// Vertex colour RGB = material channel: r bark wood, g lotus petal (UV.x 1 = glowing heart),
// b crystal (UV.x .35 = inner core, 1 = bow string), 0 = wrapped cloth grip. A = petal u / strap phase.
// Opaque on purpose: crystal depth is faked from the cut normals + a glowing core, no screen sampling.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 wood_color : source_color = vec4(0.13, 0.085, 0.22, 1.0);
uniform vec4 petal_base : source_color = vec4(0.93, 0.50, 0.86, 1.0);
uniform vec4 petal_tip : source_color = vec4(1.00, 0.95, 1.00, 1.0);
uniform vec4 crystal_color : source_color = vec4(0.52, 0.24, 0.98, 1.0);
uniform vec4 string_color : source_color = vec4(1.00, 0.42, 0.92, 1.0);
uniform vec4 grip_color : source_color = vec4(0.46, 0.32, 0.70, 1.0);
uniform float bend = 0.0;               // object-space: how far the limb tips pull toward the archer (-Z)
uniform float petal_glow = 0.22;
uniform float crystal_glow = 0.55;
uniform float string_glow = 1.5;
varying vec3 obj_pos;
varying vec3 obj_normal;
void vertex() {
    float k = clamp(abs(VERTEX.y) / 0.5, 0.0, 1.0);
    VERTEX.z -= bend * k * k;
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
void fragment() {
    float wood_w = COLOR.r;
    float petal_w = COLOR.g;
    float cry_w = COLOR.b;
    float grip_w = clamp(1.0 - COLOR.r - COLOR.g - COLOR.b, 0.0, 1.0);
    float emissive_m = step(0.9, UV.x);
    float core_m = step(0.30, UV.x) * (1.0 - emissive_m);
    float string_m = cry_w * emissive_m;
    float heart_m = petal_w * emissive_m;
    float crystal_m = cry_w * (1.0 - emissive_m);

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

    // bark: long dark fissures + a slow tone drift, never a flat brown
    float fissure = sin(obj_pos.y * 150.0 + obj_pos.x * 55.0 + obj_pos.z * 40.0) * 0.5 + 0.5;
    float drift = sin(obj_pos.y * 17.0 + obj_pos.x * 9.0) * 0.5 + 0.5;
    vec3 wood = wood_color.rgb * (0.62 + 0.30 * fissure + 0.28 * drift);
    vec3 wood_bleed = vec3(0.55, 0.30, 0.95) * 0.02 * (0.5 + 0.5 * drift);

    // petal: deep magenta at the base to pale pink tips, soft rim like thin tissue
    float u = clamp(COLOR.a, 0.0, 1.0);
    vec3 petal = mix(petal_base.rgb, petal_tip.rgb, smoothstep(0.05, 0.95, u));

    // cloth grip: alternating raised/tucked straps
    float strap = clamp(COLOR.a, 0.0, 1.0);
    vec3 cloth = grip_color.rgb * (0.55 + 0.75 * strap);

    // crystal: dark amethyst body that brightens toward the grazing edges (light bending
    // out of the cut), a glowing core, and tight sun glints per facet.
    vec3 chue = crystal_color.rgb;
    float cmax = max(max(chue.r, chue.g), chue.b);
    chue = chue / max(cmax, 0.001);
    vec3 deep = chue * chue * 0.20;
    float facet = clamp(0.5 + obj_normal.y * 0.5 + obj_normal.x * 0.35 + (obj_pos.z + obj_pos.y) * 3.0, 0.0, 1.0);
    vec3 stone = mix(deep, chue * 0.78, clamp(facet * 0.55 + (1.0 - ndv) * 0.55, 0.0, 1.0));
    float pulse = 0.5 + 0.5 * sin(TIME * 1.6);
    vec3 core = chue * (1.0 + 0.5 * pulse);

    vec3 base = wood * wood_w + petal * petal_w + stone * crystal_m + cloth * grip_w;
    base = mix(base, core * 0.6, core_m * cry_w);
    ALBEDO = base;
    ROUGHNESS = clamp(0.95 * wood_w + 0.55 * petal_w + 0.10 * crystal_m + 0.90 * grip_w + 0.30 * string_m, 0.08, 0.95);
    METALLIC = 0.0;
    // Low base specular: bright sky reflection washed the dark bark into lavender.
    SPECULAR = 0.05 * wood_w + 0.22 * petal_w + 0.10 * grip_w + 0.75 * crystal_m + 0.2 * string_m;

    vec3 emit = wood_bleed * wood_w + petal * petal_glow * petal_w * (0.4 + 0.6 * u * u)
              + vec3(1.0, 0.55, 0.95) * fres * 0.30 * petal_w
              + vec3(1.0, 0.82, 1.0) * heart_m * 1.7
              + core * crystal_glow * core_m * cry_w * 1.4
              + chue * crystal_glow * 0.10 * crystal_m
              + mix(chue, vec3(1.0), 0.35) * fres * 0.45 * crystal_m
              + vec3(1.0) * pow(rl, 70.0) * 0.9 * crystal_m
              + string_color.rgb * string_m * string_glow * (0.85 + 0.15 * sin(TIME * 3.0 + obj_pos.y * 9.0));
    EMISSION = emit;
}

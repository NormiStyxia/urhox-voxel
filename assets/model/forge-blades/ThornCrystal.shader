// Thorn-bow amethyst, translucent pass (ThornBowVisual splits the crystal triangles out).
// UV.x .35 = glowing inner core (drawn first), 0 = outer shell. Real alpha: the flowing sand,
// branches and sky show through the shell; edges and facet glints stay denser like polished gem.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 crystal_color : source_color = vec4(0.52, 0.24, 0.98, 1.0);
uniform float shell_alpha = 0.16;       // body opacity facing the camera
uniform float edge_alpha = 0.72;        // opacity at grazing angles
uniform float core_alpha = 0.60;
uniform float glow = 0.9;
varying vec3 obj_pos;
varying vec3 obj_normal;
void vertex() {
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
void fragment() {
    float core_m = step(0.30, UV.x);
    vec3 n = normalize(NORMAL);
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (dot(view_delta, view_delta) > 0.00000001) {
        v = normalize(view_delta);
    }
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.2);
    vec3 r = 2.0 * dot(n, v) * n - v;
    float rl = clamp(dot(r, MAIN_LIGHT_DIRECTION), 0.0, 1.0);
    vec3 hue = max(crystal_color.rgb, vec3(0.0));
    hue = hue / max(max(max(hue.r, hue.g), hue.b), 0.001);
    // each flat cut gets its own interior tone, so it reads as faceted stone and not a glass tube
    float facet = clamp(0.45 + obj_normal.y * 0.5 + obj_normal.x * 0.4 + (obj_pos.y + obj_pos.z) * 2.5, 0.0, 1.0);
    float pulse = 0.5 + 0.5 * sin(TIME * 1.6);
    vec3 shell_tone = mix(hue * hue * 0.30, hue * 0.85, facet);
    vec3 core_tone = hue * (1.1 + 0.5 * pulse);
    ALBEDO = mix(shell_tone, core_tone * 0.5, core_m);
    ROUGHNESS = 0.07;
    METALLIC = 0.0;
    SPECULAR = 0.8;
    EMISSION = mix(shell_tone * 0.35 + mix(hue, vec3(1.0), 0.4) * fres * 0.8 * glow,
                   core_tone * glow, core_m)
             + vec3(1.0) * pow(rl, 80.0) * 0.9 * (1.0 - core_m);
    float shell = mix(shell_alpha, edge_alpha, fres) + 0.12 * facet * (1.0 - core_m);
    ALPHA = clamp(mix(shell, core_alpha, core_m) + pow(rl, 80.0) * 0.5, 0.0, 0.95);
}

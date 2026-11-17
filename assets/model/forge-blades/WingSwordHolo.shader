// Wing sword projection layer for sheath/draw: the solid blade first turns
// into this blue hologram, then the hologram breaks into voxel-sized cells
// and blows away (reverse when forming). WingSwordVisual drives three params:
//   holo  0..1  projection brightness (0 = invisible, costs nothing visible)
//   cut   0..1  dissolve front; cells whose noise is below it are gone
// Same vertices as the solid blade; UV.y = full weapon height 0..1.
shader_type spatial;
render_mode shading_model_unlit, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 accent_color : source_color = vec4(0.236, 0.538, 0.855, 1.0);
uniform float holo = 0.0;
uniform float cut = 0.0;
uniform float cell = 38.0;          // cells per metre, ~voxel size of the blade
uniform float scan_speed = 2.5;
varying vec3 obj_pos;
varying vec3 obj_normal;
float hash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
void vertex() {
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
void fragment() {
    vec3 a = max(accent_color.rgb, vec3(0.0));
    vec3 hue = a / max(max(max(a.r, a.g), a.b), 0.001);
    vec3 ice = mix(hue, vec3(0.75, 0.95, 1.0), 0.55);
    // Dissolve noise: per-cell random, biased so the tip goes first.
    float n = hash3(floor(obj_pos * cell)) * 0.72 + (1.0 - UV.y) * 0.28;
    float alive = step(cut, n);
    float edge = (1.0 - smoothstep(0.0, 0.07, n - cut)) * step(0.001, cut);
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (dot(view_delta, view_delta) > 0.00000001) {
        v = normalize(view_delta);
    }
    float rim = pow(1.0 - abs(dot(normalize(NORMAL), v)), 2.0);
    float scan = 0.55 + 0.45 * step(0.5, fract(UV.y * 70.0 - TIME * scan_speed));
    vec3 body = ice * (0.18 + rim * 0.9) * scan;
    vec3 col = body + vec3(0.85, 0.97, 1.0) * edge * 1.6;
    ALBEDO = col;
    ALPHA = clamp(holo, 0.0, 1.0) * alive;
}

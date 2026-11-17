// Flowing sand around the thorn-bow crystal. Each grain is a tiny crossed quad; vertex() slides its
// centre along a spiral (per-grain phase in UV.x, stream id in UV.y, jitter in COLOR.rgb) so the
// geometry is built once and all motion runs on the GPU.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 head_color : source_color = vec4(0.90, 0.62, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(0.50, 0.24, 1.0, 1.0);
uniform float flow_speed = 0.20;        // cycles/sec along the crystal
uniform float strength = 1.0;
varying float s_v;
void vertex() {
    float s = fract(UV.x + TIME * flow_speed);
    float stream = UV.y;
    float phase = stream * 3.14159265 + 0.6;
    float a = phase + 7.853982 * s + 0.25 * sin(7.0 * s + phase);   // 1.25 turns
    float rad = 0.058 - 0.040 * s + 0.045 * s * s;
    // model +Z = target: the crystal runs from z=+0.01 (grip side) to the tip at +0.205
    float z = 0.010 + 0.195 * s;
    vec3 centre = vec3(cos(a) * rad, -0.012 - sin(a) * rad, z);
    centre += (COLOR.rgb - vec3(0.5)) * (0.010 + 0.032 * s * s);
    VERTEX = centre + VERTEX;
    s_v = s;
}
void fragment() {
    vec3 c = mix(head_color.rgb, tail_color.rgb, s_v);
    float fade = smoothstep(0.0, 0.08, s_v) * (1.0 - smoothstep(0.80, 1.0, s_v));
    ALBEDO = c * 2.4;
    ALPHA = clamp(fade * (0.35 + 0.65 * (1.0 - s_v)) * strength, 0.0, 1.0);
}

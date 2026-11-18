// Cast ripple of the time catalyst: a thin clock-dial ring (60 ticks, hour ticks heavier) that expands
// from the orb and fades. Geometry = flat annulus in the orb's front plane; UV.x = angle 0..1, UV.y = radial 0..1.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 ring_color : source_color = vec4(0.58, 0.80, 1.0, 1.0);
uniform vec4 gold_color : source_color = vec4(1.0, 0.80, 0.42, 1.0);
uniform float age = 1.0;              // 0 at the cast, 1 = gone
varying float a_v;
void vertex() {
    float k = 1.0 - pow(1.0 - clamp(age, 0.0, 1.0), 2.2);   // fast out, slow settle
    float s = mix(0.55, 2.0, k);
    VERTEX = vec3(VERTEX.xy * s, VERTEX.z);
    a_v = UV.x;
}
void fragment() {
    float tick60 = abs(fract(a_v * 60.0 + 0.5) - 0.5) * 2.0;
    float tick12 = abs(fract(a_v * 12.0 + 0.5) - 0.5) * 2.0;
    float edge = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
    float line = 1.0 - smoothstep(0.88, 0.97, UV.y);             // bright outer rim
    float t60 = (1.0 - smoothstep(0.0, 0.10, tick60 - 0.0)) * smoothstep(0.30, 0.6, UV.y);
    float t12 = (1.0 - smoothstep(0.0, 0.07, tick12)) * 1.0;
    float shape = max(max(smoothstep(0.80, 0.90, UV.y) * line, t60 * 0.55), t12 * edge * 0.9);
    vec3 c = mix(ring_color.rgb, gold_color.rgb, t12 * 0.7);
    float fade = pow(1.0 - clamp(age, 0.0, 1.0), 1.4);
    ALBEDO = c * 1.6;
    ALPHA = clamp(shape * fade, 0.0, 1.0);
}

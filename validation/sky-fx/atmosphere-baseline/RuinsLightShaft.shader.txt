shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform float strength = 1.0;
uniform float dusk = 0.0;
void fragment() {
    float edge = max(0.0, 1.0 - abs(UV.x * 2.0 - 1.0));
    float ends = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.70, 1.0, UV.y));
    float nearFade = smoothstep(2.0, 9.0, length(VERTEX - CAMERA_POSITION_WORLD));
    float breath = 0.76 + 0.24 * sin(TIME * 0.15 + VERTEX.x * 0.09 + VERTEX.z * 0.05);
    ALBEDO = mix(vec3(1.0, 0.94, 0.72), vec3(1.0, 0.65, 0.28), dusk);
    ALPHA = edge * edge * ends * nearFade * breath * strength * 0.035;
}

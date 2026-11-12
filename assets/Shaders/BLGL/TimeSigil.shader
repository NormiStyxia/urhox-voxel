shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint = vec4(0.45, 0.75, 1.0, 1.0);
uniform float fade = 1.0;
uniform float progress = 1.0;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float a = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
    float filled = step(a, progress);
    ALBEDO = tint.rgb * (0.7 + filled * 0.65);
    ALPHA = fade * tint.a * (0.3 + filled * 0.7);
}

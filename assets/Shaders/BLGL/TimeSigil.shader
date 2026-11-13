shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint = vec4(0.45, 0.75, 1.0, 1.0);
uniform float fade = 1.0;
uniform float progress = 1.0;
// use_tex=1：白底黑线的法阵图，亮度即不透明度；0：程序化圆环（蓄力范围 / 冲击波）。
uniform float use_tex = 0.0;
uniform sampler2D sigil_tex : filter_linear_mipmap, repeat_disable;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float a = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
    float filled = step(a, progress);
    if (use_tex > 0.5) {
        float ink = texture(sigil_tex, UV).r;
        ALBEDO = tint.rgb * (0.85 + ink * 0.6);
        ALPHA = fade * tint.a * smoothstep(0.08, 0.6, ink);
    } else {
        float r = length(p);
        float edge = smoothstep(0.93, 0.97, r) * (1.0 - smoothstep(0.985, 1.0, r));
        float inner = smoothstep(0.9, 0.93, r) * (1.0 - smoothstep(0.93, 0.95, r)) * 0.5;
        float body = (1.0 - step(1.0, r)) * 0.08;
        ALBEDO = tint.rgb * (0.7 + filled * 0.65);
        ALPHA = fade * tint.a * (edge + inner + body) * (0.3 + filled * 0.7);
    }
}

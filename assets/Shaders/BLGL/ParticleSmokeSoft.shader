// 程序化软烟粒子：无贴图，团状衰减 + 缓慢翻滚的明暗，半透明混合。
shader_type spatial;
render_mode shading_model_particle_unlit, blend_mix, depth_draw_never, cull_disabled;

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float n = sin(p.x * 5.0 + TIME * 0.9) * sin(p.y * 4.0 - TIME * 1.3);
    float r = length(p) + n * 0.15;
    float a = clamp(1.0 - smoothstep(0.2, 1.0, r), 0.0, 1.0);
    ALBEDO = COLOR.rgb * (0.85 + 0.15 * n);
    ALPHA = COLOR.a * a * a;
}

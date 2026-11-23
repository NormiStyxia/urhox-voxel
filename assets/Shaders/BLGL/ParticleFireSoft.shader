// 程序化软火焰/火星粒子：无贴图，圆形衰减 + 随时间流动的细噪边缘，叠加发光。
shader_type spatial;
render_mode shading_model_particle_unlit, blend_add, depth_draw_never, cull_disabled;

uniform float edge_noise = 0.12;   // 边缘抖动幅度（火舌感）
uniform float core_power = 1.6;    // 越大中心越集中

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    // 上半部收窄成火舌：越往上半径越小
    p.x *= 1.0 + max(-p.y, 0.0) * 0.55;
    float n = sin(p.x * 9.0 + TIME * 6.3) * sin(p.y * 7.0 - TIME * 8.1);
    float r = length(p) + n * edge_noise;
    float a = clamp(1.0 - smoothstep(0.1, 1.0, r), 0.0, 1.0);
    a = pow(a, core_power);
    ALBEDO = COLOR.rgb * a;
    ALPHA = COLOR.a * a;
}

// 星陨龙息体素光柱：套在 Models/Box.mdl（-0.5..0.5）上的方形截面光柱。
//   * 轴向（Y）分成一节节「光段」，每段亮度不同、沿轴向前推（scroll）→ 像一串方块在流动
//   * 截面方向用像素格量化：中心亮、边缘一格深色描边，硬边无柔光
//   * 两端各一段淡出
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 core_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform vec4 edge_color = vec4(0.6, 0.22, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float fade = 1.0;
uniform float scroll = 0.0;
uniform float beam_len = 10.0;   // 光柱长度（米），决定光段数量
uniform float seed = 0.0;

varying vec3 opos;

float h11(float n) { return fract(sin(n * 91.345 + seed * 7.1) * 47453.5453); }

void vertex() {
    opos = VERTEX;
}

void fragment() {
    // 截面：取所在面的两个横向坐标，量化成 6 格
    vec3 a = abs(opos);
    float lateral = max(a.x, a.z) * 2.0;           // 0 中心 .. 1 边
    float face = (a.x > a.z) ? opos.z : opos.x;    // 侧面上的横向坐标 -0.5..0.5
    float cellL = floor((face + 0.5) * 6.0);
    // 轴向光段：约 0.35m 一段，随时间前推
    float segLen = 0.35;
    float y = (opos.y + 0.5) * beam_len;
    float seg = floor(y / segLen - scroll * 18.0);
    float segB = 0.65 + 0.35 * h11(seg);
    float segStep = step(0.12, fract(y / segLen - scroll * 18.0)); // 段与段之间一条暗缝
    // 边缘一格描边
    float edge = step(0.5, abs(cellL - 2.5) - 1.5);
    vec3 col = mix(core_color.rgb * (1.0 + 0.4 * segB), edge_color.rgb, edge) * intensity;
    col *= mix(0.55, 1.0, segStep) * segB;
    // 端点淡出：前后各 4% 长度，按段量化
    float u = opos.y + 0.5;
    float ends = step(0.03, u) * step(u, 0.97);
    float aOut = fade * ends * mix(0.9, 1.0, segStep);
    // 逐格抖动显隐
    float n = h11(seg * 13.0 + cellL);
    if (n > fade * 1.1 || aOut < 0.01) discard;
    ALBEDO = col;
    ALPHA = clamp(aOut, 0.0, 1.0);
}

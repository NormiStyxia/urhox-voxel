// 星陨龙息体素光柱：套在 Models/Box.mdl（-0.5..0.5）上。
//   * 轴向（Y）切成一节节光段，沿光束方向流动，段与段之间留暗缝
//   * 截面方向量化成像素格：中心白金高光、往外过渡到主色、最外一格深紫描边
//   * 视线掠射的侧面更透（菲涅尔反向），正面看像一根实心光柱，侧面看像能量体
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 core_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 edge_color = vec4(0.6, 0.22, 1.0, 1.0);
uniform vec4 dark_color = vec4(0.12, 0.02, 0.25, 1.0);
uniform float intensity = 3.0;
uniform float fade = 1.0;
uniform float scroll = 0.0;
uniform float beam_len = 10.0;
uniform float seed = 0.0;
uniform float cells = 8.0;

varying vec3 opos;

float h11(float n) { return fract(sin(n * 91.345 + seed * 7.1) * 47453.5453); }

void vertex() {
    opos = VERTEX;
}

void fragment() {
    vec3 a = abs(opos);
    float face = (a.x > a.z) ? opos.z : opos.x;
    // 截面像素格：0 = 中心，1 = 边
    float cl = floor((face + 0.5) * cells);
    float lat = abs((cl + 0.5) / cells - 0.5) * 2.0;
    float y = (opos.y + 0.5) * beam_len;
    float segLen = 0.4;
    float segF = y / segLen - scroll * 16.0;
    float seg = floor(segF);
    float gap = step(0.14, fract(segF));
    float segB = 0.75 + 0.25 * h11(seg);
    vec3 col;
    if (lat > 0.8) col = dark_color.rgb;
    else if (lat > 0.5) col = edge_color.rgb * intensity * 0.8;
    else if (lat > 0.22) col = mix(edge_color.rgb, core_color.rgb, 0.5) * intensity;
    else col = core_color.rgb * intensity * 1.3;
    col *= mix(0.45, 1.0, gap) * segB;
    float u = opos.y + 0.5;
    float ends = step(0.02, u) * step(u, 0.985);
    // 侧面掠射时边缘格更透
    float alpha = fade * ends * ((lat > 0.8) ? 0.75 : 0.95);
    float n = h11(seg * 13.0 + cl);
    if (n > fade * 1.1 || alpha < 0.02) discard;
    ALBEDO = col;
    ALPHA = alpha;
}

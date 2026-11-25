// 剑特效面片：一张扁平的卡通刀光，硬边、几档蓝白色阶、沿挥砍方向拉长的条纹。
// 顶点色不是颜色而是数据：r = 寿命进度 0..1，g = 形状（0 刀光带 / 0.5 尖刺爆闪 / 1 梭形薄片），
// b = 随机种子，a = 亮度。刀光带的 UV.x 是沿轨迹的米数，UV.y 是 0 内缘 .. 1 外缘。
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform float glow = 1.9;
uniform float cells = 22.0;   // 横向像素格数：边缘按格子阶梯走，不做柔边

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = h21(i);
    float b = h21(i + vec2(1.0, 0.0));
    float c = h21(i + vec2(0.0, 1.0));
    float d = h21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 四档色阶：白芯 → 冰蓝 → 蓝 → 深蓝
// 四档色阶：白芯 → 冰蓝 → 蓝 → 深蓝。过渡留宽度——硬 step 在面片正对镜头、
// 带宽整个铺开时，色阶交界会读成一道折棱
vec3 ramp(float k, float power) {
    vec3 col = vec3(0.02, 0.10, 0.55);
    col = mix(col, vec3(0.08, 0.34, 1.0), smoothstep(0.18, 0.32, k));
    col = mix(col, vec3(0.45, 0.78, 1.0), smoothstep(0.46, 0.62, k));
    col = mix(col, vec3(1.0) * (1.0 + (glow - 1.0) * power), smoothstep(0.74, 0.88, k));
    return col;
}

void fragment() {
    float age = COLOR.r;
    float shape = COLOR.g;
    float seed = COLOR.b;
    float power = COLOR.a;
    float keep = 0.0;
    float k = 0.0;
    if (shape < 0.25) {
        // 刀光带：出生时整片发白，前 40% 寿命保持完整；之后内侧被条纹撕开，往外缘退，最后只剩外缘一线
        float t = clamp((age - 0.4) / 0.6, 0.0, 1.0);
        float s = floor(UV.x * 36.0) / 36.0;
        float v = (floor(UV.y * cells) + 0.5) / cells;
        float streak = vnoise(vec2(s * 2.4 + seed * 17.0, v * 6.0)) * 0.7
                     + vnoise(vec2(s * 7.0 + seed * 5.0, v * 13.0 + 3.1)) * 0.3;
        keep = smoothstep(-0.03, 0.03, streak * 0.55 + v * 0.9 - (0.12 + t * 1.33));
        k = v + (streak - 0.5) * 0.28 - t * 0.45 + (1.0 - smoothstep(0.0, 0.14, age)) * 0.6;
        // 最外一格压成蓝色描边，白芯在浅色地面上才读得出来
        k = mix(k, 0.3, step(1.0 - 1.5 / cells, v));
    } else if (shape < 0.75) {
        // 尖刺爆闪：长短交替的尖角，寿命后段从中心向外掏空
        float c = cells * 0.75;
        vec2 p = (floor((UV * 2.0 - 1.0) * c) + 0.5) / c;
        float r = length(p);
        float turn = atan(p.y, p.x) / 6.2831853 * 8.0 + seed;
        float w = abs(fract(turn) - 0.5) * 2.0;
        float len = mix(0.55, 1.0, h21(vec2(floor(turn), seed * 9.0 + 1.7)));
        float edge = mix(0.30, len, pow(w, 1.6 + age * 4.0));
        float hole = max(0.0, age * 1.7 - 0.6) * edge;
        keep = step(r, edge) * step(hole, r);
        k = 1.0 - r / max(edge, 0.001) * 0.85 - age * 0.25;
    } else {
        // 梭形薄片：头粗尾尖，寿命越大越细，从尾部先消失
        float u = (floor(UV.x * cells * 2.0) + 0.5) / (cells * 2.0);
        float w = abs(UV.y * 2.0 - 1.0);
        float body = pow(1.0 - abs(u * 2.0 - 1.0), 0.7) * (1.0 - age * age);
        keep = step(w, body) * step(age * 1.25 - 0.25, u);
        k = 1.0 - w / max(body, 0.001) * 0.9;
    }
    if (keep < 0.5) discard;
    ALBEDO = ramp(k, power);
    ALPHA = 0.95;
}

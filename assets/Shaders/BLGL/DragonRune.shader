// 龙吐息像素法阵：方形面片上程序化画法阵，再量化成低分辨率像素格。
//   * UV 先量化到 grid × grid 的像素格，每格只取一次颜色 → 硬边像素、阶梯线条
//   * 线宽以「格」为单位（≥1 格），图形只用横 / 竖 / 45° / 星形折线，像手画的像素图
//   * 4 阶调色：深色描边 / 主色 / 亮色 / 白色高光；不做柔光
//   * reveal：逐像素随机抖动显隐（dither），先外环、再内部；fade 同样用抖动
//   * glitch：喷射时整体偏移 1 格 + 个别像素闪烁
// style 0 = 霜焰（中号）、1 = 星陨（大号）、2 = 冲击环（ring_r 为半径 0..1）
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 dark_color = vec4(0.03, 0.08, 0.25, 1.0);
uniform vec4 main_color = vec4(0.2, 0.55, 1.0, 1.0);
uniform vec4 light_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform vec4 hot_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.6;   // 发光倍数（亮色、高光乘它，描边不乘）
uniform float fade = 1.0;
uniform float reveal = 1.0;
uniform float spin = 0.0;        // 外圈角度（弧度，已在 Lua 侧按步进量化）
uniform float spin2 = 0.0;       // 内部图形角度
uniform float pulse = 0.0;
uniform float glitch = 0.0;      // 0..1 抖动强度
uniform float style = 0.0;
uniform float ring_r = 0.8;
uniform float grid = 64.0;       // 像素格数
uniform float seed = 0.0;
uniform float alpha_scale = 1.0;

const float K_PI = 3.14159265;
const float K_TAU = 6.2831853;

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 rot2(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * t);
}

float star_dist(vec2 p, int n, int k, float R, float a0) {
    float d = 1e3;
    for (int i = 0; i < 9; i++) {
        if (i < n) {
            float a = a0 + K_TAU * float(i) / float(n);
            float b = a0 + K_TAU * float(i + k) / float(n);
            d = min(d, seg_dist(p, vec2(cos(a), sin(a)) * R, vec2(cos(b), sin(b)) * R));
        }
    }
    return d;
}

// 像素符文带：每格一个 5x5 的随机点阵符文（逐像素查表，天然像素化）
float rune_band(vec2 p, float r0, float r1, float count, float rot, float px) {
    float r = length(p);
    if (r < r0 || r > r1) return 0.0;
    float a = atan(p.y, p.x) + rot;
    float cell = K_TAU / count;
    float ci = floor(a / cell);
    float fa = fract(a / cell);
    // 格子内坐标 0..1，两边各留 15% 空隙
    float u = (fa - 0.15) / 0.7;
    float v = (r - r0) / (r1 - r0);
    if (u < 0.0 || u > 1.0) return 0.0;
    vec2 g = floor(vec2(u, v) * 5.0);
    // 5x5 点阵：中竖总是亮，其余按哈希
    float on = step(0.52, h21(g + ci * 7.13 + seed));
    if (g.x == 2.0) on = max(on, step(0.25, h21(vec2(ci, g.y) + 3.1)));
    if (g.y == 0.0 || g.y == 4.0) on *= step(0.5, h21(vec2(ci * 1.7, g.x)));
    return on;
}

// 返回：x = 主线条（主色）、y = 亮线（亮色）、z = 高光核
vec3 shape(vec2 p, float px) {
    float r = length(p);
    vec3 m = vec3(0.0);
    float w = px * 0.75;     // 1 格线宽
    float w2 = px * 1.25;    // 2 格线宽
    float rvIn = smoothstep(0.35, 0.85, reveal);
    float rvCore = smoothstep(0.6, 1.0, reveal);
    if (style < 0.5) {
        // 霜焰：双外环 + 像素符文带 + 六芒星 + 内六边形 + 雪花辐条
        m.x += step(abs(r - 0.955), w2) + step(abs(r - 0.87), w);
        m.y += rune_band(rot2(p, spin), 0.885, 0.94, 22.0, 0.0, px);
        vec2 pi = rot2(p, -spin2);
        m.y += step(star_dist(pi, 6, 2, 0.84, K_PI / 6.0), w) * rvIn;
        m.x += step(star_dist(rot2(p, spin2 * 1.5), 6, 1, 0.48, 0.0), w) * rvIn;
        m.x += step(abs(r - 0.5), w) * rvIn;
        float ang = atan(pi.y, pi.x);
        float sec = K_TAU / 6.0;
        float la = (fract(ang / sec + 0.5) - 0.5) * sec;
        vec2 q = vec2(cos(la), sin(la)) * r;
        float sp = seg_dist(q, vec2(0.12, 0.0), vec2(0.44, 0.0));
        sp = min(sp, seg_dist(q, vec2(0.28, 0.0), vec2(0.36, 0.08)));
        sp = min(sp, seg_dist(q, vec2(0.28, 0.0), vec2(0.36, -0.08)));
        m.y += step(sp, w) * rvCore;
        // 中心：菱形核
        float dm = abs(p.x) + abs(p.y);
        m.z += step(dm, 0.1 + 0.04 * pulse) * rvCore;
        m.x += step(abs(dm - 0.17), w) * rvCore;
    } else if (style < 1.5) {
        // 星陨：粗外环 + 刻度环 + 符文带 + 双七芒星 + 七轨道圆 + 双方块 + 中心之眼
        m.x += step(abs(r - 0.965), w2) + step(abs(r - 0.79), w) + step(abs(r - 0.42), w);
        m.y += step(abs(r - 0.925), w);
        m.y += rune_band(rot2(p, spin), 0.83, 0.905, 34.0, 0.0, px);
        float ta = atan(p.y, p.x) - spin * 0.5;
        float tc = abs(fract(ta / (K_TAU / 36.0) + 0.5) - 0.5) * (K_TAU / 36.0) * r;
        m.x += step(tc, w) * step(0.80, r) * step(r, 0.83);
        m.x += step(star_dist(rot2(p, -spin2), 7, 3, 0.79, K_PI / 2.0), w) * rvIn;
        m.y += step(star_dist(rot2(p, spin2 * 0.6), 7, 2, 0.79, K_PI / 2.0), w) * rvIn;
        float orb = 1e3;
        for (int i = 0; i < 7; i++) {
            float a = -spin2 + K_PI / 2.0 + K_TAU * float(i) / 7.0;
            vec2 c = vec2(cos(a), sin(a)) * 0.79;
            orb = min(orb, abs(length(p - c) - 0.06));
            m.z += step(length(p - c), 0.025) * rvIn;
        }
        m.y += step(orb, w) * rvIn;
        vec2 pk = rot2(p, spin2 * 1.8);
        float sq = min(max(abs(pk.x), abs(pk.y)), (abs(pk.x) + abs(pk.y)) * 0.7071);
        m.x += step(abs(sq - 0.3), w) * rvCore;
        m.y += rune_band(rot2(p, -spin * 1.5), 0.2, 0.27, 12.0, 0.0, px) * rvCore;
        // 中心之眼：竖瞳
        float eye = length(vec2(p.x * 2.4, p.y));
        m.z += step(eye, 0.12 + 0.05 * pulse) * rvCore;
        m.x += step(abs(r - 0.15), w) * rvCore;
    } else {
        // 冲击环：两格宽的像素环 + 内侧随机碎点
        float a = atan(p.y, p.x);
        float jag = (h21(vec2(floor(a * 24.0), seed)) - 0.5) * 0.04;
        float d = abs(r - ring_r - jag);
        m.y += step(d, w2 * 1.4);
        m.x += step(d, w2 * 2.6) * (1.0 - step(d, w2 * 1.4));
        m.z += step(d, w) * step(0.6, h21(floor(p / px) + seed));
        float inner = step(r, ring_r) * step(ring_r - 0.25, r);
        m.x += inner * step(0.93, h21(floor(p / px) * 1.7 + floor(seed)));
    }
    return m;
}

void fragment() {
    // 像素量化：每个像素格只在中心采样一次
    float g = grid;
    vec2 cellUV = floor(UV * g);
    // glitch：整体偏移 1 格（每 ~0.08 秒换一次）
    float gt = floor(TIME * 12.0);
    vec2 jitter = (vec2(h21(vec2(gt, 1.0)), h21(vec2(gt, 2.0))) - 0.5) * 2.0;
    cellUV += floor(jitter * glitch * 1.6 + 0.5);
    vec2 p = ((cellUV + 0.5) / g - 0.5) * 2.0;
    float px = 2.0 / g;
    float r = length(p);
    if (r > 1.0) discard;

    vec3 m = shape(p, px);
    float mainM = clamp(m.x, 0.0, 1.0);
    float lightM = clamp(m.y, 0.0, 1.0);
    float hotM = clamp(m.z, 0.0, 1.0);

    // 外环按角度写出（笔头那一格最亮），内部由 shape 自己按 reveal 分级出现
    float ang01 = fract(atan(p.y, p.x) / K_TAU + 0.25);
    float n = h21(cellUV + seed * 3.7);
    float drawn = step(ang01, reveal * 1.02) ;
    float headCell = step(abs(ang01 - reveal), 0.012) * step(reveal, 0.995);
    // 逐像素抖动显隐
    float vis = drawn * step(n, fade * 1.05);
    // 闪烁：喷射时随机像素熄灭 / 变亮
    float fl = h21(cellUV + gt * 1.31);
    vis *= 1.0 - step(1.0 - 0.18 * glitch, fl);
    float flare = step(1.0 - 0.06 * (glitch + pulse * 0.5), h21(cellUV * 1.9 + gt));

    float any = max(max(mainM, lightM), hotM);
    // 描边：任意线条周围一格画深色（通过邻格采样近似：线条像素本身以外，距离 1 格内）
    vec3 m2 = shape(p + vec2(px, 0.0), px) + shape(p - vec2(px, 0.0), px)
        + shape(p + vec2(0.0, px), px) + shape(p - vec2(0.0, px), px);
    float outline = step(0.5, m2.x + m2.y + m2.z) * (1.0 - step(0.5, any));

    vec3 col = dark_color.rgb;
    float a = 0.0;
    if (any > 0.5) {
        col = main_color.rgb * intensity;
        if (lightM > 0.5) col = light_color.rgb * intensity;
        if (hotM > 0.5 || flare > 0.5 || headCell > 0.5) col = hot_color.rgb * intensity * 1.4;
        col *= 1.0 + 0.35 * pulse;
        a = 1.0;
    } else if (outline > 0.5) {
        a = 0.85;
    } else {
        discard;
    }
    a *= vis * alpha_scale;
    if (a < 0.01) discard;
    ALBEDO = col;
    ALPHA = a;
}

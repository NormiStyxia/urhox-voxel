// 龙吐息法阵：在一张方形面片上程序化画出法阵（UV 0..1，圆心在中央）。
// style 0 = 霜焰（中号）：六芒星 + 雪花辐条 + 符文环
// style 1 = 星陨（大号）：双层七芒星 + 刻度环 + 七个轨道小圆 + 中心之眼
// style 2 = 冲击环：一圈带噪声的柔光环（ring_r 为半径，0..1）
// 混合：预乘 Alpha。RGB 直接叠加发光，ALPHA 轻微压暗背后，白色雪地上线条也清楚。
shader_type spatial;
render_mode shading_model_unlit, blend_premul_alpha, cull_disabled, depth_draw_never;

uniform vec4 main_color = vec4(0.35, 0.75, 1.0, 1.0);   // 线性 HDR 颜色
uniform vec4 accent_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float fade = 1.0;      // 整体淡入淡出
uniform float reveal = 1.0;    // 0..1 绘制进度：外环按角度画出，内部图形随后浮现
uniform float spin = 0.0;      // 外圈旋转（弧度），内圈反向
uniform float spin2 = 0.0;     // 内部图形旋转（弧度）
uniform float pulse = 0.0;     // 中心光 / 线条脉冲 0..1
uniform float style = 0.0;
uniform float ring_r = 0.8;
uniform float darken = 0.35;

const float PI = 3.14159265;
const float TAU = 6.2831853;

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }

float stroke(float d, float w, float px) {
    return 1.0 - smoothstep(w - px, w + px, abs(d));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * t);
}

vec2 rot2(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// 星形多边形 {n/k}：到所有边的最短距离
float star_dist(vec2 p, int n, int k, float R, float a0) {
    float d = 1e3;
    for (int i = 0; i < 9; i++) {
        if (i < n) {
            float a = a0 + TAU * float(i) / float(n);
            float b = a0 + TAU * float(i + k) / float(n);
            d = min(d, seg_dist(p, vec2(cos(a), sin(a)) * R, vec2(cos(b), sin(b)) * R));
        }
    }
    return d;
}

// 符文带：r0..r1 之间均分 count 格，每格一个由几笔组成的随机符文。返回到笔画的距离（以带高为单位）
float rune_dist(vec2 p, float r0, float r1, float count, float rot) {
    float r = length(p);
    float a = atan(p.y, p.x) + rot;
    float cell = TAU / count;
    float ci = floor(a / cell);
    float fa = fract(a / cell);
    float h = hash1(ci + 17.0 * count);
    float bh = r1 - r0;
    vec2 q = vec2((fa - 0.5) * cell * r / bh, (r - r0) / bh - 0.5);
    float d = seg_dist(q, vec2(0.0, -0.32), vec2(0.0, 0.32));
    if (h < 0.25) {
        d = min(d, seg_dist(q, vec2(-0.2, 0.08), vec2(0.2, 0.08)));
    } else if (h < 0.5) {
        d = min(d, seg_dist(q, vec2(-0.2, -0.08), vec2(0.0, 0.2)));
        d = min(d, seg_dist(q, vec2(0.0, 0.2), vec2(0.2, -0.08)));
    } else if (h < 0.75) {
        d = min(d, seg_dist(q, vec2(0.0, 0.0), vec2(0.2, 0.26)));
        d = min(d, seg_dist(q, vec2(0.0, -0.1), vec2(-0.2, -0.3)));
    } else {
        d = min(d, abs(length(q - vec2(0.2, 0.05)) - 0.07));
        d = min(d, seg_dist(q, vec2(-0.2, -0.22), vec2(0.0, -0.22)));
    }
    // 格子之间留空
    return (abs(q.x) > 0.42) ? 1e3 : d;
}

void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float r = length(p);
    float px = max(fwidth(r), 1e-4) * 1.2;
    float ang01 = fract(atan(p.y, p.x) / TAU + 0.25 + spin / TAU);

    // 外环按角度画出（带一个亮的笔头），内部图形在 reveal 后半段浮现
    float rv = 1.0 - smoothstep(reveal - 0.012, reveal + 0.012, ang01);
    float head = exp(-pow((ang01 - reveal) * 40.0, 2.0)) * step(reveal, 0.999) * step(0.001, reveal);
    float rvIn = smoothstep(0.35, 0.85, reveal);
    float rvCore = smoothstep(0.6, 1.0, reveal);

    float mMain = 0.0;
    float mAcc = 0.0;
    float glow = 0.0;

    if (style < 0.5) {
        // ---------------- 霜焰
        float rings = stroke(r - 0.965, 0.012, px) + stroke(r - 0.895, 0.007, px) + stroke(r - 0.52, 0.008, px);
        float rd = rune_dist(p, 0.905, 0.955, 26.0, spin) * 0.05;
        float runes = stroke(rd, 0.0024, px);
        mMain += (rings + runes) * rv;
        mMain += head * 2.0 * smoothstep(1.02, 0.86, r) * smoothstep(0.84, 0.9, r);
        vec2 pi = rot2(p, -spin2);
        float hexa = stroke(star_dist(pi, 6, 2, 0.86, PI / 6.0), 0.008, px);
        float hexb = stroke(star_dist(rot2(p, spin2 * 1.6), 6, 1, 0.5, 0.0), 0.006, px);
        mAcc += hexa * rvIn;
        mMain += hexb * rvIn;
        // 雪花辐条 + 分叉
        float ang = atan(pi.y, pi.x);
        float sec = TAU / 6.0;
        float la = (fract(ang / sec + 0.5) - 0.5) * sec;
        vec2 q = vec2(cos(la), sin(la)) * r;
        float sp = seg_dist(q, vec2(0.14, 0.0), vec2(0.48, 0.0));
        sp = min(sp, seg_dist(q, vec2(0.3, 0.0), vec2(0.38, 0.07)));
        sp = min(sp, seg_dist(q, vec2(0.3, 0.0), vec2(0.38, -0.07)));
        sp = min(sp, seg_dist(q, vec2(0.4, 0.0), vec2(0.45, 0.04)));
        sp = min(sp, seg_dist(q, vec2(0.4, 0.0), vec2(0.45, -0.04)));
        mAcc += stroke(sp, 0.006, px) * rvCore;
        mMain += stroke(r - 0.14, 0.006, px) * rvCore;
        glow = exp(-r * r * 26.0) * (0.35 + pulse) * rvCore;
    } else if (style < 1.5) {
        // ---------------- 星陨
        float rings = stroke(r - 0.975, 0.011, px) + stroke(r - 0.935, 0.005, px)
            + stroke(r - 0.80, 0.008, px) + stroke(r - 0.765, 0.004, px) + stroke(r - 0.42, 0.007, px);
        float rd = rune_dist(p, 0.94, 0.97, 40.0, spin) * 0.03;
        float runes = stroke(rd, 0.0018, px);
        // 刻度环：72 条短刻度，每 9 条一条长刻度
        float ta = atan(p.y, p.x) - spin * 0.5;
        float tc = fract(ta / (TAU / 72.0) + 0.5) - 0.5;
        float tIdx = floor(ta / (TAU / 72.0) + 0.5);
        float longT = (mod(tIdx, 9.0) < 0.5) ? 1.0 : 0.0;
        float tickR = mix(0.86, 0.82, longT);
        float tick = stroke(tc * TAU / 72.0 * r, 0.004, px) * step(tickR, r) * step(r, 0.925);
        mMain += (rings + runes + tick) * rv;
        mMain += head * 2.0 * smoothstep(1.02, 0.9, r) * smoothstep(0.88, 0.93, r);
        float s73 = stroke(star_dist(rot2(p, -spin2), 7, 3, 0.765, PI / 2.0), 0.007, px);
        float s72 = stroke(star_dist(rot2(p, spin2 * 0.6), 7, 2, 0.765, PI / 2.0), 0.005, px);
        mMain += s73 * rvIn;
        mAcc += s72 * rvIn;
        // 七个顶点上的轨道小圆
        float orb = 1e3;
        for (int i = 0; i < 7; i++) {
            float a = -spin2 + PI / 2.0 + TAU * float(i) / 7.0;
            orb = min(orb, abs(length(p - vec2(cos(a), sin(a)) * 0.765) - 0.055));
        }
        mAcc += stroke(orb, 0.006, px) * rvIn;
        // 内层：双方块 + 中心之眼
        vec2 pk = rot2(p, spin2 * 1.8);
        float sq = min(star_dist(pk, 4, 1, 0.4, 0.0), star_dist(pk, 4, 1, 0.4, PI / 4.0));
        mMain += stroke(sq, 0.005, px) * rvCore;
        float rd2 = rune_dist(p, 0.2, 0.27, 16.0, -spin * 1.5) * 0.07;
        mAcc += stroke(rd2, 0.003, px) * rvCore;
        mMain += (stroke(r - 0.13, 0.008, px) + stroke(r - 0.29, 0.004, px)) * rvCore;
        glow = exp(-r * r * 30.0) * (0.4 + 1.2 * pulse) * rvCore;
    } else {
        // ---------------- 冲击环
        float a = atan(p.y, p.x);
        float n = 0.75 + 0.25 * sin(a * 9.0 + spin * 3.0) * sin(a * 5.0 - spin * 2.0);
        float w = 0.03 + 0.05 * (1.0 - ring_r);
        float ring = exp(-pow((r - ring_r) / w, 2.0)) * n;
        float inner = smoothstep(ring_r, 0.0, r) * 0.18 * (1.0 - ring_r);
        mMain += ring;
        mAcc += inner;
    }

    // 外缘渐隐，面片边角不留硬边
    float edge = 1.0 - smoothstep(0.985, 1.0, r);
    float m = (mMain + mAcc) * edge;
    vec3 col = (main_color.rgb * mMain + accent_color.rgb * mAcc) * (1.0 + 0.6 * pulse) * edge
        + accent_color.rgb * glow;
    col *= intensity * fade;
    ALBEDO = col;
    ALPHA = clamp(m * darken * fade, 0.0, 1.0);
}

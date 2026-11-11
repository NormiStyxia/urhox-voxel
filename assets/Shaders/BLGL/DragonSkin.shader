// 龙鳞外皮（配合 DragonSkin.lua 的倒角网格）
//   UV.x = 表面类型：0 鱼鳞，1 腹甲横纹，2 素面（眼、爪、口、角刺）；UV.y = 该部件的体素边长
//   COLOR = 调色板颜色（sRGB），COLOR.a = 自发光强度
// 鱼鳞：在部件局部空间做三向投影，行距 1、相邻行错开半格的圆形鳞片，上一排盖住下一排（屋瓦式），
// 露出每片的下缘弧线。每片鳞是一个小穹顶：中央略亮、边缘一圈暗线、被上片压住处有阴影；
// 高度场再用屏幕导数扰动法线，鳞片在光下有起伏和高光，但不改外形。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;

uniform float scale_size = 2.6;   // 鳞片行距 = 体素边长 × 该值
uniform float scale_amount = 1.0; // 鳞片明暗强度
uniform float bump_amount = 1.0;  // 鳞片起伏强度

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
    obj_pos = VERTEX;
    obj_nrm = NORMAL;
}

// 第 r 行里离 p 最近的鳞片中心的距离（纵向略压扁，鳞片偏宽）
float row_dist(vec2 p, float r) {
    float off = 0.5 * mod(r, 2.0);
    float cx = floor(p.x - off + 0.5) + off;
    return length(vec2(p.x - cx, (p.y - r) * 1.2));
}

// 返回 vec2(高度, 遮蔽)：高度 1 = 鳞片中央，0 = 边缘，负值 = 被上片压住的阴影
vec2 fish_scale(vec2 p) {
    float R = 0.82;
    float r1 = floor(p.y) + 1.0;
    float d1 = row_dist(p, r1);
    float d0 = row_dist(p, r1 - 1.0);
    float in1 = step(d1, R);
    float dome1 = 1.0 - d1 / R;
    float dome0 = clamp(1.0 - d0 / R, 0.0, 1.0);
    float shade = 1.0 - smoothstep(0.0, 0.28, d1 - R);   // 上片边缘投下的影
    float h = mix(dome0 * 0.55 - shade * 0.45, dome1, in1);
    return vec2(h, mix(shade, 0.0, in1));
}

// 腹甲：横向一条条甲片，接缝处凹下
float plate(float c) {
    float f = fract(c);
    return smoothstep(0.0, 0.14, f) * (1.0 - smoothstep(0.82, 1.0, f));
}

void fragment() {
    vec3 c = COLOR.rgb;
    vec3 lin = pow(c, vec3(2.2));
    float kind = UV.x;
    float isScale = 1.0 - step(0.5, kind);
    float isPlate = step(0.5, kind) * (1.0 - step(1.5, kind));
    float size = max(UV.y, 0.01) * scale_size;

    vec3 n = normalize(obj_nrm);
    vec3 w = pow(abs(n), vec3(4.0));
    w /= (w.x + w.y + w.z);
    vec3 q = obj_pos / size;

    // 鱼鳞：侧面（±X / ±Z）鳞片朝下叠，顶面 / 底面（±Y）朝尾巴方向叠
    vec2 sx = fish_scale(vec2(q.z, q.y));
    vec2 sz = fish_scale(vec2(q.x, q.y));
    vec2 sy = fish_scale(vec2(q.x, q.z));
    vec2 fs = sx * w.x + sy * w.y + sz * w.z;
    // 腹甲：竖面按高度分条，底面按前后分条
    float pl = plate(q.y * 0.8) * (w.x + w.z) + plate(q.z * 0.8) * w.y;

    float h = fs.x * isScale + (pl - 0.5) * isPlate;

    // 明暗：鳞片中央亮一点、边缘与被压处暗
    float tone = mix(0.8, 1.07, clamp(fs.x * 0.75 + 0.35, 0.0, 1.0));
    float albedoK = mix(1.0, tone, isScale * scale_amount) * mix(1.0, mix(0.86, 1.03, pl), isPlate);
    ALBEDO = lin * albedoK;

    // 高度场扰动法线（屏幕导数）
    vec3 N = normalize(NORMAL);
    float hm = h * size * 0.06 * bump_amount * (isScale + isPlate * 0.6);
    vec3 dpdx = dFdx(VERTEX);
    vec3 dpdy = dFdy(VERTEX);
    float dhdx = dFdx(hm);
    float dhdy = dFdy(hm);
    vec3 r1 = cross(dpdy, N);
    vec3 r2 = cross(N, dpdx);
    float det = dot(dpdx, r1);
    vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
    vec3 Nb = normalize(abs(det) * N - grad);
    NORMAL = mix(N, Nb, step(1e-12, abs(det)));

    // 鳞片偏光滑（湿润的鳞光），腹甲哑一点，眼睛最亮
    float rough = mix(0.62, 0.42 + 0.2 * (1.0 - clamp(fs.x, 0.0, 1.0)), isScale);
    rough = mix(rough, 0.72, isPlate);
    ROUGHNESS = rough;
    METALLIC = 0.0;
    AO = 1.0 - 0.35 * fs.y * isScale;
    AO_LIGHT_AFFECT = 0.5;
    EMISSION = lin * COLOR.a;
}

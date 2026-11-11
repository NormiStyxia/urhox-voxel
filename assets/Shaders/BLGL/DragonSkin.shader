// 龙鳞外皮（配合 DragonSkin.lua 的倒角网格）
//   UV.x = 表面类型：0 鱼鳞，1 腹甲横纹，2 素面（眼、爪、口、角刺）；UV.y = 该部件的体素边长
//   COLOR = 调色板颜色（sRGB），COLOR.a = 自发光强度
// 鱼鳞：部件局部空间三向投影，行距 1、相邻行错开半格的圆形鳞片，上一排盖住下一排（屋瓦式），
// 露出每片的下缘弧线。每片鳞是一个小穹顶：中央亮、下缘一圈暗线、被上片压住处有阴影。
// 起伏用局部空间有限差分求梯度（不用屏幕导数，三角形接缝处不会出线），只改法线不改外形。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;

uniform float scale_size = 1.9;   // 鳞片行距 = 体素边长 × 该值
uniform float scale_amount = 1.0; // 鳞片明暗强度
uniform float bump_amount = 1.0;  // 鳞片起伏强度

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
    obj_pos = VERTEX;
    obj_nrm = NORMAL;
}

float row_dist(vec2 p, float r) {
    float off = 0.5 * mod(r, 2.0);
    float cx = floor(p.x - off + 0.5) + off;
    return length(vec2(p.x - cx, (p.y - r) * 1.15));
}

// vec3(高度, 下缘暗线, 被压阴影)
vec3 fish_scale(vec2 p) {
    float R = 0.8;
    float r1 = floor(p.y) + 1.0;
    float d1 = row_dist(p, r1);
    float d0 = row_dist(p, r1 - 1.0);
    float in1 = step(d1, R);
    float dome1 = 1.0 - d1 / R;
    float dome0 = clamp(1.0 - d0 / R, 0.0, 1.0);
    float shade = 1.0 - smoothstep(0.0, 0.3, d1 - R);
    float h = mix(dome0 * 0.6 - shade * 0.5, dome1, in1);
    // 外露鳞片（下一排）的下缘线：在它自己的边缘附近
    float rim0 = smoothstep(R - 0.16, R - 0.04, d0) * (1.0 - in1);
    float rim1 = smoothstep(R - 0.12, R - 0.02, d1) * in1;
    return vec3(h, max(rim0, rim1), shade * (1.0 - in1));
}

float plate(float c) {
    float f = fract(c);
    return smoothstep(0.0, 0.12, f) * (1.0 - smoothstep(0.84, 1.0, f));
}

// 三向投影的综合高度场（局部空间位置 q，权重 w）
vec4 skin_field(vec3 q, vec3 w, float isScale, float isPlate) {
    vec3 sx = fish_scale(vec2(q.z, q.y));
    vec3 sz = fish_scale(vec2(q.x, q.y));
    vec3 sy = fish_scale(vec2(q.x, q.z));
    vec3 fs = sx * w.x + sy * w.y + sz * w.z;
    float pl = plate(q.y * 0.8) * (w.x + w.z) + plate(q.z * 0.8) * w.y;
    float h = fs.x * isScale + (pl - 0.5) * isPlate;
    return vec4(h, fs.y, fs.z, pl);
}

void fragment() {
    vec3 c = COLOR.rgb;
    vec3 lin = pow(c, vec3(2.2));
    float kind = UV.x;
    float isScale = 1.0 - step(0.5, kind);
    float isPlate = step(0.5, kind) * (1.0 - step(1.5, kind));
    float size = max(UV.y, 0.01) * scale_size;

    vec3 on = normalize(obj_nrm);
    vec3 w = pow(abs(on), vec3(4.0));
    w /= (w.x + w.y + w.z);
    vec3 q = obj_pos / size;
    vec4 f = skin_field(q, w, isScale, isPlate);

    // ---- 颜色：鳞片中央亮、下缘暗线、被压处暗；腹甲接缝暗
    float tone = mix(0.9, 1.06, clamp(f.x * 0.8 + 0.3, 0.0, 1.0));
    tone *= 1.0 - 0.4 * f.y - 0.2 * f.z;
    float k = mix(1.0, tone, isScale * scale_amount);
    k *= mix(1.0, mix(0.8, 1.04, f.w), isPlate);
    ALBEDO = lin * k;

    // ---- 法线：局部空间有限差分
    float strength = 0.12 * bump_amount * (isScale + isPlate * 0.7);
    vec3 t1 = normalize(cross(on, abs(on.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(on, t1);
    float e = 0.04;
    float h1 = skin_field(q + t1 * e, w, isScale, isPlate).x;
    float h2 = skin_field(q + t2 * e, w, isScale, isPlate).x;
    vec3 nObj = normalize(on - (t1 * (h1 - f.x) + t2 * (h2 - f.x)) / e * strength);
    vec3 nW = normalize(MODEL_NORMAL_MATRIX * nObj);
    // 保持和光栅正反面一致
    vec3 N = normalize(NORMAL);
    nW = dot(nW, N) < 0.0 ? -nW : nW;
    NORMAL = mix(N, nW, step(0.001, strength));

    // ---- 粗糙度：鳞片中央湿亮，边缘哑；腹甲哑
    float rough = mix(0.6, 0.38 + 0.25 * (1.0 - clamp(f.x, 0.0, 1.0)), isScale);
    ROUGHNESS = mix(rough, 0.7, isPlate);
    METALLIC = 0.0;
    AO = 1.0 - (0.35 * f.z + 0.2 * f.y) * isScale;
    AO_LIGHT_AFFECT = 0.4;
    EMISSION = lin * COLOR.a;
}

// 剑特效体素块：实例颜色 × 三面明暗 × 每面一圈深色像素描边。
// 实例颜色 rgb 为线性色，a 为发光量（0 = 不发光，1 = 乘到 glow 倍进入 HDR）。
shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform float glow = 2.4;
uniform float rim_width = 0.74;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
    opos = VERTEX;
    onrm = NORMAL;
    COLOR = INSTANCE_COLOR;
}

void fragment() {
    vec3 n = abs(onrm);
    // 顶 / 侧 / 前后三档亮度，方块才有体积感
    float shade = n.y > 0.5 ? 1.0 : (n.x > 0.5 ? 0.80 : 0.64);
    // Box.mdl 局部坐标 -0.5..0.5：面内离边最近的那一圈压暗
    vec3 a = abs(opos) * 2.0;
    vec3 face = step(vec3(0.999), a);
    float e = max(max(a.x * (1.0 - face.x), a.y * (1.0 - face.y)), a.z * (1.0 - face.z));
    float rim = step(rim_width, e);
    vec3 body = COLOR.rgb * shade * (1.0 + COLOR.a * (glow - 1.0));
    vec3 edge = COLOR.rgb * vec3(0.30, 0.42, 0.72) * shade;
    ALBEDO = mix(body, edge, rim);
}

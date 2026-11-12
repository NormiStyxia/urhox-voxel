// RuinsBark.shader — 树干 / 树枝（6.25cm 方格表面）：竖向树皮纹 + 北侧苔痕
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);
uniform vec3 bark_dark = vec3(0.30, 0.23, 0.17);
uniform vec3 bark_light = vec3(0.56, 0.45, 0.34);
uniform vec3 moss_color = vec3(0.22, 0.32, 0.14);

float h21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float n2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    vec3 wp = VERTEX;
    // 世界投影，跨贪心合并面保持一致，不使用旧圆管的环形 UV。
    vec3 n = normalize(NORMAL);
    float along = abs(n.x) > abs(n.z) ? wp.z : wp.x;
    float ridge = n2(vec2(along * 18.0, wp.y * 0.8));
    float crack = smoothstep(0.62, 0.8, ridge);
    vec3 col = mix(bark_light, bark_dark, crack * 0.8 + n2(wp.xz * 3.0 + wp.y) * 0.25);
    // 苔痕：只长在朝上 / 朝北的一侧（n.z > 0），成片
    float moss = smoothstep(0.55, 0.75, n2(vec2(along * 3.0, wp.y * 0.7))) * smoothstep(-0.2, 0.6, n.z + n.y * 0.5);
    col = mix(col, moss_color, moss * 0.6);
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = 0.92;
    METALLIC = 0.0;
    SPECULAR = 0.2;
}

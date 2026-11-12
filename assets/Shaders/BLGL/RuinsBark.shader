// RuinsBark.shader — 树干 / 树枝（TubeGeometry 网格）：竖向树皮纹 + 北侧苔痕
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
    // UV.x 沿管长、UV.y 绕圈：竖向裂纹
    float ridge = n2(vec2(UV.y * 22.0, UV.x * 3.0 + wp.y * 0.6));
    float crack = smoothstep(0.62, 0.8, ridge);
    vec3 col = mix(bark_light, bark_dark, crack * 0.8 + n2(wp.xz * 3.0 + wp.y) * 0.25);
    // 苔痕：只长在朝上 / 朝北的一侧（n.z > 0），成片
    vec3 n = normalize(NORMAL);
    float moss = smoothstep(0.55, 0.75, n2(vec2(UV.y * 6.0, UV.x * 4.0))) * smoothstep(-0.2, 0.6, n.z + n.y * 0.5);
    col = mix(col, moss_color, moss * 0.6);
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = 0.92;
    METALLIC = 0.0;
    SPECULAR = 0.2;
}

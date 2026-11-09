// 龙翼膜：一整张连续的体素阶梯网格，顶点按所在的控制三角形做仿射变形。
// 每个控制三角形的 3x4 矩阵由 Lua 每帧传入（DragonMembrane.Update）；相邻三角形在公共边上
// 映射完全一致，所以骨骼怎么折，膜都像皮一样连续拉伸 / 收拢，不会裂开或散成薄片。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;

uniform vec4 tri_rows[96];           // 32 个三角形 × 3 行（右翼 0..15，左翼 16..31）
uniform float color_is_srgb = 1.0;   // 顶点色是调色板的 sRGB 值
uniform float roughness_value = 0.8;
uniform float emission_gain = 1.0;   // 顶点色 alpha = 翼膜微弱自发光强度

void vertex() {
    if (UV.y > 0.5) {
        // 只用来撑大包围盒的退化三角形
        VERTEX = vec3(0.0);
    } else {
        int b = int(UV.x + 0.5) * 3;
        vec4 r0 = tri_rows[b];
        vec4 r1 = tri_rows[b + 1];
        vec4 r2 = tri_rows[b + 2];
        vec4 p = vec4(VERTEX, 1.0);
        VERTEX = vec3(dot(r0, p), dot(r1, p), dot(r2, p));
        // 法线用逆转置（余子式）变换，膜被拉伸时光照仍正确
        vec3 ca = vec3(r0.x, r1.x, r2.x);
        vec3 cb = vec3(r0.y, r1.y, r2.y);
        vec3 cc = vec3(r0.z, r1.z, r2.z);
        vec3 n = NORMAL;
        NORMAL = normalize(n.x * cross(cb, cc) + n.y * cross(cc, ca) + n.z * cross(ca, cb));
    }
}

void fragment() {
    vec3 c = COLOR.rgb;
    vec3 lin = mix(c, pow(c, vec3(2.2)), color_is_srgb);
    ALBEDO = lin;
    ROUGHNESS = roughness_value;
    METALLIC = 0.0;
    EMISSION = lin * COLOR.a * emission_gain;
}

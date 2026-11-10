// 体素风像素粒子：硬边像素贴图 × 顶点色（粒子 / 公告板颜色）。
//   * 最近邻采样 + alpha 阈值 → 边缘是一个个像素，没有柔边
//   * 淡出用「像素抖动」：贴图像素格按哈希逐格消失（顶点色 alpha 决定留下多少格）
//   * glow > 1 时颜色进入 HDR，配合 Bloom 发光
shader_type spatial;
render_mode shading_model_unlit, cull_disabled;

uniform sampler2D sprite_tex : filter_nearest, repeat_disable;
uniform float glow = 1.0;
uniform float cells = 8.0;   // 贴图像素格数（与 VoxelFX 的像素图尺寸一致）

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec4 t = texture(sprite_tex, UV);
    vec4 c = clamp(COLOR, 0.0, 1.0);
    // 像素抖动淡出：同一个粒子内按像素格哈希逐格消失
    float cellN = h21(floor(UV * cells) + 0.37);
    if (t.a < 0.5 || cellN > c.a * 1.02) discard;
    // 顶点色是 sRGB（粒子 / 公告板颜色按 sRGB 输入），转线性后再乘发光倍数
    vec3 lin = c.rgb * (c.rgb * (c.rgb * 0.305306011 + 0.682171111) + 0.012522878);
    // 发光时向白色靠一点，避免 HDR 色调映射把高饱和颜色推成纯红 / 纯蓝
    float mx = max(max(lin.r, lin.g), lin.b);
    vec3 col = mix(lin, vec3(mx), 0.25 * step(1.01, glow));
    ALBEDO = col * t.rgb * glow;
}

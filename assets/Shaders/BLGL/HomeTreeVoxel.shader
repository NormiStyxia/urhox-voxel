// 家园体素树：颜色来自体素色块，保留几何硬法线与真实阴影。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    ALBEDO = srgb_to_linear(COLOR.rgb) * daynight_tint;
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.16;
}

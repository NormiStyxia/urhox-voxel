// 体素角色材质：顶点色（调色板颜色由 art/nomi_voxel/voxelize.py 写进顶点）
shader_type spatial;
render_mode shading_model_pbr, cull_back;

// 顶点色来自参考图的 sRGB 像素；渲染管线是线性的，这里转一次。
// 如果实机颜色偏暗、偏饱和，把它关掉（材质 XML 里设 0）。
uniform float color_is_srgb = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.85;

void fragment() {
    vec3 c = COLOR.rgb;
    ALBEDO = mix(c, pow(c, vec3(2.2)), color_is_srgb);
    ROUGHNESS = roughness_value;
    METALLIC = 0.0;
}

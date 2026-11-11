// VoxelPalettePBR.shader — 调色板查表的 PBR 体素材质（颜色 / 粗糙金属 / 自发光 / 断面）
// 用途：离屏软件渲染校验截图时替代引擎体素材质；也可作为体素 UGC 皮肤的起点。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    float idx = voxel_palette_index(COLOR);
    vec3 albedo = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_ALBEDO)).rgb);
    vec3 cut = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_CUT)).rgb);
    vec4 pbr = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_PBR));
    vec4 emi = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_EMISSIVE));
    float interior = step(0.5, COLOR.g);
    ALBEDO = mix(albedo, cut, interior);
    ROUGHNESS = pbr.r;
    METALLIC = pbr.g;
    SPECULAR = pbr.b;
    EMISSION = srgb_to_linear(emi.rgb) * emi.a * 16.0;
}

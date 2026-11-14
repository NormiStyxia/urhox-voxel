// Indexed palette volume only; not a true-RGB character mesh. Single opaque PBR pass.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float rage_glow : hint_range(0.0, 1.0) = 0.0;

vec3 palette_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}
void fragment() {
    float index = voxel_palette_index(COLOR);
    // All samples are unconditional. No sampling/helper inside a varying predicate:
    // avoids FXC sampling-in-branch and unrelated-predicate argument lowering.
    vec4 base_sample = texture(palette_tex, voxel_palette_uv(index, VOXEL_PALETTE_ALBEDO));
    vec4 cut_sample = texture(palette_tex, voxel_palette_uv(index, VOXEL_PALETTE_CUT));
    vec4 pbr_sample = texture(palette_tex, voxel_palette_uv(index, VOXEL_PALETTE_PBR));
    vec4 emission_sample = texture(palette_tex, voxel_palette_uv(index, VOXEL_PALETTE_EMISSIVE));
    vec3 base_albedo = mix(palette_linear(base_sample.rgb), palette_linear(cut_sample.rgb), step(0.5, COLOR.g));
    vec3 base_emission = palette_linear(emission_sample.rgb) * (emission_sample.a * 16.0);
    // Palette 219 is the existing copper crack detail; no texture branch or new geometry.
    float copper = 1.0 - step(0.5, abs(index - 219.0));
    base_emission += rage_glow * (vec3(0.45, 0.28, 0.08) * copper + base_emission * 0.35);
    float f = clamp(hit_flash, 0.0, 1.0);
    ALBEDO = mix(base_albedo, vec3(1.0), f);
    EMISSION = base_emission * (1.0 - f) + vec3(0.65 * f);
    ROUGHNESS = pbr_sample.r;
    METALLIC = pbr_sample.g;
    SPECULAR = pbr_sample.b;
}

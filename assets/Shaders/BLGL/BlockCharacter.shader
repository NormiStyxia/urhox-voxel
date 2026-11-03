// 方块拼装角色材质：像素贴图（最近点采样，不糊）+ Alpha 镂空（破斗篷、发梢、丝带）
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D albedo_map : source_color, filter_nearest, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.85;

void fragment() {
    vec4 c = texture(albedo_map, UV);
    ALBEDO = c.rgb;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    ROUGHNESS = roughness_value;
    METALLIC = 0.0;
}

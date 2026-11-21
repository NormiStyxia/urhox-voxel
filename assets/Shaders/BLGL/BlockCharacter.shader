// 方块拼装角色材质：像素贴图（最近点采样，不糊）+ Alpha 镂空（破斗篷、发梢、丝带）
shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform sampler2D albedo_map : filter_nearest, repeat_disable;
varying float face_shade;

void vertex() {
    // Match Blockbench's default top-lit textured viewport, including the
    // different brightness of side and front faces of the same voxel.
    vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    face_shade = 0.75 + 0.25 * n.y - 0.15 * n.x * n.x + 0.05 * n.z * n.z;
}

void fragment() {
    vec4 c = texture(albedo_map, UV);
    // The atlas and Blockbench face brightness are in display space. Supply
    // linear colour to the game's output pass so it encodes them only once.
    vec3 rgb = c.rgb * face_shade;
    ALBEDO = rgb * (rgb * (rgb * 0.305306011 + 0.682171111) + 0.012522878);
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}

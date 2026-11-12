// HiddenVoxel.shader — 只碰撞、不显示的体素体积（地形碰撞层）：所有顶点塌到裁剪空间外
shader_type spatial;
render_mode shading_model_unlit, cull_back;

void vertex() {
    POSITION = vec4(0.0, 0.0, 2.0, 1.0);
}

void fragment() {
    ALBEDO = vec3(1.0, 0.0, 1.0);
}

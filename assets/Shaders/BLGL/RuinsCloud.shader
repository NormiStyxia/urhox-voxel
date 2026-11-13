shader_type spatial;
render_mode shading_model_unlit, cull_back;
uniform float day = 1.0;
uniform float dusk = 0.0;
void fragment() {
    // 线性 RGB；顶点面色保留体素转折，夜云冷暗，晨昏金橙。
    vec3 tint = mix(vec3(0.045, 0.075, 0.15), vec3(0.84, 0.90, 0.98), day);
    tint = mix(tint, vec3(0.98, 0.54, 0.23), dusk * 0.78);
    ALBEDO = tint * COLOR.rgb;
}

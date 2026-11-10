// 体素碎块 / 光柱方块：纯色 PBR + 自发光，边缘一圈稍暗（像体素块的描边感）。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec4 base_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform vec4 emit_color = vec4(0.0, 0.0, 0.0, 1.0);   // 线性 HDR
uniform float roughness_value = 0.35;

varying vec3 opos;

void vertex() {
    opos = VERTEX;
}

void fragment() {
    // Box.mdl 局部坐标 -0.5..0.5：离面边缘近的地方压暗一点
    vec3 a = abs(opos) * 2.0;
    vec3 s = vec3(step(0.999, a.x), step(0.999, a.y), step(0.999, a.z));
    float e = max(max(a.x * (1.0 - s.x), a.y * (1.0 - s.y)), a.z * (1.0 - s.z));
    float rim = step(0.72, e);
    ALBEDO = base_color.rgb * (1.0 - 0.28 * rim);
    ROUGHNESS = roughness_value;
    METALLIC = 0.0;
    EMISSION = emit_color.rgb * (1.0 - 0.35 * rim);
}

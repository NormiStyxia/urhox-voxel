// RuinsCrystal.shader — 时晶（六棱柱网格）：半透感的冷蓝本色 + 菲涅尔边光 + 缓慢呼吸的内发光
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);
uniform vec3 base_color = vec3(0.30, 0.48, 0.95);
uniform vec3 glow_color = vec3(0.30, 0.55, 1.0);
uniform float glow = 1.2;

varying vec3 tint;

void vertex() {
    tint = INSTANCE_COLOR.rgb;
}

void fragment() {
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(CAMERA_POSITION_WORLD - VERTEX);
    float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
    float breathe = 0.75 + 0.25 * sin(TIME * 1.3 + VERTEX.x * 0.7 + VERTEX.z * 0.5);
    // INSTANCE_COLOR.rgb 区分蓝 / 蓝紫两种晶体
    ALBEDO = base_color * tint * daynight_tint;
    ROUGHNESS = 0.12;
    METALLIC = 0.0;
    SPECULAR = 0.8;
    EMISSION = glow_color * tint * (0.35 + fres * 1.6) * glow * breathe;
}

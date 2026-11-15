// RuinsGrassTuft.shader — 兜底草簇（设备不支持 GrassField 时）
// 几何草叶：每叶一个细三角，按 UV.y（0 根 → 1 尖）做风摆和根→尖渐变；
// 法线统一朝上，让草和下面的地面落在同一档光照里（不会出现一圈亮边）。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled, world_vertex_coords;

uniform vec3 root_color = vec3(0.10, 0.20, 0.06);
uniform vec3 tip_color = vec3(0.42, 0.58, 0.22);
uniform vec3 daynight_tint = vec3(1.0);
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_strength = 0.18;

void vertex() {
    float h = UV.y;
    vec2 w = normalize(wind_dir);
    float phase = dot(VERTEX.xz, w) * 0.35 - TIME * 1.6;
    float gust = 0.6 + 0.4 * sin(phase) + 0.25 * sin(VERTEX.x * 1.7 + VERTEX.z * 1.3 + TIME * 3.1);
    vec2 bend = w * gust * wind_strength * h * h;
    VERTEX.xz += bend;
    VERTEX.y -= dot(bend, bend) * 0.5;
    NORMAL = vec3(0.0, 1.0, 0.0);
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    float h = UV.y;
    vec3 col = mix(root_color, tip_color, pow(h, 0.8)) * COLOR.rgb;
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
    SPECULAR = 0.2;
}

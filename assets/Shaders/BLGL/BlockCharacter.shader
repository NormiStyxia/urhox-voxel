// 方块拼装角色材质：像素贴图（最近点采样，不糊）+ Alpha 镂空（破斗篷、发梢、丝带）
shader_type spatial;
// The unlit technique omits the shadow caster pass. Use its opaque PBR
// coverage passes. Daytime keeps the authored Blockbench viewport colour
// (emissive); at night that self-light fades toward a floor and the same
// texels are lit by real lights instead, so campfires and lamps tint the
// character while it stays readable against the blue night.
render_mode shading_model_pbr, cull_back, ambient_light_disabled, specular_disabled;

uniform sampler2D albedo_map : filter_nearest, repeat_disable;
// 1 = daytime viewport colour, fully self-lit. Driven by Lua from DayNight.
uniform float scene_light = 1.0;
// Cool moonlit tint applied to the self-lit share at night (linear RGB).
uniform vec3 night_tint = vec3(0.62, 0.70, 0.95);
// Self-light floor at full night: keeps the silhouette and face readable.
uniform float night_floor = 0.30;
// Real-light response (albedo) at full night; 0 during the day.
uniform float night_albedo = 0.85;
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
    vec3 lin = rgb * (rgb * (rgb * 0.305306011 + 0.682171111) + 0.012522878);
    vec3 tex = c.rgb * (c.rgb * (c.rgb * 0.305306011 + 0.682171111) + 0.012522878);
    float day = clamp(scene_light, 0.0, 1.0);
    float self_light = mix(night_floor, 1.0, day);
    vec3 tint = mix(night_tint, vec3(1.0), day);
    EMISSION = lin * self_light * tint;
    // Real lights only at night: in daylight the sun would double the
    // already-complete viewport colour.
    ALBEDO = tex * night_albedo * (1.0 - day);
    SPECULAR = 0.0;
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}

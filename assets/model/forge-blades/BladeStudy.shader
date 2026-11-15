// RGB vertex channels = stone / gold / sapphire; alpha = planar shade.
// UV.x = emission mask (0 body, .3-.35 spine, 1 gem); UV.y = local height.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 primary_color : source_color = vec4(0.885, 0.911, 0.928, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.878, 0.698, 0.325, 1.0);
uniform vec4 accent_color : source_color = vec4(0.236, 0.538, 0.855, 1.0);
uniform float flow_strength : hint_range(0.0, 2.0) = 0.7;
uniform float flow_speed = 0.28;
void fragment() {
    vec3 base = primary_color.rgb * COLOR.r + secondary_color.rgb * COLOR.g + accent_color.rgb * COLOR.b;
    ALBEDO = base * COLOR.a;
    METALLIC = 0.72 * COLOR.g;
    ROUGHNESS = clamp(0.65 - 0.26 * COLOR.g - 0.30 * COLOR.b, 0.3, 0.7);
    SPECULAR = 0.35;
    // Travel entirely off the tip before resetting below the root. No seam flash.
    float head = fract(TIME * flow_speed) * 1.30 - 0.15;
    float band = 1.0 - smoothstep(0.025, 0.085, abs(UV.y - head));
    float pulse = 0.18 + 0.12 * (0.5 + 0.5 * sin(TIME * 2.4));
    float gem = step(0.75, UV.x);
    float spine = step(0.15, UV.x);
    EMISSION = flow_strength * accent_color.rgb * (spine * band * 1.9 + gem * pulse);
}

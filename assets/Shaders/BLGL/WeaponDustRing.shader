// Unit UV disc on an XZ plane. The outer dust edge ends exactly at radius 1.
shader_type spatial;
render_mode shading_model_particle_unlit, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    float theta = atan(p.y, p.x);
    float grit = .5 + .5 * sin(theta * 17.0 + sin(theta * 5.0) * 3.0);
    float rim = smoothstep(.72 + .12 * grit, .94, r) * (1.0 - smoothstep(.94, 1.0, r));
    ALBEDO = COLOR.rgb * (.82 + .28 * grit);
    ALPHA = COLOR.a * rim;
}

shader_type spatial;
render_mode shading_model_particle_unlit, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
    ALBEDO = COLOR.rgb * (.70 + .30 * abs(NORMAL.y));
    ALPHA = COLOR.a;
}

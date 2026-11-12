// Lightweight continuous frost ribbons, distinct from the cinematic breath.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform float strength = 0.0;
void fragment() {
    float across = abs(UV.y*2.0-1.0);
    float core = 1.0-smoothstep(0.12,0.72,across);
    float flow = 0.72+0.28*sin(UV.x*38.0-TIME*22.0+UV.y*7.0);
    float ends = smoothstep(0.0,0.045,UV.x)*(1.0-smoothstep(0.88,1.0,UV.x));
    ALBEDO = mix(vec3(0.12,0.48,0.68),vec3(0.65,0.9,1.0),core);
    ALPHA = (0.12+core*0.34)*flow*ends*strength*(1.0-across*across);
}

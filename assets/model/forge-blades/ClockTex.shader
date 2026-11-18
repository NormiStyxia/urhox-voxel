// Texture-driven FX sheet for the time catalyst (AI-painted dial / star-sand textures, black already keyed to alpha).
// Quads are placed by the visual: `billboard` = 1 faces the camera (dial halo), 0 keeps the quad's own orientation
// (tilted star-sand rings). The texture slowly spins about its centre, so one static sheet reads as a moving effect.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength = 1.0;
uniform float spin = 0.3;              // rad/sec, texture rotation about its centre
uniform float breathe = 0.0;           // 0..1: brightness swell (cast / charge)
uniform float billboard = 0.0;
uniform float half_size = 0.5;         // object-space half edge of the quad (billboard mode)
varying vec2 uv_v;
void vertex() {
    uv_v = UV;
    if (billboard > 0.5) {
        vec3 centre = MODEL_MATRIX[3].xyz;
        float sc = length(MODEL_MATRIX[0].xyz);
        vec3 right = vec3(INV_VIEW_MATRIX[0][0], INV_VIEW_MATRIX[0][1], INV_VIEW_MATRIX[0][2]);
        vec3 up = vec3(INV_VIEW_MATRIX[1][0], INV_VIEW_MATRIX[1][1], INV_VIEW_MATRIX[1][2]);
        vec2 c = UV * 2.0 - 1.0;
        VERTEX = centre + (right * c.x + up * (-c.y)) * half_size * sc;
    }
}
void fragment() {
    vec2 p = uv_v - 0.5;
    // The Roman dial and its bezel stay fixed. Only the procedural hand moves.
    vec2 q = uv_v;
    vec4 t = texture(tex, q);
    float handAngle = TIME * 4.2;
    vec2 hand = vec2(cos(handAngle), sin(handAngle));
    float along = dot(p, hand);
    vec2 side = p - hand * along;
    float handWidth = 0.012 + 0.010 * (1.0 - clamp(along * 2.0, 0.0, 1.0));
    float handLine = (1.0 - smoothstep(handWidth, handWidth + 0.008, length(side)))
        * step(0.0, along) * (1.0 - smoothstep(0.36, 0.48, length(p)));
    float handHub = 1.0 - smoothstep(0.035, 0.055, length(p));
    float inside = 1.0 - smoothstep(0.46, 0.5, length(p));
    ALBEDO = (t.rgb * tint.rgb + vec3(1.0, 0.88, 0.55) * (handLine + handHub) * 1.6) * (1.4 + 1.2 * breathe);
    ALPHA = clamp(max(t.a * tint.a, (handLine + handHub) * tint.a) * strength * inside, 0.0, 1.0);
}

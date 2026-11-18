// Drifting star motes around the time catalyst: camera-facing diamonds on a loose shell that slowly turns
// and rises, twinkling. Geometry is uploaded once; vertex() places every mote (phase in UV.x, seed in UV.y,
// corner in COLOR.rg). world_vertex_coords because the quads must face the camera.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;
uniform vec4 ice_color : source_color = vec4(0.62, 0.82, 1.0, 1.0);
uniform vec4 white_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform vec4 gold_color : source_color = vec4(1.0, 0.80, 0.42, 1.0);
uniform float strength = 1.0;
uniform float spread = 1.0;          // shell scale (orb scale), set by the visual
uniform float rise = 0.045;          // shell units/sec
varying float tw_v;
varying float kind_v;
varying vec2 corner_v;
void vertex() {
    float phase = UV.x;
    float seed = UV.y;
    vec2 corner = COLOR.rg * 2.0 - 1.0;
    float t = TIME * 0.12 + seed * 6.2831853;
    float r = (0.30 + 0.34 * fract(seed * 7.13)) * spread;
    float ang = t * (0.6 + 0.8 * fract(seed * 3.7)) + phase * 6.2831853;
    float h = fract(phase + TIME * rise) * 2.0 - 1.0;      // -1 .. 1 rising column
    float ring = sqrt(max(0.0, 1.0 - h * h * 0.8));
    vec3 centre_obj = vec3(cos(ang) * r * ring, h * r * 0.95, sin(ang) * r * ring * 0.8);
    vec3 centre = (MODEL_MATRIX * vec4(centre_obj, 1.0)).xyz;
    vec3 right = vec3(INV_VIEW_MATRIX[0][0], INV_VIEW_MATRIX[0][1], INV_VIEW_MATRIX[0][2]);
    vec3 up = vec3(INV_VIEW_MATRIX[1][0], INV_VIEW_MATRIX[1][1], INV_VIEW_MATRIX[1][2]);
    float size = (0.011 + 0.020 * fract(seed * 11.9)) * spread;
    float life = smoothstep(-1.0, -0.7, h) * (1.0 - smoothstep(0.7, 1.0, h));
    VERTEX = centre + (right * corner.x + up * corner.y) * size * (0.4 + 0.6 * life);
    tw_v = (0.5 + 0.5 * sin(TIME * (2.0 + 4.0 * fract(seed * 5.3)) + seed * 40.0)) * life;
    kind_v = step(0.82, fract(seed * 13.7)) + step(0.55, fract(seed * 13.7)) * 0.5;
    corner_v = corner;
}
void fragment() {
    float d = abs(corner_v.x) + abs(corner_v.y);          // diamond
    float shape = 1.0 - smoothstep(0.55, 1.0, d);
    vec3 c = mix(ice_color.rgb, white_color.rgb, step(0.5, kind_v));
    c = mix(c, gold_color.rgb, step(0.99, kind_v));
    ALBEDO = c * 1.7;
    ALPHA = clamp(shape * tw_v * strength, 0.0, 1.0);
}

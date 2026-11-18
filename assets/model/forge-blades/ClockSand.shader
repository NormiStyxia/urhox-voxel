// Star-river sand around the time catalyst. Grains are short ribbons; vertex() slides each one along a
// tilted orbit (stream id in UV.y, phase in UV.x, ribbon coordinates + jitter in COLOR), so the geometry
// is uploaded once and all motion runs on the GPU. blend_mix, unlit, no depth write.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 head_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 body_color : source_color = vec4(0.30, 0.60, 1.0, 1.0);
uniform vec4 gold_color : source_color = vec4(1.0, 0.78, 0.38, 1.0);
uniform float flow_speed = 0.11;      // orbit cycles/sec at rest
uniform float strength = 1.0;         // overall brightness/alpha
uniform float tighten = 0.0;          // 0..1: orbits pull toward the core while casting
varying float s_v;
varying float u_v;
varying float lane_v;
varying float spark_v;
vec3 orbit(float stream, float s, float jit) {
    float a = 6.2831853 * s;
    float tilt = 0.0;
    float rad = 0.15;
    float lift = 0.0;
    float dir = 1.0;
    if (stream < 0.5) { tilt = 0.55; rad = 0.135; dir = 1.0; }
    else if (stream < 1.5) { tilt = -0.60; rad = 0.175; dir = -1.0; }
    else { tilt = 1.15; rad = 0.315; dir = 1.0; }
    rad *= 1.0 - 0.28 * tighten;
    rad += 0.012 * sin(a * 3.0 + stream * 1.7) + (jit - 0.5) * 0.030;
    vec3 p = vec3(cos(a * dir) * rad, sin(a * dir) * rad * 0.62, 0.0);
    p.z = sin(a * 2.0 + stream) * rad * 0.35;           // galactic S-sweep out of the plane
    float ct = cos(tilt), st = sin(tilt);
    return vec3(p.x, p.y * ct - p.z * st, p.y * st + p.z * ct);
}
void vertex() {
    float stream = UV.y;
    float s = fract(UV.x + TIME * flow_speed * (stream < 1.5 ? 1.0 : 0.55));
    float along = COLOR.r;                 // 0 head -> 1 tail
    float across = COLOR.g * 2.0 - 1.0;
    float jit = COLOR.b;
    float tail_len = 0.020 + 0.060 * COLOR.a;
    vec3 head = orbit(stream, s, jit);
    vec3 back = orbit(stream, s - tail_len, jit);
    vec3 tangent = normalize(head - back + vec3(0.0000001));
    vec3 side = normalize(cross(tangent, normalize(head + vec3(0.0000001))));
    float width = 0.0016 + 0.0028 * COLOR.a * (1.0 - along * 0.8);
    vec3 centre = mix(head, back, along);
    VERTEX = centre + side * across * width;
    s_v = s;
    u_v = along;
    lane_v = stream;
    spark_v = step(0.86, jit);
}
void fragment() {
    float tail = 1.0 - u_v;
    vec3 c = mix(body_color.rgb, head_color.rgb, tail * tail);
    c = mix(c, gold_color.rgb, spark_v * 0.8);
    float twinkle = 0.65 + 0.35 * sin(TIME * 3.0 + s_v * 40.0 + lane_v * 2.0);
    ALBEDO = c * (1.4 + 0.8 * spark_v);
    ALPHA = clamp(tail * tail * 0.95 * twinkle * strength, 0.0, 1.0);
}

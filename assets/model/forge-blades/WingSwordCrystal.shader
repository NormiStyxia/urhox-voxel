// Wing sword sapphire inset, translucent pass. Only the blue core/shoulder/gem
// triangles use this material (WingSwordVisual splits them out); gold, white
// edges and grip stay on the opaque WingSword.shader.
// UV.x .35 core / 1 gem; UV.y = full weapon height 0..1; COLOR.a = face shade.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 primary_color : source_color = vec4(0.885, 0.911, 0.928, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.878, 0.698, 0.325, 1.0);
uniform vec4 accent_color : source_color = vec4(0.236, 0.538, 0.855, 1.0);
uniform vec4 grip_color : source_color = vec4(0.08, 0.15, 0.36, 1.0);
uniform float crystal_alpha = 0.42;     // body opacity at normal incidence
uniform float edge_alpha = 0.92;        // opacity at grazing angles / facet rims
uniform float gem_alpha = 0.80;
uniform float inner_glow = 0.55;        // self-light of the coloured interior
uniform float rim_glow = 0.85;          // icy fresnel rim
uniform float sparkle = 1.4;            // sun glints on the cut faces
uniform float flow_strength : hint_range(0.0, 2.0) = 0.7;
uniform float flow_speed = 0.22;        // sweep cycles/sec
uniform float charge = 0.0;             // 0..1, raised by WeaponRig while swinging
varying vec3 obj_pos;
varying vec3 obj_normal;
void vertex() {
    obj_pos = VERTEX;
    obj_normal = NORMAL;
}
void fragment() {
    float gem_m = step(0.75, UV.x);
    // Saturated hue from the forge palette; brightness is rebuilt here.
    vec3 a = max(accent_color.rgb, vec3(0.0));
    vec3 hue = a / max(max(max(a.r, a.g), a.b), 0.001);
    hue = max(hue - vec3(min(min(hue.r, hue.g), hue.b) * 0.85), vec3(0.0));
    hue = hue / max(max(max(hue.r, hue.g), hue.b), 0.001);
    vec3 deep = hue * hue * 0.22;
    vec3 ice = mix(hue, vec3(0.80, 0.95, 1.0), 0.55);

    vec3 n = normalize(NORMAL);
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (dot(view_delta, view_delta) > 0.00000001) {
        v = normalize(view_delta);
    }
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.5);
    vec3 r = 2.0 * dot(n, v) * n - v;
    float rl = clamp(dot(r, MAIN_LIGHT_DIRECTION), 0.0, 1.0);

    // Each flat cut gets its own interior brightness: reads as faceted stone,
    // not a smooth glass tube. Shade is constant per triangle.
    float facet = clamp(0.45 + obj_normal.x * 0.9 + obj_normal.y * 0.6 + (COLOR.a - 0.9) * 2.0, 0.0, 1.0);
    // Light pooling towards the blade axis (thin edges stay clear).
    float axis = 1.0 - smoothstep(0.0, 0.05, abs(obj_pos.x));
    vec3 body = mix(deep, hue * 0.75, facet * 0.6 + axis * 0.4);

    // Slow refracted sweep plus a faint second band; stronger while charged.
    float head = fract(TIME * flow_speed) * 1.5 - 0.25;
    float phase = UV.y + obj_pos.x * 1.2 + obj_normal.x * 0.02;
    float sweep = 1.0 - smoothstep(0.0, 0.06, abs(phase - head));
    float sweep2 = 1.0 - smoothstep(0.0, 0.03, abs(phase - head + 0.18));
    float k = clamp(charge, 0.0, 1.0);

    ALBEDO = body;
    ROUGHNESS = 0.04;
    METALLIC = 0.0;
    SPECULAR = 0.9;
    float glint = pow(rl, 80.0) * (0.4 + facet);
    EMISSION = body * (inner_glow + k * 1.6)
             + ice * fres * (rim_glow + k * 0.8)
             + vec3(1.0) * glint * sparkle
             + ice * (sweep * 0.55 + sweep2 * 0.25) * max(flow_strength, 0.0) * (1.0 - gem_m)
             + hue * gem_m * (0.35 + 0.15 * sin(TIME * 2.0));
    float alpha = mix(crystal_alpha, edge_alpha, clamp(fres * 1.4 + glint, 0.0, 1.0));
    alpha = max(alpha, sweep * 0.7);
    ALPHA = clamp(mix(alpha, gem_alpha, gem_m) + k * 0.25, 0.0, 1.0);
}

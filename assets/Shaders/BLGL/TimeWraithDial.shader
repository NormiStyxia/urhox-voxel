// Registered copper and cold-imprint plates; all phase decisions use native texels.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D dial_atlas : filter_nearest, repeat_disable;
uniform float ink_phase = 0.0; // 0 windup, 1 slow, 2 release
uniform float phase_progress = 0.0;
uniform float hand_turn = 0.0; // clockwise from world +Z, same angle as the raised hand

void fragment() {
    vec2 cell = clamp(floor(UV * 128.0), vec2(0.0), vec2(127.0));
    vec2 uv = (cell + 0.5) / 128.0;
    vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y) * 2.0;
    float r = length(p);
    float turn = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
    float dither = mod(cell.x + 2.0 * cell.y + mod(cell.y, 3.0), 7.0) / 7.0;
    float shutter = mod(floor(turn * 12.0) * 5.0, 12.0) / 12.0;
    vec4 copper = texture(dial_atlas, vec2(uv.x * 0.5, uv.y));
    vec4 cold = texture(dial_atlas, vec2(uv.x * 0.5 + 0.5, uv.y));
    float tip = fract(hand_turn);
    float trail = fract(tip - turn + 1.0);
    float brushed = step(turn, tip);
    float printMask = step(r + 0.13 * shutter + 0.055 * dither, 1.25 * phase_progress + 0.025);
    float opacity = 0.74;
    if (ink_phase < 0.5) {
        brushed = 0.16 * brushed;
    } else if (ink_phase < 1.5) {
        printMask = 1.0;
        opacity = 0.84;
    } else {
        float eraser = (1.0 - phase_progress) * 1.23;
        float row = floor(r * 10.0) / 10.0 + 0.10 * shutter + 0.05 * dither;
        printMask = step(row, eraser) * (1.0 - step(0.999, phase_progress));
    }
    vec3 pigment = mix(copper.rgb, cold.rgb, brushed);
    float glint = (1.0 - step(0.016 + 0.009 * dither, trail)) * step(0.13, r);
    pigment = mix(pigment, vec3(0.86,1.0,0.82), glint * 0.86);
    ALBEDO = pigment;
    ALPHA = copper.a * opacity * printMask;
}

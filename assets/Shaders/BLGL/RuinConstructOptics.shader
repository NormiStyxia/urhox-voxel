// One nearest texel read per fragment. Frames contain the painted metallic
// underlayer, sweep and broken highlights. No scene-colour or depth reads.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D optics_tex : filter_nearest, repeat_disable;
uniform float stamp = 0.0;
uniform float exposure = 0.0;
uniform float runs = 1.0;
uniform float coverage = 1.0;
void fragment() {
    vec2 p = vec2(fract(clamp(UV.x, 0.0, 0.99999) * runs), clamp(UV.y, 0.0, 0.99999));
    vec2 cell = floor(p * 64.0);
    vec2 atlas = (vec2(exposure, stamp) * 64.0 + cell + 0.5) / vec2(512.0,384.0);
    vec4 ink = textureLod(optics_tex, atlas, 0.0);
    float brush = fract((cell.x * 5.0 + cell.y * 11.0 + floor(cell.y / 3.0)) / 19.0);
    if (ink.a < 0.01 || brush >= coverage) discard;
    ALBEDO = ink.rgb;
    ALPHA = ink.a;
}

// 龙息光束：套在 Models/Cylinder.mdl（Y 轴 -0.5..0.5，直径 1）上的发光柱。
// 视线与法线夹角决定亮度（中心亮、边缘柔），沿轴向滚动的能量纹让光束有流动感；
// 两端（含圆柱盖）淡出，不露出硬边。
shader_type spatial;
render_mode shading_model_unlit, blend_premul_alpha, cull_disabled, depth_draw_never;

uniform vec4 core_color = vec4(1.0, 0.9, 1.0, 1.0);
uniform vec4 edge_color = vec4(0.5, 0.2, 1.0, 1.0);
uniform float intensity = 4.0;
uniform float fade = 1.0;
uniform float scroll = 0.0;
uniform float sharp = 2.0;
uniform float darken = 0.0;

varying vec3 opos;

void vertex() {
    opos = VERTEX;
}

void fragment() {
    vec3 v = normalize(CAMERA_POSITION_WORLD - VERTEX);
    vec3 n = normalize(NORMAL);
    float f = abs(dot(n, v));
    float y = clamp(opos.y + 0.5, 0.0, 1.0);
    float a = atan(opos.z, opos.x);
    float flow = 0.65 + 0.35 * sin(y * 46.0 - scroll * 14.0 + sin(a * 3.0 + scroll * 4.0) * 1.6);
    float flow2 = 0.7 + 0.3 * sin(y * 13.0 - scroll * 6.0 + a * 2.0);
    float ends = smoothstep(0.0, 0.04, y) * (1.0 - smoothstep(0.93, 1.0, y));
    float core = pow(f, sharp);
    vec3 col = mix(edge_color.rgb, core_color.rgb, core) * core * flow * flow2;
    col *= intensity * fade * ends;
    ALBEDO = col;
    ALPHA = clamp(core * darken * fade * ends, 0.0, 1.0);
}

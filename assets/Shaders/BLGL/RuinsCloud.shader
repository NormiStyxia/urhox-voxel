shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_back, depth_draw_never;
// 真正闭合的三维网格；没有 billboard/图集/顶点形变。RGB=厚度/高度/烘焙遮蔽，A=近/远层。
uniform sampler2D scene_depth : hint_depth_texture;
uniform float day = 1.0;
uniform float dusk = 0.0;
// Lua传入Color，材质API自动转线性；不得再次做sRGB解码。
uniform vec4 sky_top = vec4(0.30, 0.50, 0.80, 1.0);
uniform vec4 sky_horizon = vec4(0.65, 0.75, 0.90, 1.0);

void fragment() {
    vec3 n = normalize(NORMAL); // 引擎插值的烘焙梯度法线，禁止用dFdx/dFdy重建面法线
    vec3 toward_camera = CAMERA_POSITION_WORLD - VERTEX;
    float distance_to_camera = length(toward_camera);
    vec3 v = toward_camera / max(distance_to_camera, 0.001);
    vec3 l = MAIN_LIGHT_DIRECTION; // 真实太阳/月光方向，与 DayNight 共用同一平行光
    float lit = dot(n, l);
    float wrap = clamp((lit + 0.45) / 1.45, 0.0, 1.0);
    float stepped = 0.35 * smoothstep(0.12, 0.36, wrap) + 0.65 * smoothstep(0.48, 0.76, wrap);
    float bands = (0.24 + 0.76 * mix(wrap, stepped, 0.45)) * (0.68 + 0.32 * smoothstep(-0.50, 0.50, n.y));
    vec3 horizon = sky_horizon.rgb;
    vec3 zenith = sky_top.rgb;
    vec3 dark = mix(vec3(0.020, 0.033, 0.065), vec3(0.48, 0.55, 0.72), day);
    dark = mix(dark, vec3(0.31, 0.25, 0.39), dusk * 0.65);
    dark = mix(dark, zenith, 0.18);
    vec3 light = mix(vec3(0.10, 0.14, 0.22), vec3(0.94, 0.93, 0.88), day);
    light = mix(light, vec3(0.98, 0.70, 0.44), dusk * 0.62);
    vec3 color = mix(dark, light, bands) * (0.92 + 0.08 * COLOR.b);
    color = mix(color, mix(horizon, zenith, COLOR.g), 0.08 + 0.09 * COLOR.g);
    float facing = max(dot(n, v), 0.0);
    float rim = pow(1.0 - facing, 3.0);
    float backlight = max(-dot(l, v), 0.0);
    vec3 rim_color = mix(vec3(0.75, 0.84, 0.96), vec3(1.0, 0.48, 0.19), dusk);
    float silver = rim * (0.10 + 0.70 * backlight * backlight) * (0.12 + day * 0.30 + dusk * 0.35);
    float transmission = max(-lit, 0.0) * backlight * backlight * (1.0 - COLOR.r);
    color += rim_color * silver + vec3(1.0, 0.34, 0.12) * transmission * dusk * 0.28;
    // 云堤更薄、更雾化；其余继承 Zone 距离/高度雾，不建立独立背景色。
    color = mix(color, horizon, (1.0 - COLOR.a) * 0.38);
    ALBEDO = color;

    // 与 BayWater 相同的引擎反投影约定；交界1.2m软化，保留实体内部近不透明的厚度感。
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(scene_depth, SCREEN_UV).r, 1.0);
    vec4 cloud_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
    float scene_distance = abs(scene_view.z) / max(abs(scene_view.w), 0.00001);
    float cloud_distance = abs(cloud_view.z) / max(abs(cloud_view.w), 0.00001);
    float soft_depth = smoothstep(0.0, 1.2, scene_distance - cloud_distance);
    float near_fade = smoothstep(2.0, 9.0, distance_to_camera);
    float edge_opacity = 0.98 * smoothstep(0.0, 0.62, facing);
    ALPHA = edge_opacity * mix(0.66, 1.0, COLOR.a) * soft_depth * near_fade;
    // 保留引擎距离/高度雾，与 DayNight 地平线自动融合。
}

shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
// 数据图，不加 source_color：A=轮廓，R=shade，G=highlight，B 保留。
// filter_linear 不启用 mipmap；repeat_disable 为 Clamp，阈值只保留极小抗锯齿边缘。
uniform sampler2D cloud_atlas : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture;
uniform float use_atlas = 0.0;
uniform float day = 1.0;
uniform float dusk = 0.0;

void vertex() {
    if (COLOR.a > 0.0) {
        // RGBA8 整数中心；节点只有平移，不能给 CloudLayer 施加旋转/缩放。
        vec3 packed_center = floor(COLOR.rgb * 255.0 + vec3(0.5));
        vec3 center = packed_center * vec3(2.0, 1.0, 2.0) - vec3(256.0, 128.0, 256.0);
        vec3 offset = VERTEX - center;
        vec3 world_center = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
        vec2 toward = CAMERA_POSITION_WORLD.xz - world_center.xz;
        float span = length(toward);
        vec2 facing = vec2(0.0, 1.0);
        if (span > 0.01) { facing = toward / span; }
        vec3 right_axis = vec3(facing.y, 0.0, -facing.x);
        vec3 front_axis = vec3(facing.x, 0.0, facing.y);
        VERTEX = center + right_axis * offset.x + vec3(0.0, offset.y, 0.0) + front_axis * offset.z;
        NORMAL = vec3(0.0, NORMAL.y, 0.0) + front_axis * NORMAL.z;
    }
}

void fragment() {
    vec2 p = fract(UV * 2.0) * 2.0 - 1.0;
    vec4 masks = texture(cloud_atlas, UV);
    // 缺图退回程序圆形遮罩，不读取默认白纹理的轮廓，也不生成方块。
    float round_edge = 0.78 - length(p);
    float round_aa = max(fwidth(round_edge), 0.004);
    float round_mask = smoothstep(-round_aa * 0.5, round_aa * 0.5, round_edge);
    float bottom_aa = max(fwidth(p.y), 0.004);
    float round_shade = smoothstep(0.18 - bottom_aa * 0.5, 0.18 + bottom_aa * 0.5, p.y);
    vec3 aa = max(fwidth(masks.arg) * 0.5, vec3(0.05));
    vec3 coverage = smoothstep(vec3(0.5) - aa, vec3(0.5) + aa, masks.arg);
    float shape = mix(round_mask, coverage.x, use_atlas);
    float shade = mix(round_shade, coverage.y, use_atlas);
    float highlight = coverage.z * use_atlas;
    // 底片只用 shade 色；正文三个色块没有噪声、明暗渐变、透明泛灰或写实轮廓光。
    float is_bottom = 1.0 - step(0.75, COLOR.a);
    shade = max(shade, is_bottom);
    highlight *= 1.0 - shade;
    vec3 base_color = mix(vec3(0.065, 0.095, 0.17), vec3(0.87, 0.91, 0.98), day);
    vec3 shade_color = mix(vec3(0.025, 0.045, 0.095), vec3(0.59, 0.67, 0.84), day);
    vec3 light_color = mix(vec3(0.16, 0.23, 0.34), vec3(1.0, 0.96, 0.83), day);
    base_color = mix(base_color, vec3(0.96, 0.76, 0.69), dusk);
    shade_color = mix(shade_color, vec3(0.40, 0.30, 0.43), dusk);
    light_color = mix(light_color, vec3(1.0, 0.85, 0.57), dusk);
    ALBEDO = mix(mix(base_color, shade_color, shade), light_color, highlight);

    // 与 BayWater 相同的引擎反投影约定；只在交界 0.6m 内软化，内部 alpha=1。
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(scene_depth, SCREEN_UV).r, 1.0);
    vec4 card_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
    float scene_distance = abs(scene_view.z) / max(abs(scene_view.w), 0.00001);
    float card_distance = abs(card_view.z) / max(abs(card_view.w), 0.00001);
    float soft_depth = smoothstep(0.0, 0.6, scene_distance - card_distance);
    float near_fade = smoothstep(2.0, 8.0, length(VERTEX - CAMERA_POSITION_WORLD));
    ALPHA = shape * soft_depth * near_fade;
    // 保留引擎距离/高度雾，与 DayNight 地平线自动融合。
}

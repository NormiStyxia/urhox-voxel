// RuinsLeafCard.shader — 树冠叶片卡（MC 高清材质包风格的像素叶，alpha 镂空）
//
// 每张卡是一个四边形，几十张交叉叠成一个叶团。要点：
//   • 贴图最近点采样 + mip：像素叶边缘清楚，远处不闪
//   • 颜色由贴图亮度重映射到 leaf_dark → leaf_light 渐变（同一张图做绿叶 / 金叶）
//   • 光照法线用"叶团外法线"（CustomGeometry 里写好的），整个树冠像一个体积那样明暗过渡，
//     不会每张卡各亮各的；外层 / 顶部再提亮，内层压暗（顶点色 r = 深度遮蔽）
//   • 风：按卡片在团里的位置整体轻摆 + 叶尖抖动（UV.y 越高抖得越多）
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;

uniform sampler2D leaf_tex : filter_nearest_mipmap, repeat_disable;
uniform vec3 leaf_dark = vec3(0.10, 0.22, 0.07);
uniform vec3 leaf_light = vec3(0.56, 0.74, 0.26);
uniform vec3 daynight_tint = vec3(1.0);
uniform float wind_strength = 0.05;
uniform float alpha_cut = 0.5;

varying vec3 vcol;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
    vcol = COLOR.rgb;
    vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float sway = sin(TIME * 1.2 + wp.x * 0.23 + wp.z * 0.19) * 0.6 + sin(TIME * 2.6 + wp.z * 0.5 + wp.y * 0.3) * 0.4;
    float flutter = sin(TIME * 7.0 + wp.x * 3.1 + wp.y * 2.3) * 0.02;
    float k = 0.4 + 0.6 * (1.0 - UV.y);
    VERTEX.x += (sway * wind_strength + flutter) * k;
    VERTEX.z += (sway * wind_strength * 0.6 - flutter) * k;
    VERTEX.y += flutter * 0.5 * k;
}

void fragment() {
    vec4 t = texture(leaf_tex, UV);
    float lum = dot(t.rgb, vec3(0.3, 0.55, 0.15));
    float shade = vcol.r;      // 0 = 团心深处，1 = 外表面
    float var = vcol.g;        // 每张卡的亮度差
    vec3 col = mix(leaf_dark, leaf_light, clamp((lum - 0.06) * 1.9, 0.0, 1.0));
    col *= mix(0.5, 1.12, shade) * (0.88 + var * 0.24);
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ALPHA = t.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_cut;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
    SPECULAR = 0.3;
}

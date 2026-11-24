// 家园叶冠：体素遮蔽、轻微棱面高光，以及相机到角色视线上的柔和消隐。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);
// 主视角统一传入，反射和阴影 pass 不改用自己的相机位置。
uniform vec4 foliage_eye = vec4(0.0);
uniform vec4 foliage_target = vec4(0.0);
uniform float leaf_cell = 0.1875;
varying vec3 leaf_local;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
    leaf_local = VERTEX;
}

void fragment() {
    vec3 n = normalize(NORMAL);
    // 只在每颗方粒边缘做极窄的光照过渡，远处自动衰减，轮廓仍是实体方块。
    vec3 cell = fract((leaf_local - n * 0.001) / leaf_cell);
    vec3 edge = 1.0 - smoothstep(vec3(0.025), vec3(0.12), min(cell, 1.0-cell));
    vec3 bevel = sign(cell-0.5) * edge * (1.0-abs(n));
    float pixel_width = max(length(dFdx(leaf_local)), length(dFdy(leaf_local)));
    float detail = 1.0-smoothstep(0.025, 0.09, pixel_width);
    NORMAL = normalize(n + bevel * 0.18 * detail);

    float variation = dot(COLOR.rgb, vec3(0.24,0.58,0.18));
    // 顶部微暖、内部偏冷；环境遮蔽由叶簇实际占据格预计算。
    vec3 facing_tint = mix(vec3(0.93,0.99,1.035), vec3(1.035,1.015,0.95), n.y*0.5+0.5);
    ALBEDO = srgb_to_linear(COLOR.rgb * facing_tint) * daynight_tint;
    ROUGHNESS = mix(0.82,0.65,variation);
    METALLIC = 0.0;
    SPECULAR = 0.30;
    AO = COLOR.a;

    vec3 ray = foliage_target.xyz - foliage_eye.xyz;
    float length2 = max(dot(ray,ray),0.001);
    float along = clamp(dot(VERTEX-foliage_eye.xyz,ray)/length2,0.0,1.0);
    vec3 nearest = foliage_eye.xyz + ray*along;
    // 中央彻底让出视野，边缘渐虚；用空间哈希避免多层半透明叶面叠回不透明。
    float radius = mix(0.80,0.62,along);
    float corridor = smoothstep(radius,radius+0.60,length(VERTEX-nearest));
    float near_camera = smoothstep(0.85,2.05,length(VERTEX-foliage_eye.xyz));
    float visibility = min(corridor,near_camera);
    ALPHA = mix(1.0,visibility,foliage_eye.w);
    ALPHA_HASH_SCALE = 1.0;
}

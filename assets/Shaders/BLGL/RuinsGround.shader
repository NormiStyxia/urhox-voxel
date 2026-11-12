// RuinsGround.shader — 时之遗迹的平滑地面（Terrain 高度图网格）
//
// 颜色全部程序化：世界空间多层噪声把草地 / 枯草 / 泥土 / 铺石 / 岩壁 混在一起，
// 权重来自 Lua 生成的控制图 splat_map（覆盖整块地形，UV 0..1）：
//   R = 铺石路   G = 泥土 / 碎石   B = 岩壁（崖面）   A = 草地密度（GrassField 也读这张）
// 崖面另外按法线坡度自动换岩石，岩层沿倾斜、带噪声扭曲的方向分布，不再是一圈圈水平色带。
// daynight_tint：昼夜模块统一写入，乘到最终颜色（与其他自定义材质一致）。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform vec3 daynight_tint = vec3(1.0);
uniform vec3 grass_dark = vec3(0.16, 0.30, 0.10);
uniform vec3 grass_light = vec3(0.36, 0.52, 0.20);
uniform vec3 grass_dry = vec3(0.55, 0.52, 0.28);
uniform vec3 dirt_color = vec3(0.36, 0.28, 0.20);
uniform vec3 path_color = vec3(0.62, 0.58, 0.51);
uniform vec3 rock_a = vec3(0.56, 0.54, 0.51);
uniform vec3 rock_b = vec3(0.40, 0.39, 0.40);
uniform vec3 rock_warm = vec3(0.62, 0.56, 0.47);
uniform vec3 deep_color = vec3(0.22, 0.23, 0.27);
uniform float deep_y = -11.5;
uniform float world_half = 84.0;
uniform float snow_y = 31.0;
uniform vec3 snow_color = vec3(0.93, 0.94, 0.97);

float hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += vnoise(p) * a;
        p = p * 2.03 + vec2(17.1, 5.3);
        a *= 0.5;
    }
    return s;
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    vec3 wp = VERTEX;
    vec3 n = normalize(NORMAL);
    // 控制图按世界坐标取：第 0 行 = +Z（北）
    vec2 suv = vec2(wp.x + world_half, world_half - wp.z) / (2.0 * world_half);
    vec4 sp = texture(splat_map, suv);

    // ---- 草地：大块明暗斑 + 细碎颗粒 + 枯草斑
    float big = fbm(wp.xz * 0.045);
    float mid = fbm(wp.xz * 0.28 + 3.0);
    float fine = vnoise(wp.xz * 3.1);
    vec3 grass = mix(grass_dark, grass_light, clamp(big * 1.1 + mid * 0.35 - 0.25, 0.0, 1.0));
    grass = mix(grass, grass_dry, smoothstep(0.62, 0.78, fbm(wp.xz * 0.06 + 40.0)) * 0.55);
    grass *= 0.88 + fine * 0.22;

    // ---- 泥土 / 碎石
    float pebble = smoothstep(0.72, 0.8, vnoise(wp.xz * 5.0));
    vec3 dirt = dirt_color * (0.85 + mid * 0.3);
    dirt = mix(dirt, path_color * 0.85, pebble * 0.6);

    // ---- 铺石路：不规则石板（Voronoi 风格的格缝）
    vec2 pc = wp.xz * 1.15;
    vec2 cell = floor(pc + vec2(0.0, floor(pc.x) * 0.5));
    vec2 f = fract(pc + vec2(0.0, floor(pc.x) * 0.5));
    float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    float slab = hash2(cell);
    vec3 path = path_color * (0.84 + slab * 0.26) * (0.92 + fine * 0.12);
    path = mix(path * 0.55, path, smoothstep(0.02, 0.07, seam));
    path = mix(path, grass * 0.9, smoothstep(0.55, 0.85, mid) * 0.5 * (1.0 - smoothstep(0.03, 0.09, seam)));

    // ---- 岩壁：倾斜 + 噪声扭曲的岩层（不是水平环带）
    float warp = fbm(wp.xz * 0.05 + vec2(wp.y * 0.03)) * 6.0;
    float strata = wp.y * 0.55 + dot(wp.xz, vec2(0.07, 0.045)) + warp;
    float band = vnoise(vec2(strata, 0.5)) * 0.65 + vnoise(vec2(strata * 3.7, 7.0)) * 0.35;
    vec3 rock = mix(rock_b, rock_a, band);
    rock = mix(rock, rock_warm, smoothstep(0.6, 0.85, fbm(wp.xz * 0.11 + wp.y * 0.07)) * 0.6);
    rock *= 0.82 + 0.3 * vnoise(vec2(wp.x + wp.z, wp.y) * 2.3);
    // 崖顶向下挂一点苔
    float mossy = smoothstep(0.55, 0.75, fbm(vec2(wp.x - wp.z, wp.y * 2.0) * 0.35)) * smoothstep(0.35, 0.75, n.y + 0.6);
    rock = mix(rock, grass_dark * 1.2, mossy * 0.45);
    rock = mix(rock, deep_color, smoothstep(deep_y + 1.5, deep_y - 1.0, wp.y) * 0.8);

    // ---- 权重
    float slope = 1.0 - n.y;
    float wRock = max(sp.b, smoothstep(0.28, 0.45, slope + (fine - 0.5) * 0.06));
    float wPath = sp.r * (1.0 - wRock);
    float wDirt = sp.g * (1.0 - wRock) * (1.0 - wPath);
    // 草地边缘用噪声咬边，避免控制图的线性渐变
    float edgeN = (mid - 0.5) * 0.5;
    wPath = smoothstep(0.35, 0.65, wPath + edgeN * 0.6);
    wDirt = smoothstep(0.3, 0.7, wDirt + edgeN);
    vec3 col = grass;
    col = mix(col, dirt, wDirt);
    col = mix(col, path, wPath);
    col = mix(col, rock, wRock);
    // 草地被 GrassField 覆盖处稍压暗（草缝里是草丛深处）
    float under = sp.a * (1.0 - wRock) * (1.0 - wPath) * (1.0 - wDirt);
    col = mix(col, col * 0.62, under * 0.5);
    // 山顶积雪：平坦处先积，噪声咬边
    float snow = smoothstep(snow_y - 1.0, snow_y + 1.5, wp.y + (big - 0.5) * 3.0) * smoothstep(0.25, 0.7, n.y);
    col = mix(col, snow_color * (0.92 + fine * 0.08), snow);

    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = mix(0.92, 0.78, wPath);
    METALLIC = 0.0;
    SPECULAR = mix(0.25, 0.4, wRock);
}

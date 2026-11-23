// RuinsGround.shader — 时之遗迹岛面与岩壳（共用世界空间材质）
//
// 颜色全部程序化：世界空间多层噪声把草地 / 枯草 / 泥土 / 铺石 / 岩壁 混在一起，
// 权重来自 Lua 生成的控制图 splat_map（覆盖整块地形，UV 0..1）：
//   R = 铺石路   G = 泥土 / 碎石   B = 岩壁（崖面）   A = 草地密度（GrassField 也读这张）
// 崖面另外按法线坡度自动换岩石，岩层沿倾斜、带噪声扭曲的方向分布，不再是一圈圈水平色带。
// daynight_tint：昼夜模块统一写入，乘到最终颜色（与其他自定义材质一致）。
shader_type spatial;
render_mode shading_model_pbr, cull_back;
#include "res://Shaders/BLGL/RuinsFrost.shaderinc"
#include "res://Shaders/BLGL/RuinsContactAO.shaderinc"

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform vec3 daynight_tint = vec3(1.0);
// Shared celestial wind / artistic ground projection; disabled until atlas ready.
uniform sampler2D cloud_shadow_atlas : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float cloud_shadow_strength = 0.0;
uniform vec4 cloud_wind = vec4(0.0);
// sun X/Y, Z/Y; virtual cloud altitude metres; high-tier second tap
uniform vec4 cloud_shadow_projection = vec4(0.0,0.0,120.0,0.0);

// CLOUD_SHADOW_SHARED_BEGIN
float cloud_mask(vec2 point) {
    vec2 grid=point/150.0;
    vec2 cell=fract(grid);
    vec2 slope=cloud_shadow_projection.xy;
    float slant=length(slope);
    vec2 along=slope/max(slant,0.0001);
    vec2 local_shape=cell-vec2(0.5);
    // Keep atlas gutters fixed even when stretching near a low sun.
    float stretch_envelope=16.0*cell.x*(1.0-cell.x)*cell.y*(1.0-cell.y);
    local_shape-=along*dot(local_shape,along)*(1.0-1.0/(1.0+0.18*slant))*stretch_envelope;
    // 4x2 original cloud atlas; transparent gutters survive LOD2/3.
    vec2 tiles=vec2(4.0,2.0);
    vec2 uv=(mod(floor(grid),tiles)+vec2(0.004)+(local_shape+vec2(0.5))*0.992)/tiles;
    return textureLod(cloud_shadow_atlas,uv,3.0-cloud_shadow_projection.w).a;
}
vec3 cloud_illumination(vec3 position) {
    vec2 point=position.xz+cloud_shadow_projection.xy*clamp(cloud_shadow_projection.z-position.y,0.0,160.0)-cloud_wind.xy;
    float mask=cloud_mask(point);
    if (cloud_shadow_projection.w>0.5) {
        mask=0.5*(mask+cloud_mask(point+vec2(3.0,-2.0)));
    }
    float shade=smoothstep(0.05,0.92,mask);
    // Subtle artistic ALBEDO modulation, not a new light or physical GI.
    return vec3(1.0)+cloud_shadow_strength*((1.0-shade)*vec3(0.06,0.03,0.0)-shade*vec3(1.0,0.96,0.86));
}
// CLOUD_SHADOW_SHARED_END

uniform vec3 grass_dark = vec3(0.16, 0.30, 0.10);
uniform vec3 grass_light = vec3(0.36, 0.52, 0.20);
uniform vec3 grass_dry = vec3(0.55, 0.52, 0.28);
uniform vec3 dirt_color = vec3(0.36, 0.28, 0.20);
uniform vec3 path_color = vec3(0.62, 0.58, 0.51);
uniform vec3 rock_a = vec3(0.56, 0.54, 0.51);
uniform vec3 rock_b = vec3(0.40, 0.39, 0.40);
uniform vec3 rock_warm = vec3(0.62, 0.56, 0.47);
uniform vec3 deep_color = vec3(0.34, 0.35, 0.37);
uniform float deep_y = -11.5;
uniform float world_half = 84.0;
// XYZ is the island origin in metres. W selects voxel palette IDs in COLOR.r (shells store soil weight).
uniform vec4 ground_frame = vec4(0.0);
uniform float meadow_sun = 0.0;
uniform float snow_y = 31.0;
uniform vec3 snow_color = vec3(0.93, 0.94, 0.97);
// GrassField 可见距离（x=开始淡出，y=完全消失）。超出后地面直接呈现草冠色，
// 近处草根下的压暗随之退去，避免草叶消失处出现一圈深色接缝。x>=y 表示没有原生草。
uniform vec2 grass_far = vec2(46.0, 55.0);
uniform vec3 grass_canopy = vec3(0.36, 0.48, 0.19);

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

// 三向世界投影：陡坡也按实际米数取样，不把平面纹理拉成竖条。
float surfaceNoise(vec3 p, vec3 weights) {
    return vnoise(p.yz) * weights.x + vnoise(p.xz) * weights.y + vnoise(p.xy) * weights.z;
}

// 约 60cm 岩块的非规则断隙；返回块内差异与距边缘的相对距离。
vec2 rockCell(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float first = 8.0, second = 8.0, color = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 off = vec2(float(x), float(y));
            vec2 id = cell + off;
            vec2 point = off + vec2(hash2(id), hash2(id + 17.3)) - f;
            float d = dot(point, point);
            if (d < first) { second = first; first = d; color = hash2(id + 31.0); }
            else { second = min(second, d); }
        }
    }
    return vec2(color, sqrt(second) - sqrt(first));
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    vec3 wp = VERTEX - ground_frame.xyz;
    vec3 n = normalize(NORMAL);
    vec3 weights = pow(abs(n), vec3(4.0));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    // Keep the relief field quad-wide: do NOT move these samples into weight/LOD branches.
    vec3 dpdx = dFdx(wp), dpdy = dFdy(wp);
    float footprint = max(length(dpdx), length(dpdy));
    float detailFade = 1.0 - smoothstep(0.035, 0.14, footprint);
    float grainFade = 1.0 - smoothstep(0.012, 0.055, footprint);
    float chips = surfaceNoise(wp * 11.0, weights);
    float grain = surfaceNoise(wp * 45.0, weights);
    float relief = chips * 0.006 + grain * 0.0015;
    vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
    float det = dot(dpdx, r1);
    vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.000001);
    // 控制图按世界坐标取：第 0 行 = +Z（北）
    vec2 suv = vec2(wp.x + world_half, world_half - wp.z) / (2.0 * world_half);
    vec4 sp = texture(splat_map, suv);

    // Shared low-frequency fields remain at every distance (snow, blend edges and grass).
    float big = fbm(wp.xz * 0.045);
    float mid = fbm(wp.xz * 0.28 + 3.0);
    float fine = vnoise(wp.xz * 3.1);

    // ---- 权重：先决定实际可见的材质，再计算只用于颜色的昂贵细节。
    float slope = 1.0 - n.y;
    float wRock = max(sp.b, smoothstep(0.28, 0.45, slope + (fine - 0.5) * 0.06));
    // IslandShell 顶点 R 标记最上方薄土断缘。
    float soilLip = COLOR.r;
    float sand = 0.0;
    float canopyCover = 0.0;
    if (ground_frame.w > 0.5) {
        float id = floor(COLOR.r * 255.0 + 0.5);
        bool turf = id >= 115.0 && id <= 118.0;
        sand = id == 125.0 ? 1.0 : 0.0;
        soilLip = (id == 119.0 || id == 120.0 || (turf && n.y < 0.5)) ? 1.0 : sand;
        if (turf && n.y > 0.5) {
            float canopy = min(length(wp.xz-vec2(-20.5,0.5)),length(wp.xz-vec2(-17.0,-10.0)));
            canopy = min(canopy,min(length(wp.xz-vec2(0.0,-13.0)),length(wp.xz-vec2(19.0,-5.0))));
            canopyCover = 1.0-smoothstep(0.65,4.2,min(canopy,length(wp.xz-vec2(5.0,13.5))));
        }
    }
    wRock *= 1.0 - soilLip;
    float wPath = sp.r * (1.0 - wRock) * (1.0 - soilLip);
    float wDirt = max(sp.g, soilLip) * (1.0 - wRock) * (1.0 - wPath);
    float edgeN = (mid - 0.5) * 0.5;
    // 控制图是 0.5m 双线性，直接阈值会得到一圈模糊的软边。叠加米级与厘米级噪声
    // 再收窄过渡带：泥地边缘变成被草啃出的不规则齿边，铺石边缘带少量缺角。
    float edgeFine = (fine - 0.5) * 0.30 + (chips - 0.5) * 0.22 * detailFade;
    wPath = smoothstep(0.42, 0.58, wPath + edgeN * 0.6 + edgeFine * 0.45);
    wDirt = smoothstep(0.40, 0.60, wDirt + edgeN + edgeFine);
    vec3 col = vec3(0.0);
    float camDist = length(VERTEX - CAMERA_POSITION_WORLD);
    float canopyK = grass_far.y > grass_far.x ? smoothstep(grass_far.x, grass_far.y, camDist) : 1.0;
    // All branches below are derivative-free. Exact zero/one tests preserve blend boundaries.
    if (wRock < 1.0) {
        // ---- 草地：铺石缝里也用到草色，不仅是裸露草地。
        vec3 grass = mix(grass_dark, grass_light, clamp(big * 1.1 + mid * 0.35 - 0.25, 0.0, 1.0));
        grass = mix(grass, grass_dry, smoothstep(0.62, 0.78, fbm(wp.xz * 0.06 + 40.0)) * 0.55);
        grass *= 0.88 + fine * 0.22;
        // 远景草冠：没有草叶的距离上，地面要呈现"从上往下看草丛"的颜色，
        // 带 1–3m 的团簇明暗，而不是草根下的深色泥土。
        if (canopyK > 0.0) {
            float clumps = vnoise(wp.xz * 0.55) * 0.6 + vnoise(wp.xz * 1.7 + 9.0) * 0.4;
            vec3 canopy = grass_canopy * (0.80 + clumps * 0.36) * (0.92 + big * 0.16);
            canopy = mix(canopy, grass_dry * 0.95, smoothstep(0.62, 0.78, fbm(wp.xz * 0.06 + 40.0)) * 0.45);
            grass = mix(grass, canopy, canopyK);
        }
        col = grass;

        // ---- 泥土 / 碎石：被铺石或岩壁完全覆盖时跳过。
        if (wDirt > 0.0 && wPath < 1.0) {
            float pebble = smoothstep(0.63, 0.76, chips);
            vec3 dirt = mix(dirt_color,vec3(0.80,0.74,0.60),sand) * (0.85 + mid * 0.3);
            dirt *= 1.0 + (chips - 0.5) * 0.34 * detailFade + (grain - 0.5) * 0.18 * grainFade;
            dirt = mix(dirt, path_color * 0.72, pebble * 0.38 * detailFade);
            col = mix(col, dirt, wDirt);
        }

        // ---- 铺石路：保留原石板、窄缝及缝内草色。
        if (wPath > 0.0) {
            vec2 pc = wp.xz * 1.15;
            vec2 cell = floor(pc + vec2(0.0, floor(pc.x) * 0.5));
            vec2 f = fract(pc + vec2(0.0, floor(pc.x) * 0.5));
            float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
            float slab = hash2(cell);
            vec3 path = path_color * (0.84 + slab * 0.26) * (0.92 + fine * 0.12);
            path = mix(path * 0.55, path, smoothstep(0.02, 0.07, seam));
            path = mix(path, grass * 0.9, smoothstep(0.55, 0.85, mid) * 0.5 * (1.0 - smoothstep(0.03, 0.09, seam)));
            col = mix(col, path, wPath);
        }
    }

    // ---- 岩壁：只在实际贡献颜色时计算，近景岩层、风化与苔藓不变。
    if (wRock > 0.0) {
        float warp = fbm(wp.xz * 0.05 + vec2(wp.y * 0.03)) * 6.0;
        float strata = wp.y * 0.55 + dot(wp.xz, vec2(0.07, 0.045)) + warp;
        float band = vnoise(vec2(strata, 0.5)) * 0.65 + vnoise(vec2(strata * 3.7, 7.0)) * 0.35;
        vec3 rock = mix(rock_b, rock_a, band);
        rock = mix(rock, rock_warm, smoothstep(0.6, 0.85, fbm(wp.xz * 0.11 + wp.y * 0.07)) * 0.6);
        float rockFade = 1.0 - smoothstep(0.08, 0.30, footprint);
        // The old Voronoi terms already vanish at rockFade == 0; do not evaluate 27 cells there.
        vec2 cellDetail = vec2(0.5, 1.0);
        float crack = 0.0;
        if (rockFade > 0.0) {
            vec3 rp = wp * 1.6;
            cellDetail = vec2(0.0);
            if (weights.x > 0.0) { cellDetail += rockCell(rp.yz) * weights.x; }
            if (weights.y > 0.0) { cellDetail += rockCell(rp.xz) * weights.y; }
            if (weights.z > 0.0) { cellDetail += rockCell(rp.xy) * weights.z; }
            crack = 1.0 - smoothstep(0.012, 0.045 + footprint * 1.6, cellDetail.y);
        }
        rock *= 0.92 + (cellDetail.x - 0.5) * 0.20 * rockFade;
        rock *= 1.0 - crack * 0.19 * rockFade + (chips - 0.5) * 0.26 * detailFade + (grain - 0.5) * 0.13 * grainFade;
        float mossFacing = smoothstep(0.35, 0.75, n.y + 0.6);
        if (mossFacing > 0.0) {
            float mossy = smoothstep(0.55, 0.75, fbm(vec2(wp.x - wp.z, wp.y * 2.0) * 0.35)) * mossFacing;
            rock = mix(rock, grass_dark * 1.2, mossy * 0.45);
        }
        // 复用已有低频场，不新增纹理/噪声采样；大块深浅只作用于崖面。
        float cliff = 1.0 - smoothstep(0.15, 0.60, n.y);
        rock *= mix(1.0, mix(0.90, 1.06, smoothstep(0.22, 0.70, big)), cliff);
        // 雨水沿陡崖下淌留下的竖向水痕：沿崖面水平方向取样、竖向拉长 8 倍。
        // 远处仍可读，让岛侧不再是一整片均匀的灰。
        float along = wp.z * weights.x + wp.x * weights.z + (wp.x + wp.z) * 0.5 * weights.y;
        float streak = vnoise(vec2(along * 1.9, wp.y * 0.24 + warp * 0.3)) * 0.7 + vnoise(vec2(along * 5.3, wp.y * 0.5)) * 0.3;
        float stain = smoothstep(0.52, 0.86, streak) * cliff;
        rock *= 1.0 - stain * 0.20;
        rock = mix(rock, rock * vec3(1.04, 1.0, 0.92), (1.0 - smoothstep(0.10, 0.30, streak)) * cliff * 0.5);
        // 深部仍是灰岩而非另一圈深色材料；11m宽过渡随空间低频场偏移。
        float deepHeight = wp.y + (big - 0.47) * 10.0 + (warp - 2.8) * 0.45;
        float deepMix = (1.0 - smoothstep(deep_y - 5.0, deep_y + 6.0, deepHeight)) * 0.50 * cliff;
        rock = mix(rock, deep_color, deepMix);
        col = mix(col, rock, wRock);
    }
    // 草地被 GrassField 覆盖处稍压暗（草缝里是草丛深处）；草叶淡出后不再压暗。
    float under = sp.a * (1.0 - wRock) * (1.0 - wPath) * (1.0 - wDirt) * (1.0 - canopyK);
    col = mix(col, col * 0.62, under * 0.5);
    // 山顶积雪：平坦处先积，噪声咬边
    float snow = smoothstep(snow_y - 1.0, snow_y + 1.5, wp.y + (big - 0.5) * 3.0) * smoothstep(0.25, 0.7, n.y);
    col = mix(col, snow_color * (0.92 + fine * 0.08), snow);

    // 毫米级凹凸直接扰动世界法线；梯度已在所有非一致分支之前求好。
    float bumpWeight = max(wRock, wDirt) * (1.0 - snow);
    NORMAL = normalize(n - clamp(grad, vec3(-0.35), vec3(0.35)) * detailFade * bumpWeight);
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = clamp(mix(0.92, 0.78, wPath) + (chips - 0.5) * 0.12 * bumpWeight * detailFade, 0.0, 1.0);
    METALLIC = 0.0;
    SPECULAR = mix(0.25, 0.4, wRock);
    float ice = ruins_frost(VERTEX, NORMAL);
    // Frost is evaluated after all derivatives; a zero mask needs no vein sin/pow or PBR mixes.
    if (ice != 0.0) {
        float iceVeins = pow(abs(sin(VERTEX.x*7.0 + sin(VERTEX.z*4.0))), 18.0);
        ALBEDO = mix(ALBEDO, vec3(0.30,0.56,0.68) + vec3(0.26)*iceVeins, ice*0.85);
        ROUGHNESS = mix(ROUGHNESS, 0.19 + iceVeins*0.14, ice);
        SPECULAR = mix(SPECULAR, 0.7, ice);
    }
    // Explicit LOD only, after unrelated ground derivatives/frost.
    if (cloud_shadow_strength>0.0 && n.y>0.35) {
        ALBEDO*=mix(vec3(1.0),cloud_illumination(VERTEX),smoothstep(0.35,0.75,n.y));
    }
    AO=ruins_contact_ao(VERTEX,n,0.0,CAMERA_POSITION_WORLD);
    if (canopyCover > 0.0) {
        float sunPatch = smoothstep(0.37,0.67,vnoise(wp.xz*0.63+vec2(TIME*0.055,0.0)));
        ALBEDO *= mix(vec3(1.0),mix(vec3(0.83,0.91,0.97),vec3(1.14,1.10,0.99),sunPatch),canopyCover*meadow_sun);
        AO *= 1.0-0.22*canopyCover;
    }
}

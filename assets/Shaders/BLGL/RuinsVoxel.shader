// RuinsVoxel.shader — 时之遗迹静态体素的调色板 PBR 材质
//
// 几何负责轮廓；显式启用的砌石层负责厘米级石缝，远处按像素足迹淡出。
// 法阵、金属、雕像与谜题沿用原调色板，不给每个体素描边。
// 断面（体素内部被打出来的面）自动用调色板的断面色。
shader_type spatial;
render_mode shading_model_pbr, cull_back;
#include "res://Shaders/BLGL/RuinsFrost.shaderinc"

uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"

uniform float voxel_size = 0.25;
uniform float grime = 0.18;       // 风化保持克制，避免墙面像迷彩
uniform float jitter = 0.015;     // 每格亮度抖动（很轻，避免格子感）
uniform float bevel = 0.0;        // 格边压暗（0 = 不画格缝）
uniform vec3 daynight_tint = vec3(1.0);
uniform float masonry_mode = 0.0;
uniform float wall_radius = 51.0;
// 可破坏体积被准星选中时的外轮廓光（碎时 = 红）
uniform float hover = 0.0;
uniform vec4 hover_color = vec4(1.0, 0.30, 0.24, 1.0);

varying vec3 opos;
varying vec3 object_normal;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

float h31(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float n3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(h31(i), h31(i + vec3(1, 0, 0)), u.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), u.x), u.y);
    float b = mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), u.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), u.x), u.y);
    return mix(a, b, u.z);
}

void vertex() {
    opos = VERTEX;
    object_normal = NORMAL;
}

void fragment() {
    float idx = voxel_palette_index(COLOR);
    vec3 albedo = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_ALBEDO)).rgb);
    vec3 cut = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_CUT)).rgb);
    vec4 pbr = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_PBR));
    vec4 emi = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_EMISSIVE));
    float interior = step(0.5, COLOR.g);
    vec3 base = mix(albedo, cut, interior);

    vec3 n = normalize(NORMAL);
    vec3 wp = VERTEX;
    vec3 dpdx = dFdx(wp), dpdy = dFdy(wp);
    float footprint = max(length(dpdx), length(dpdy));
    float grainFade = 1.0 - smoothstep(0.025, 0.12, footprint);
    float detailFade = 1.0 - smoothstep(0.08, 0.30, footprint);
    float surfaceFade = 1.0 - smoothstep(0.04, 0.16, footprint);
    // 石材限定：100..108，142..144。金属、符文、草皮不受石缝影响。
    float stone = step(99.5, idx) * (1.0 - step(108.5, idx));
    float rubble = step(141.5, idx) * (1.0 - step(144.5, idx));
    float tile = step(138.5, idx) * (1.0 - step(141.5, idx));
    float mineral = max(max(stone, rubble), tile);
    float marble = step(104.5, idx) * (1.0 - step(106.5, idx));

    // Keep ALL relief inputs quad-wide, including non-marble mineral veins.
    // Their one-order derivatives must not consume a field conditionally sampled per pixel.
    float g = n3(wp * 0.35) * 0.6 + n3(wp * 1.3 + 7.0) * 0.4;
    float veins = n3(wp * vec3(2.2, 5.0, 2.2) + vec3(g * 3.0));
    float pores = n3(wp * 24.0);
    float relief = (pores * 0.0025 + veins * 0.003) * mineral;
    vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
    float det = dot(dpdx, r1);
    vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.000001);

    // Only a draw-uniform switch may guard the masonry derivatives. Do not add stone/LOD here.
    float horizontal = 0.0;
    float aa = 0.001;
    if (masonry_mode >= 0.5) {
        horizontal = abs(n.x) > abs(n.z) ? wp.z : wp.x;
        if (masonry_mode > 1.5 && masonry_mode < 2.5) {
            horizontal = mod(atan(wp.z, wp.x) + 6.2831853, 6.2831853) * wall_radius;
        }
        aa = max(fwidth(horizontal), fwidth(wp.y)) * 0.65 + 0.001;
    }

    // 大块两层风化不随距离变纯色。
    float shade = 1.0 + (g - 0.5) * 2.0 * grime;
    // 朝下的面略暗、朝上的面略亮（积尘 / 背光）
    shade *= 1.0 + n.y * 0.05;

    // 体素格内坐标：关闭 jitter/bevel 时不做其专用计算。
    if (jitter != 0.0 || bevel != 0.0) {
        vec3 cellP = opos / voxel_size;
        vec3 objectN = normalize(object_normal);
        if (jitter != 0.0) {
            vec3 cell = floor(cellP - objectN * 0.5);
            shade *= 1.0 + (h31(cell) - 0.5) * 2.0 * jitter;
        }
        if (bevel != 0.0) {
            vec3 f = fract(cellP);
            vec3 an = abs(objectN);
            vec2 uv = (an.x > 0.5) ? f.yz : ((an.y > 0.5) ? f.xz : f.xy);
            float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
            shade *= 1.0 - bevel * (1.0 - smoothstep(0.0, 0.12, edge));
        }
    }

    // Grain affects color/roughness only, never the relief derivatives above.
    float grain = 0.5;
    if (mineral > 0.0 && grainFade > 0.0) { grain = h31(floor(wp * 40.0)); }
    shade *= 1.0 + (grain - 0.5) * 0.10 * grainFade * mineral;

    // 环墙采用 1.5m × 0.75m 砌石，浅缝无几何挖槽。
    float masonry = step(0.5, masonry_mode) * stone * (1.0 - smoothstep(0.55, 0.85, abs(n.y)));
    float jointK = 0.0;
    if (masonry > 0.0 && detailFade > 0.0) {
        float blockScale = masonry_mode > 1.5 ? 1.5 : 1.0;
        float row = floor(wp.y * 2.0 / blockScale);
        vec2 blockUV = vec2(horizontal / blockScale + mod(row, 2.0) * 0.5, wp.y * 2.0 / blockScale);
        vec2 blockF = fract(blockUV);
        vec2 distances = min(blockF, vec2(1.0) - blockF) * vec2(1.0, 0.5) * blockScale;
        float jointDistance = min(distances.x, distances.y);
        float joint = 1.0 - smoothstep(0.008, 0.018 + aa, jointDistance);
        float lip = smoothstep(0.015, 0.027 + aa, jointDistance)
            * (1.0 - smoothstep(0.035, 0.055 + aa, jointDistance));
        jointK = joint * detailFade * masonry;
        shade *= 1.0 - 0.16 * jointK + 0.025 * lip * detailFade * masonry;
    }

    // 中央庭院：仅石板需要这两次 n3。磨耗保留到远景，已淡出的裂纹不算。
    if (tile > 0.0) {
        float slabNoise = n3(wp * vec3(2.8, 1.0, 2.8));
        float fissure = 0.0;
        if (detailFade > 0.0 && slabNoise > 0.50) {
            float fissureField = sin(wp.x * 2.1 + wp.z * 1.3 + n3(wp * 0.8) * 9.0);
            fissure = (1.0 - smoothstep(0.025, 0.07 + footprint * 1.2, abs(fissureField)))
                * smoothstep(0.50, 0.66, slabNoise) * detailFade;
        }
        shade *= 1.0 + tile * ((slabNoise - 0.5) * 0.22 - fissure * 0.23);
    }
    // 原矿脉/细孔颜色与近景法线不变；只有已为零的颜色贡献跳过。
    if (marble > 0.0) {
        float patina = smoothstep(0.57, 0.78, veins);
        base = mix(base, base * vec3(0.80, 0.82, 0.86), patina * 0.30 * marble);
    }
    if (mineral > 0.0 && surfaceFade > 0.0) {
        shade *= 1.0 - smoothstep(0.64, 0.82, pores) * 0.14 * mineral * surfaceFade;
    }
    // 世界空间表面梯度已在非一致分支前求好，不依赖体素切线流。
    NORMAL = normalize(n - clamp(grad, vec3(-0.22), vec3(0.22)) * surfaceFade);
    float emiK = emi.a;
    ALBEDO = base * shade * daynight_tint;
    ROUGHNESS = clamp(pbr.r + 0.06 * jointK + (grain - 0.5) * 0.05 * grainFade * mineral, 0.0, 1.0);
    METALLIC = pbr.g;
    SPECULAR = pbr.b;
    EMISSION = srgb_to_linear(emi.rgb) * emiK * 16.0;
    float ice = ruins_frost(VERTEX, NORMAL);
    // Frost is evaluated after all derivatives; a zero mask needs no vein sin/pow or PBR mixes.
    if (ice != 0.0) {
        float iceVeins = pow(abs(sin(VERTEX.x*7.0 + sin(VERTEX.z*4.0))), 18.0);
        ALBEDO = mix(ALBEDO, vec3(0.30,0.56,0.68) + vec3(0.26)*iceVeins, ice*0.85);
        ROUGHNESS = mix(ROUGHNESS, 0.19 + iceVeins*0.14, ice);
        SPECULAR = mix(SPECULAR, 0.7, ice);
    }
    if (hover > 0.0) {
        vec3 view = normalize(CAMERA_POSITION_WORLD - VERTEX);
        float fres = pow(1.0 - clamp(dot(NORMAL, view), 0.0, 1.0), 3.0);
        ALBEDO = mix(ALBEDO, ALBEDO * 0.85 + hover_color.rgb * 0.15, hover);
        EMISSION += hover_color.rgb * (0.12 + fres * 2.4) * hover;
    }
}

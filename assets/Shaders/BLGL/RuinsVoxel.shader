// RuinsVoxel.shader — 时之遗迹静态体素的调色板 PBR 材质
//
// 在调色板查表的基础上加两层细节，让 0.25m 体素看起来不像"纯色积木"：
//   1. 世界空间低频噪声做大块明暗起伏（风化、污渍），跨体素连续，不会逐格跳色
//   2. 每格极轻的亮度抖动（可选格边压暗，默认关：不画体素之间的接缝）
// 断面（体素内部被打出来的面）自动用调色板的断面色。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"

uniform float voxel_size = 0.25;
uniform float grime = 0.28;       // 大块污渍强度
uniform float jitter = 0.015;     // 每格亮度抖动（很轻，避免格子感）
uniform float bevel = 0.0;        // 格边压暗（0 = 不画格缝）
uniform vec3 daynight_tint = vec3(1.0);

varying vec3 opos;

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
    // 大块风化：世界空间，两层
    float g = n3(wp * 0.35) * 0.6 + n3(wp * 1.3 + 7.0) * 0.4;
    float shade = 1.0 + (g - 0.5) * 2.0 * grime;
    // 朝下的面略暗、朝上的面略亮（积尘 / 背光）
    shade *= 1.0 + n.y * 0.05;

    // 体素格内坐标
    vec3 cellP = opos / voxel_size;
    vec3 cell = floor(cellP - n * 0.5);
    vec3 f = fract(cellP);
    vec3 an = abs(n);
    vec2 uv = (an.x > 0.5) ? f.yz : ((an.y > 0.5) ? f.xz : f.xy);
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    shade *= 1.0 + (h31(cell) - 0.5) * 2.0 * jitter;
    shade *= 1.0 - bevel * (1.0 - smoothstep(0.0, 0.12, edge));

    float emiK = emi.a;
    ALBEDO = base * shade * daynight_tint;
    ROUGHNESS = pbr.r;
    METALLIC = pbr.g;
    SPECULAR = pbr.b;
    EMISSION = srgb_to_linear(emi.rgb) * emiK * 16.0;
}

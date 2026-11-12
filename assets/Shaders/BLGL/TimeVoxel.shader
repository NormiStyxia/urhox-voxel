// TimeVoxel.shader — 时之物件的体素材质（调色板查表 PBR + 时间法术表现）
//
// mode 0 = 普通石材；未复原且瞄准时仅有轻微外轮廓提示，不描逐格棱线
// mode 1 = 冻结：色调推向蓝 / 蓝紫，低粗糙度，菲涅尔冰光，逐格闪烁
// mode 2 = 回溯：强蓝发光，自上而下的回扫线，金色闪点
// strength 0..1 控制效果强度（淡入 / 淡出）。符脉图案按物体空间计算，碎块飞散时图案跟着碎块走。
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"

uniform float mode = 0.0;
uniform float strength = 1.0;
uniform float hover = 0.0;
uniform float restored = 0.0;
uniform float voxel_size = 0.25;
uniform vec4 blue_color = vec4(0.22, 0.46, 1.0, 1.0);
uniform vec4 violet_color = vec4(0.42, 0.34, 1.0, 1.0);
uniform vec4 gold_color = vec4(1.0, 0.74, 0.30, 1.0);

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
    float rough = pbr.r;
    float metal = pbr.g;
    vec3 emission = srgb_to_linear(emi.rgb) * emi.a * 16.0;

    // 体素格内坐标：取法线所在面的两个切向分量，算到格边的距离
    vec3 n = normalize(NORMAL);
    vec3 cellP = opos / voxel_size;
    vec3 cell = floor(cellP - normalize(object_normal) * 0.5);
    vec3 f = fract(cellP);
    vec3 an = abs(normalize(object_normal));
    vec2 uv = (an.x > 0.5) ? f.yz : ((an.y > 0.5) ? f.xz : f.xy);
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float h = h31(cell);
    vec3 view = normalize(CAMERA_POSITION_WORLD - VERTEX);
    float fres = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
    float s = clamp(strength, 0.0, 1.0);

    if (mode < 0.5) {
        // 无常驻逐格发光，也不把复原成功提示铺在全部体素边缘。
        emission *= mix(1.0, 0.12, restored);
        emission += blue_color.rgb * fres * clamp(hover, 0.0, 1.0) * 0.22 * s * (1.0 - restored);
    } else if (mode < 1.5) {
        // 冻结：冷色调 + 冰面高光
        vec3 ice = mix(blue_color.rgb, violet_color.rgb, 0.35 + 0.3 * h);
        base = mix(base, base * 0.35 + ice * 0.55, 0.75 * s);
        rough = mix(rough, 0.18, s);
        metal = mix(metal, 0.0, s);
        float spark = step(0.97, fract(h * 37.0 + floor(TIME * 3.0) * 0.618));
        emission += ice * (fres * 1.6 + 0.12) * s;
        emission += vec3(0.85, 0.92, 1.0) * spark * (1.0 - smoothstep(0.05, 0.15, edge)) * 2.0 * s;
        emission += ice * (1.0 - smoothstep(0.02, 0.06, edge)) * 0.6 * s;
    } else {
        // 回溯：蓝光 + 回扫线 + 金色闪点
        float scan = fract(-VERTEX.y * 0.35 + TIME * 1.6);
        float line = smoothstep(0.88, 1.0, scan);
        float spark = step(0.93, fract(h * 13.0 + floor(TIME * 8.0) * 0.371));
        base = mix(base, base * 0.6 + blue_color.rgb * 0.3, 0.6 * s);
        emission += blue_color.rgb * (0.55 + fres * 2.0 + line * 2.5) * s;
        emission += gold_color.rgb * spark * 2.5 * s;
        emission += gold_color.rgb * (1.0 - smoothstep(0.02, 0.07, edge)) * 0.8 * s;
    }

    // 石材表面有细颗粒，但不是按体素单元描边。
    float stone = step(99.5, idx) * (1.0 - step(108.5, idx));
    float footprint = max(length(dFdx(VERTEX)), length(dFdy(VERTEX)));
    float grain = h31(floor(opos * 32.0));
    base *= 1.0 + (grain - 0.5) * 0.10 * stone * (1.0 - smoothstep(0.025, 0.09, footprint));
    ALBEDO = base;
    ROUGHNESS = rough;
    METALLIC = metal;
    SPECULAR = pbr.b;
    EMISSION = emission;
}

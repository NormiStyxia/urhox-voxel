// RuinsVoxel.shader — 时之遗迹静态体素的调色板 PBR 材质
//
// 几何负责轮廓；显式启用的砌石层负责厘米级石缝，远处按像素足迹淡出。
// 法阵、金属、雕像与谜题沿用原调色板，不给每个体素描边。
// 断面（体素内部被打出来的面）自动用调色板的断面色。
shader_type spatial;
render_mode shading_model_pbr, cull_back;
#include "res://Shaders/BLGL/RuinsFrost.shaderinc"
#include "res://Shaders/BLGL/RuinsContactAO.shaderinc"
#include "res://Shaders/BLGL/RuinsGroundContact.shaderinc"

uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"

uniform float voxel_size = 0.25;
uniform float grime = 0.18;       // 风化保持克制，避免墙面像迷彩
uniform float jitter = 0.015;     // 每格亮度抖动（很轻，避免格子感）
uniform float bevel = 0.0;        // 格边压暗（0 = 不画格缝）
uniform vec3 daynight_tint = vec3(1.0);
uniform float masonry_mode = 0.0;
uniform float wall_radius = 51.0;
uniform vec3 home_stone_origin = vec3(0.0);
// Only opaque, non-destructible volumes made entirely from home limestone set this flag.
uniform float dressed_stone_draw = 0.0;
// Windows volumes also carry the upper-storey marble slots. This flag remaps
// those shared slots to the house's warm dry-stone finish without touching ruins.
uniform float home_house_draw = 0.0;
uniform vec3 meadow_origin = vec3(0.0);
uniform float meadow_sun = 0.0;
uniform float window_light = 0.0;
// XYZ: world-space cross-section centre; W=1 only on private near-joint materials.
uniform vec4 wood_center = vec4(0.0);
// 可破坏体积被准星选中时的外轮廓光（碎时 = 红）
uniform float hover = 0.0;
uniform vec4 hover_color = vec4(1.0, 0.30, 0.24, 1.0);

varying vec3 opos;
varying vec3 object_normal;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

float cornerHash(vec3 p) {
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

float h31(vec3 p) {
    return cornerHash(fract(p * vec3(0.1031, 0.1030, 0.0973)));
}

float n3(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    // Each axis has just two hash inputs across the eight corners of the cell.
    vec3 scale = vec3(0.1031, 0.1030, 0.0973);
    vec3 lo = fract(cell * scale);
    vec3 hi = fract((cell + 1.0) * scale);
    float a = mix(mix(cornerHash(lo), cornerHash(vec3(hi.x, lo.yz)), u.x),
                  mix(cornerHash(vec3(lo.x, hi.y, lo.z)), cornerHash(vec3(hi.xy, lo.z)), u.x), u.y);
    float b = mix(mix(cornerHash(vec3(lo.xy, hi.z)), cornerHash(vec3(hi.x, lo.y, hi.z)), u.x),
                  mix(cornerHash(vec3(lo.x, hi.yz)), cornerHash(hi), u.x), u.y);
    return mix(a, b, u.z);
}

void vertex() {
    opos = VERTEX;
    object_normal = NORMAL;
}

// Only the receiver close to a real foot or overhang loses indirect light.
float home_pillar_occlusion(vec3 p, vec3 n, vec2 center, float foot, float neckY) {
    vec2 d=abs(p.xz-center);
    float r=max(d.x,d.y);
    if (r>foot+0.16 || p.y<1.74 || p.y>neckY+0.02) { return 0.0; }
    float floorContact=(1.0-smoothstep(0.0,0.14,max(0.0,r-foot)))
        *(1.0-smoothstep(0.012,0.10,abs(p.y-1.75)));
    float support=(1.0-smoothstep(0.50,0.71,r))*(1.0-smoothstep(0.015,0.14,abs(p.y-neckY)));
    return max(floorContact*0.14,support*(1.0-smoothstep(0.1,0.7,n.y))*0.22);
}

void fragment() {
    float idx = voxel_palette_index(COLOR);
    vec3 albedo = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_ALBEDO)).rgb);
    vec4 pbr = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_PBR));
    vec4 emi = vec4(0.0);
    vec3 base = albedo;
    float homeRoughness = 0.0;
    if (dressed_stone_draw<0.5) {
        vec3 cut = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_CUT)).rgb);
        emi = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_EMISSIVE));
        base = mix(albedo,cut,step(0.5,COLOR.g));
    }

    vec3 n = normalize(NORMAL);
    vec3 wp = VERTEX;
    // Derivatives are evaluated before any house/material branch so the Web
    // quad stays coherent when upper-wall patches fade with footprint.
    vec3 dpdx = dFdx(wp), dpdy = dFdy(wp);
    float footprint = max(length(dpdx), length(dpdy));
    float houseWallSeam = 0.0;
    float houseWallPatch = 0.0;
    float houseWallRoughness = 0.0;
    float houseWallAO = 1.0;
    if (home_house_draw > 0.5 && (idx==105.0 || idx==106.0)) {
        float blockTint = h31(floor(wp * vec3(1.15, 2.4, 1.15) + vec3(idx)));
        vec3 warmStone = srgb_to_linear(vec3(0.63, 0.60, 0.54));
        base = mix(base, warmStone, 0.92);
        base *= 0.91 + blockTint * 0.15;
        homeRoughness = 0.76 - pbr.r;
    }
    float grainFade = 1.0 - smoothstep(0.025, 0.12, footprint);
    float detailFade = 1.0 - smoothstep(0.08, 0.30, footprint);
    float surfaceFade = 1.0 - smoothstep(0.04, 0.16, footprint);
    // 石材限定：100..108，142..144。金属、符文、草皮不受石缝影响。
    float stone = step(99.5, idx) * (1.0 - step(108.5, idx));
    float rubble = step(141.5, idx) * (1.0 - step(144.5, idx));
    float tile = step(138.5, idx) * (1.0 - step(141.5, idx));
    float mineral = max(max(stone, rubble), tile);
    float marble = step(104.5, idx) * (1.0 - step(106.5, idx));
    bool dressed = idx >= 192.0 && idx <= 197.0;

    // Keep ALL relief inputs quad-wide, including non-marble mineral veins.
    // Their one-order derivatives must not consume a field conditionally sampled per pixel.
    float g = n3(wp * 0.35);
    float veins = g;
    if (dressed_stone_draw<0.5) {
        g = g * 0.6 + n3(wp * 1.3 + 7.0) * 0.4;
        veins = n3(wp * vec3(2.2, 5.0, 2.2) + vec3(g * 3.0));
    }
    float pores = n3(wp * 24.0);
    float relief = (pores * 0.0025 + veins * 0.003) * mineral;
    if (dressed) { relief = pores * 0.0007 + veins * 0.0012; }
    vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
    float det = dot(dpdx, r1);
    vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.000001);

    // Exclusive palette selection supplied by HomeHouseUpper. Reuse the
    // existing low-frequency fields: no new texture reads or noise octaves.
    if (home_house_draw > 0.5 && (idx==240.0 || idx==241.0)) {
        vec3 p = wp-home_stone_origin;
        bool frontFace = abs(n.z)>abs(n.x);
        vec3 tangent = frontFace ? vec3(1,0,0) : vec3(0,0,1);
        float along = frontFace ? p.x : p.z;
        float facing = 1.0-smoothstep(0.50,0.70,abs(n.y));
        float nearWall = 1.0-smoothstep(0.035,0.16,footprint);
        float blockFade = 1.0-smoothstep(0.12,0.35,footprint);
        float spread = max(0.001,footprint*0.5);
        // Follow the actual timber bays, not an all-over plaster brick grid.
        float frameU = frontFace ? mod(p.x+16.0+1.5,3.0)-1.5 : p.z-10.0;
        float frameV = abs(p.y-3.875)<abs(p.y-6.5) ? p.y-3.875 : p.y-6.5;
        if (p.y>=6.75) {
            float cx = p.x < -11.25 ? -13.75 : (p.x > -5.75 ? -3.25 : -8.5);
            bool central = cx== -8.5;
            frameU = frontFace ? p.x-cx : p.z-10.0;
            float baseY = central ? 7.25 : 7.5;
            float headY = central ? 8.625 : 8.25;
            frameV = abs(p.y-baseY)<abs(p.y-headY) ? p.y-baseY : p.y-headY;
        }
        float edgeU = abs(frameU)-0.0625;
        float edgeV = abs(frameV)-0.0625;
        float frameEdge = min(edgeU,edgeV);
        float frameSeam = (1.0-smoothstep(0.0,0.045+spread,max(0.0,frameEdge)))
            *0.045/(0.045+spread)*nearWall*facing;
        vec3 frameSlope = edgeU<edgeV ? tangent*sign(frameU) : vec3(0,sign(frameV),0);
        grad += frameSlope*0.045*frameSeam;

        houseWallPatch = idx==241.0 ? facing : 0.0;
        if (idx==241.0 && p.z<7.5 && frontFace) {
            vec2 chipUV = p.y>6.75 ? (p.xy-vec2(-10.8125,7.9375))/vec2(0.375,0.50)
                : vec2(min(abs(p.x+13.875)/0.66,abs(p.x+5.875)/0.53),(p.y-4.125)/0.42);
            float chippedEdge = length(chipUV)+(veins-0.5)*0.30;
            houseWallPatch *= 1.0-smoothstep(0.65,1.0,chippedEdge);
        }
        if (idx==241.0) {
            base = mix(srgb_to_linear(vec3(0.73,0.71,0.68)),base,houseWallPatch);
            homeRoughness = mix(0.86,pbr.r,houseWallPatch)-pbr.r;
        }
        vec2 cell = vec2(along/0.625,p.y/0.375);
        cell.x += mod(floor(cell.y),2.0)*0.5;
        vec2 f = fract(cell)-0.5;
        vec2 edges = (vec2(0.5)-abs(f))*vec2(0.625,0.375);
        float joint = (1.0-smoothstep(0.003,0.015+spread,min(edges.x,edges.y)))
            *0.012/(0.012+spread)*nearWall*houseWallPatch;
        vec3 jointSlope = edges.x<edges.y ? tangent*sign(f.x) : vec3(0,sign(f.y),0);
        grad -= jointSlope*joint*0.11;
        float blockTint = h31(vec3(floor(cell),241.0));
        base *= 1.0+(g-0.5)*0.10+(blockTint-0.5)*0.12*houseWallPatch*blockFade;
        houseWallSeam = frameSeam*0.7+joint*1.5;
        houseWallRoughness = (veins-0.5)*0.055+0.035*joint;
        houseWallAO = 1.0-max(frameSeam*0.13,joint*0.16);
        // Broad, shallow trowel undulation; analytic slope avoids conditional
        // derivatives and fades before it becomes subpixel grain.
        float phaseU = along*5.1+p.y*0.8;
        float phaseV = p.y*4.3-along*0.6;
        // Meter-scale plaster passes survive normal play distance; the patch
        // transitions stay continuous rather than adding granular speckle.
        float trowel = sin(phaseU+veins*1.8)*sin(phaseV+g*2.0);
        base *= 1.0+trowel*0.065*blockFade*(1.0-houseWallPatch);
        grad += (tangent*cos(phaseU)*0.025+vec3(0,cos(phaseV)*0.018,0))
            *nearWall*facing*(1.0-houseWallPatch*0.45);
    }

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
    // Upper plaster joints are shallow value breaks, never black outlines.
    shade *= 1.0 - 0.11 * houseWallSeam;

    // 体素格内坐标：关闭 jitter/bevel 时不做其专用计算。
    if (!dressed && (jitter != 0.0 || bevel != 0.0)) {
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
    // 每块砌石的随机值（苔石槽位按它给裸石配色，融进周围的 A/B/C 石块）。
    float blockHash = h31(floor(wp * vec3(1.0, 2.0, 1.0)));
    if (masonry > 0.0 && detailFade > 0.0) {
        float blockScale = masonry_mode > 1.5 ? 1.5 : 1.0;
        float row = floor(wp.y * 2.0 / blockScale);
        vec2 blockUV = vec2(horizontal / blockScale + mod(row, 2.0) * 0.5, wp.y * 2.0 / blockScale);
        vec2 blockF = fract(blockUV);
        blockHash = h31(vec3(floor(blockUV), 7.0));
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
    // 苔石槽位只给出"可能长苔"的区域；真正的苔斑在石面上按噪声生长，
    // 朝上的面、砌缝更容易积苔，块状区域的直边被打散成不规则斑块，不再像迷彩色块。
    float mossK = 0.0;
    float mossField = 0.0;
    if (dressed_stone_draw < 0.5 && COLOR.g < 0.5 && idx >= 99.5 && idx <= 104.5) {
        // 一个连续的世界空间生长场，苔石槽位只是把它抬高。槽位边界本身不画出来：
        // 块内只有一部分长苔，块外紧邻的普通石面也有零星苔点，体素块的直角轮廓被打散。
        // 竖直墙面上噪声沿 Y 拉长，形成顺着雨水往下淌的苔痕。
        vec3 mp = wp * vec3(1.6, mix(0.75, 1.6, abs(n.y)), 1.6);
        // 普通石块只复用已求好的 g/veins（零额外噪声），只有苔石槽位才多采两次 n3。
        mossField = veins * 0.55 + g * 0.45 + 0.04;
        if (idx == 104.0) {
            mossField = n3(mp + vec3(3.1, 7.7, 1.3)) * 0.62 + n3(wp * 5.2 + 11.0) * 0.38;
        }
        float growth = mossField + max(n.y, 0.0) * 0.20 - max(-n.y, 0.0) * 0.20
            + (idx == 104.0 ? jointK * 0.22 : jointK * 0.10 - 0.30);
        mossK = smoothstep(0.50, 0.64, growth);
        if (idx == 104.0) {
            vec3 bare = srgb_to_linear(mix(vec3(0.79, 0.76, 0.70), vec3(0.72, 0.72, 0.69), blockHash));
            float damp = smoothstep(0.38, 0.50, growth) * (1.0 - mossK);
            base = bare * (1.0 - 0.14 * damp);
        }
        if (mossK > 0.0) {
            // 苔色：朝上受光的苔偏黄绿、垂面与背阴处偏深橄榄；块内色调变化走低频，不做像素噪点。
            float tone = smoothstep(0.25, 0.85, n3(wp * 2.3 + 5.0));
            vec3 mossShade = mix(vec3(0.24, 0.31, 0.14), vec3(0.33, 0.40, 0.17), tone);
            vec3 mossSun = mix(vec3(0.40, 0.47, 0.20), vec3(0.52, 0.55, 0.25), tone);
            vec3 moss = srgb_to_linear(mix(mossShade, mossSun, smoothstep(0.2, 0.9, n.y)));
            // 苔层边缘变薄、透出石色。
            float thick = smoothstep(0.0, 0.6, mossK);
            base = mix(base, moss, mossK * (0.55 + 0.45 * thick));
        }
    }
    if (mineral > 0.0 && surfaceFade > 0.0) {
        shade *= 1.0 - smoothstep(0.64, 0.82, pores) * 0.14 * mineral * surfaceFade;
    }
    // ---- 落地风化（反照率，正午直射光下也能读出）：墙脚返潮带、溅泥、根部苔，
    // 加上旧石块顶面的积尘/地衣。只复用已有的低频噪声 g/veins/pores，额外开销是一次高度查表。
    float oldStone = step(99.5, idx) * (1.0 - step(104.5, idx));
    bool plaster = home_house_draw > 0.5 && (idx == 240.0 || idx == 241.0);
    float weatherable = max(max(mineral, dressed ? 1.0 : 0.0), plaster ? 0.7 : 0.0) * (1.0 - 0.5 * tile);
    float groundDist = 1000.0;
    if ((ground_weather_strength > 0.0 && weatherable > 0.0) || ground_contact_strength > 0.0) {
        groundDist = ruins_ground_distance(wp);
    }
    float dampK = 0.0;
    if (ground_weather_strength > 0.0 && weatherable > 0.0 && groundDist < 1.7 && groundDist > -0.6) {
        float wk = ground_weather_strength * weatherable;
        float vertical = 1.0 - smoothstep(0.55, 0.85, abs(n.y));
        float buried = smoothstep(-0.55, -0.12, groundDist);
        // 返潮线高度 0.25–1.15m，按石面低频噪声起伏，不是一条水平直线。
        float tide = 0.62 + (g - 0.5) * 0.95 + (veins - 0.5) * 0.40;
        dampK = (1.0 - smoothstep(tide - 0.30, tide + 0.04, groundDist)) * buried * vertical;
        // 返潮上沿析出的一道浅色盐霜，让湿区有边界而不是一层脏雾。
        float bloomLine = smoothstep(tide - 0.16, tide - 0.03, groundDist) * (1.0 - smoothstep(tide - 0.03, tide + 0.07, groundDist)) * vertical * buried;
        // 雨滴溅起的泥点：离地 0–35cm，贴地最浓，边缘由细孔噪声打碎。
        float splash = (1.0 - smoothstep(0.02, 0.30 + (pores - 0.5) * 0.18, groundDist)) * buried * vertical;
        splash *= 0.55 + 0.45 * smoothstep(0.35, 0.65, pores);
        base *= mix(vec3(1.0), vec3(0.78, 0.78, 0.70), dampK * wk);
        base *= 1.0 + bloomLine * 0.05 * wk * (1.0 - mossK);
        base = mix(base, srgb_to_linear(vec3(0.40, 0.33, 0.24)), splash * 0.42 * wk);
        // 墙根背阴潮湿处才长的苔：只在旧石材上，按块状噪声成簇。
        float footGrowth = g * 0.55 + veins * 0.45 + (1.0 - smoothstep(0.0, 0.55, groundDist)) * 0.30;
        float footMoss = smoothstep(0.66, 0.80, footGrowth) * (1.0 - smoothstep(0.05, 0.60, groundDist)) * buried * oldStone;
        base = mix(base, srgb_to_linear(vec3(0.26, 0.33, 0.15)), footMoss * 0.75 * ground_weather_strength);
        mossK = max(mossK, footMoss);
    }
    // 旧石块（墙顶、檐口、断墙台面）朝上的面积尘长地衣：远看是墙顶一圈略暗偏橄榄色。
    if (oldStone > 0.0 && n.y > 0.6 && dressed_stone_draw < 0.5 && COLOR.g < 0.5 && groundDist > 0.4) {
        float up = smoothstep(0.6, 0.9, n.y);
        float lichen = smoothstep(0.52, 0.70, g * 0.5 + veins * 0.5) * up;
        base = mix(base, base * vec3(0.84, 0.86, 0.74), lichen * 0.55);
        base = mix(base, srgb_to_linear(vec3(0.42, 0.46, 0.26)), smoothstep(0.70, 0.80, g * 0.45 + veins * 0.55) * up * 0.45);
    }
    float dressedJoint = 0.0;
    float dressedRoughness = 0.0;
    float dressedOcclusion = 0.0;
    if (dressed) {
        vec3 p = wp-home_stone_origin;
        bool topFace = abs(n.y)>0.5;
        vec3 axisU = abs(n.x)>0.5 ? vec3(0,0,1) : vec3(1,0,0);
        vec3 axisV = topFace ? vec3(0,0,1) : vec3(0,1,0);
        vec2 uv = vec2(dot(p,axisU),dot(p,axisV));
        float nearFade = 1.0-smoothstep(0.025,0.13,footprint);
        float stoneFade = 1.0-smoothstep(0.12,0.32,footprint);
        float spread = max(0.001,footprint*0.5);
        // Shafts, paving and mouldings all use island-local metres, including the footing embedded in the court.
        if (p.x>3.0 && p.x<5.9) {
            dressedOcclusion=max(home_pillar_occlusion(p,n,vec2(4.0,2.0),0.6875,2.5),
                max(home_pillar_occlusion(p,n,vec2(4.875,-1.125),0.75,2.5),
                    home_pillar_occlusion(p,n,vec2(4.875,7.125),0.75,4.0)));
        }
        if ((idx==196.0 || idx==197.0) && p.z>7.1 && p.z<9.51 && p.y<2.85) {
            vec2 aperture=vec2((p.x-1.2)/1.25,max(p.y-1.4,0.0)/1.05);
            float inner=(1.0-smoothstep(1.0,1.24,length(aperture)))*smoothstep(0.38,0.65,p.y);
            dressedOcclusion=max(dressedOcclusion,inner*smoothstep(7.10,8.55,p.z)*0.38);
        }
        if (idx==195.0 && topFace) {
            vec2 court = p.xz-vec2(12.0,3.0);
            float r = length(court);
            float diamond = abs(court.x)+abs(court.y);
            float brassDistance = min(abs(r-4.65),abs(r-7.60));
            float markDistance = min(abs(diamond-1.45),min(abs(diamond-3.0),abs(diamond-3.5)))*0.7071;
            float brass = (1.0-smoothstep(0.016,0.028+spread,brassDistance))*0.024/(0.024+spread);
            float mark = (1.0-smoothstep(0.030,0.047+spread,markDistance))*0.040/(0.040+spread);
            base *= mix(vec3(1.0),vec3(0.87,0.72,0.52),brass);
            base *= mix(vec3(1.0),vec3(0.65,0.74,0.84),mark);
        }
        if (stoneFade>0.0) {
            vec2 size = idx==195.0 ? vec2(1.25,0.75) : (idx==196.0 ? vec2(0.625,0.375) : vec2(0.875,0.375));
            vec2 cell = uv/size;
            cell.x += 0.5*mod(floor(cell.y),2.0);
            vec2 f = fract(cell)-0.5;
            vec2 edge = (vec2(0.5)-abs(f))*size;
            bool joints = idx==192.0 || idx==195.0 || idx==196.0;
            float distanceToJoint = min(edge.x,edge.y);
            vec3 tangent = edge.x<edge.y ? axisU*sign(f.x) : axisV*sign(f.y);
            float blockTint = h31(vec3(floor(cell),idx));
            if (idx==197.0) {
                // Eleven wedge stones. Angular seams run from facade into the existing vaulted reveal.
                vec2 radial = (p.xy-vec2(1.2,1.4))/vec2(1.25,1.05);
                float angle = clamp(atan(radial.y,radial.x),0.0,3.141593);
                float wedge = angle*(11.0/3.141593);
                float across = fract(wedge)-0.5;
                distanceToJoint=(0.5-abs(across))*length(radial)*0.32;
                tangent=normalize(vec3(-radial.y/1.25,radial.x/1.05,0.0))*sign(across);
                blockTint=h31(vec3(floor(wedge),0.0,197.0));
                joints=true;
            }
            if (joints) {
                dressedJoint=(1.0-smoothstep(0.003,0.012+spread,distanceToJoint))*nearFade*0.010/(0.010+spread);
                float shoulder=(1.0-smoothstep(0.010,0.026+spread,distanceToJoint))*nearFade;
                grad-=(tangent-n*dot(tangent,n))*0.13*shoulder;
                shade*=1.0+(blockTint-0.5)*0.13*stoneFade-0.32*dressedJoint;
                base*=vec3(1.0)+(blockTint-0.5)*stoneFade*vec3(0.036,0.0,-0.046);
                dressedRoughness+=(0.5-blockTint)*0.055*stoneFade-0.050*shoulder;
            } else if (!topFace) {
                // Copings and plinths are solid cut stones. Dress their horizontal arrises only.
                float level = fract(p.y*4.0);
                float arris = (1.0-smoothstep(0.002,0.014+spread,min(level,1.0-level)*0.25))*nearFade;
                grad.y += (level<0.5 ? 0.07 : -0.07)*arris;
            }
        }
        shade *= 1.0+(veins-0.5)*0.065+(pores-0.5)*0.035*surfaceFade;
        dressedRoughness+=(veins-0.5)*0.075+0.10*dressedJoint;
    }
    // 世界空间表面梯度已在非一致分支前求好，不依赖体素切线流。
    float woodRoughness = 0.0;
    // A single growth-ring field through the timber gives longitudinal fibres on
    // its sides and curved rings on a sawn end. The three frame axes come from
    // the voxel palette, so turning the camera never turns a plank's grain.
    if (idx == 146.0 || (idx >= 150.0 && idx <= 152.0) || (idx >= 157.0 && idx <= 159.0)) {
        vec3 timberPosition = wp - wood_center.xyz * wood_center.w;
        vec3 timber = timberPosition.xyz;
        // The anvil's weathered wood block (146) is a vertical stump, not a plank.
        bool verticalWood = idx == 146.0 || idx == 157.0;
        if (verticalWood) { timber = timberPosition.yzx; }
        if (idx >= 158.0) { timber = timberPosition.zxy; }
        vec2 radial = timber.yz;
        // A draw-uniform branch keeps the two small joints continuous and centred
        // on their actual cuts; the rest of the house retains its existing field.
        if (wood_center.w < 0.5) {
            vec2 bow = vec2(sin(timber.x * 1.3), cos(timber.x * 0.83)) * 0.019;
            radial = (fract((timber.yz + bow) / 0.75 + vec2(0.19,0.37)) - 0.5) * 0.75;
        }
        radial.y *= 0.87;
        float radius = max(length(radial), 0.0001);
        float phase = radius * 76.0 + sin(radius * 14.0);
        float visible = 1.0 - smoothstep(0.014, 0.065, footprint);
        float fineTimber = smoothstep(0.03125, 0.125, voxel_size);
        float ring = sin(phase) * visible * mix(0.30, 1.0, fineTimber);
        shade *= 1.0 + 0.10 * ring;
        woodRoughness = -0.045 - 0.030 * ring;
        vec2 slope = radial / radius * vec2(1.0,0.87) * cos(phase) * 0.045 * visible * mix(0.35, 1.0, fineTimber);
        vec3 grainNormal = vec3(0.0,slope);
        if (verticalWood) { grainNormal = grainNormal.zxy; }
        if (idx >= 158.0) { grainNormal = grainNormal.yzx; }
        grad += grainNormal - n * dot(n,grainNormal);
    }
    NORMAL = normalize(n - clamp(grad, vec3(-0.22), vec3(0.22)) * surfaceFade);
    float emiK = emi.a;
    // The recessed pane receives transmitted room light. Its broad variation
    // stays legible across the pond, while the wood mullions keep their own PBR.
    if (idx==156.0) {
        vec3 eyeRay=normalize(CAMERA_POSITION_WORLD-wp);
        float facing=abs(dot(n,eyeRay));
        vec3 behind=wp-eyeRay*(.14/max(facing,.34));
        float along=abs(n.z)>abs(n.x) ? behind.x : behind.z;
        float room=.5+.5*cos(along*1.73+behind.y*.71);
        float amber=.5+.5*sin(behind.y*2.25-along*.52);
        base*=.72+.28*room;
        emi.rgb=mix(vec3(1.0,.55,.27),vec3(1.0,.84,.53),.22*room+.56*amber);
        emiK*=window_light*(.53+.47*room)*(.78+.22*facing);
    } else if (idx==99.0) {
        // Warm bounce is limited to the assigned inner strip: top of the sill
        // and jambs catch more light than the outward face and underside.
        emiK*=window_light*(.2+.65*max(n.y,0.0)+.22*(1.0-abs(n.y)));
    }
    ALBEDO = base * shade * daynight_tint;
    ROUGHNESS = clamp(pbr.r + homeRoughness + houseWallRoughness + woodRoughness + dressedRoughness + 0.06 * jointK + 0.04 * mossK - 0.07 * dampK + (grain - 0.5) * 0.05 * grainFade * mineral, 0.0, 1.0);
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
        ALBEDO = mix(ALBEDO, ALBEDO * 0.75 + hover_color.rgb * 0.25, hover);
        EMISSION += hover_color.rgb * (0.35 + fres * 2.4) * hover;
    }
    AO=min(houseWallAO,min(ruins_contact_ao(VERTEX,n,jointK,CAMERA_POSITION_WORLD),1.0-max(dressedOcclusion,0.19*dressedJoint)));
    // 墙脚、柱础、台阶落地处的环境光遮蔽：建筑"坐"在地面上，而不是贴上去的。
    AO*=ruins_ground_contact_ao(groundDist,n);
    if (meadow_origin.x > 0.0 && idx >= 115.0 && idx <= 118.0) {
        vec2 lawn = wp.xz-meadow_origin.xz;
        float canopy = min(length(lawn-vec2(-20.5,.5)),length(lawn-vec2(-17.0,-10.0)));
        canopy = min(canopy,min(length(lawn-vec2(0.0,-13.0)),length(lawn-vec2(19.0,-5.0))));
        canopy = min(canopy,length(lawn-vec2(5.0,13.5)));
        float cover = 1.0-smoothstep(.65,4.2,canopy);
        if (meadow_sun>0.0) {
            float sunPatch = smoothstep(.37,.67,n3(vec3(lawn*.63,TIME*.055)));
            ALBEDO *= mix(vec3(1.0),mix(vec3(.83,.91,.97),vec3(1.14,1.10,.99),sunPatch),cover*meadow_sun);
        }
        AO *= 1.0-.22*cover;
    }
}

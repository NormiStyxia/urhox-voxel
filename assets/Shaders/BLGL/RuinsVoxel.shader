// RuinsVoxel.shader — 时之遗迹静态体素的调色板 PBR 材质
//
// 几何负责轮廓；显式启用的砌石层负责厘米级石缝，远处按像素足迹淡出。
// 法阵、金属、雕像与谜题沿用原调色板，不给每个体素描边。
// 断面（体素内部被打出来的面）自动用调色板的断面色。
shader_type spatial;
render_mode shading_model_pbr, cull_back;
#include "res://Shaders/BLGL/RuinsFrost.shaderinc"
#include "res://Shaders/BLGL/RuinsContactAO.shaderinc"

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
    if (dressed_stone_draw<0.5) {
        vec3 cut = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_CUT)).rgb);
        emi = texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_EMISSIVE));
        base = mix(albedo,cut,step(0.5,COLOR.g));
    }

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
        float ring = sin(phase) * visible;
        shade *= 1.0 + 0.15 * ring;
        woodRoughness = -0.077 - 0.047 * ring;
        vec2 slope = radial / radius * vec2(1.0,0.87) * cos(phase) * 0.068 * visible;
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
    ROUGHNESS = clamp(pbr.r + woodRoughness + dressedRoughness + 0.06 * jointK + (grain - 0.5) * 0.05 * grainFade * mineral, 0.0, 1.0);
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
    AO=min(ruins_contact_ao(VERTEX,n,jointK,CAMERA_POSITION_WORLD),1.0-max(dressedOcclusion,0.19*dressedJoint));
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

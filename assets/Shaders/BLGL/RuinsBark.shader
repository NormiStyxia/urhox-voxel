// RuinsBark.shader — 树干 / 树枝（6.25cm 方格表面）：竖向树皮纹 + 北侧苔痕
shader_type spatial;
render_mode shading_model_pbr, cull_back;

uniform vec3 daynight_tint = vec3(1.0);
uniform vec3 bark_dark = vec3(0.30, 0.23, 0.17);
uniform vec3 bark_light = vec3(0.56, 0.45, 0.34);
uniform vec3 moss_color = vec3(0.22, 0.32, 0.14);
uniform float rock_mode = 0.0;

varying vec4 vcol;
varying vec3 opos;

float h21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float n2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

float surfaceNoise(vec3 p, vec3 w) {
    return n2(p.yz) * w.x + n2(p.xz) * w.y + n2(p.xy) * w.z;
}

vec2 rockCell(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float first = 8.0, second = 8.0, id_col = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 off = vec2(float(x), float(y));
            vec2 id = cell + off;
            vec2 pt = off + vec2(h21(id), h21(id + 17.3)) - f;
            float d = dot(pt, pt);
            if (d < first) { second = first; first = d; id_col = h21(id + 31.0); }
            else { second = min(second, d); }
        }
    }
    return vec2(id_col, sqrt(second) - sqrt(first));
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
    vcol = COLOR;
    opos = VERTEX;
}

void fragment() {
    vec3 wp = VERTEX;
    vec3 n = normalize(NORMAL);
    float along = abs(n.x) > abs(n.z) ? wp.z : wp.x;
    vec3 dx = dFdx(wp), dy = dFdy(wp);
    float footprint = max(length(dx), length(dy));
    float detail = 1.0 - smoothstep(0.02, 0.12, footprint);

    if (rock_mode >= 0.5) {
        vec3 base = srgb_to_linear(clamp(vcol.rgb, 0.0, 1.0));
        float facet = clamp(vcol.a, 0.0, 1.0);
        vec3 w = pow(abs(n), vec3(4.0));
        w /= max(w.x + w.y + w.z, 0.0001);
        float chips = surfaceNoise(wp * 10.5, w);
        float grain = surfaceNoise(wp * 36.0, w);
        float strata = n2(vec2(wp.y * 5.2 + dot(wp.xz, vec2(1.5, -1.1)), along * 1.4));
        vec2 cell = rockCell(vec2(along * 2.8, wp.y * 2.8 + strata * 0.55));
        float crack = 1.0 - smoothstep(0.016, 0.055 + footprint * 1.4, cell.y);
        float relief = chips * 0.009 - crack * 0.008 + grain * 0.0025 + (strata - 0.5) * 0.004;
        if (rock_mode >= 1.5) {
            relief = n2(vec2(along * 16.0, wp.y * 2.4)) * 0.005 + (grain - 0.5) * 0.002;
        }
        vec3 r1 = cross(dy, n), r2 = cross(n, dx);
        float det = dot(dx, r1);
        vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.000001);
        NORMAL = normalize(n - clamp(grad, vec3(-0.36), vec3(0.36)) * detail);

        if (rock_mode >= 1.5) {
            float wood_grain = n2(vec2(along * 14.0, wp.y * 3.0));
            vec3 col = base * (0.78 + 0.34 * facet) * (0.88 + 0.24 * wood_grain);
            col *= 1.0 + (grain - 0.5) * 0.12 * detail;
            ALBEDO = col * daynight_tint;
            ROUGHNESS = 0.88;
            METALLIC = 0.0;
            SPECULAR = 0.20;
            return;
        }

        float vein = pow(1.0 - abs(sin(wp.x * 5.8 + wp.y * 8.2 + chips * 4.2)), 11.0);
        vec3 col = base * (0.74 + 0.42 * facet);
        col *= (0.84 + 0.32 * strata) * (0.88 + 0.24 * cell.x);
        col *= 1.0 - crack * 0.38 * detail + (chips - 0.5) * 0.28 * detail + (grain - 0.5) * 0.16 * detail;
        col = mix(col, base * 1.45 + vec3(0.035), vein * 0.24 * detail);
        float is_slate = step(base.r, base.b * 1.05);
        float moss = smoothstep(0.52, 0.76, n2(wp.xz * 2.5 + wp.y)) * smoothstep(0.25, 0.75, n.y) * is_slate;
        col = mix(col, vec3(0.045, 0.085, 0.035), moss * 0.40);
        col *= 0.66 + 0.34 * smoothstep(-0.06, 0.32, opos.y);
        ALBEDO = col * daynight_tint;
        ROUGHNESS = clamp(0.88 + (grain - 0.5) * 0.14 + crack * 0.08 - vein * 0.12, 0.72, 0.98);
        METALLIC = 0.0;
        SPECULAR = 0.24 + 0.10 * vein;
        return;
    }

    // 世界投影，跨贪心合并面保持一致，不使用旧圆管的环形 UV。
    float ridge = n2(vec2(along * 18.0, wp.y * 0.8));
    float crack = smoothstep(0.58, 0.76, ridge);
    float scar = n2(vec2(along * 6.0 + n2(wp.xz * 1.5), wp.y * 2.2));
    vec3 col = mix(bark_light, bark_dark, crack * 0.8 + n2(wp.xz * 3.0 + wp.y) * 0.25);
    // 苔痕：只长在朝上 / 朝北的一侧（n.z > 0），成片
    float moss = smoothstep(0.55, 0.75, n2(vec2(along * 3.0, wp.y * 0.7))) * smoothstep(-0.2, 0.6, n.z + n.y * 0.5);
    col = mix(col, moss_color, moss * 0.6);
    col *= 1.0 - smoothstep(0.60, 0.76, scar) * 0.18;
    float relief = ridge * 0.007 + scar * 0.004;
    vec3 r1 = cross(dy, n), r2 = cross(n, dx);
    float det = dot(dx, r1);
    vec3 grad = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.000001);
    NORMAL = normalize(n - clamp(grad, vec3(-0.3), vec3(0.3)) * detail);
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    ROUGHNESS = 0.92;
    METALLIC = 0.0;
    SPECULAR = 0.2;
}

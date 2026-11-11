// 冰晶：风格化「刻面冰」（配合 VoxelFX.IceCluster 生成的平面六棱晶体网格）
//   * 每个平面按主光方向分亮 / 中 / 暗三档：受光面浅青、侧面主色、背光面深蓝，干净不花
//   * 透光：逆光看时整根晶体透出亮青色；掠射角（轮廓）偏亮，像光在冰里全反射
//   * 根部沉入深色、尖顶提亮；面中央隐约一条亮芯（透过冰面看到的内部光）
//   * 棱线细亮边 + 镜面闪光 + 一条缓慢上扫的高光带
// 顶点数据：COLOR.r = 沿晶体的高度比例，COLOR.g = 尖顶面标记，COLOR.b = 每根晶体的随机数；
//           UV.x = 面内横向（棱线在 0 / 1），UV.y = 面内纵向
shader_type spatial;
render_mode shading_model_unlit, cull_disabled;

uniform vec4 deep_color = vec4(0.02, 0.10, 0.45, 1.0);
uniform vec4 mid_color = vec4(0.10, 0.42, 0.95, 1.0);
uniform vec4 light_color = vec4(0.55, 0.86, 1.0, 1.0);
uniform vec4 edge_color = vec4(0.90, 1.0, 1.0, 1.0);
uniform float glow = 1.0;
uniform float edge_width = 0.06;
uniform float translucency = 1.0;

void fragment() {
    vec3 N = normalize(NORMAL);
    vec3 V = normalize(CAMERA_POSITION_WORLD - VERTEX);
    if (dot(N, V) < 0.0) {
        N = -N;
    }
    vec3 L = normalize(MAIN_LIGHT_DIRECTION);
    float h = COLOR.r;
    float tipFace = COLOR.g;
    float rnd = COLOR.b;

    // ---- 三档刻面明暗（过渡极窄：面与面之间是干脆的色块）
    float ndl = dot(N, L);
    float t = 0.5 * smoothstep(-0.28, -0.16, ndl) + 0.5 * smoothstep(0.30, 0.42, ndl);
    vec3 lo = mix(deep_color.rgb, mid_color.rgb, clamp(t * 2.0, 0.0, 1.0));
    vec3 hi = mix(mid_color.rgb, light_color.rgb, clamp(t * 2.0 - 1.0, 0.0, 1.0));
    vec3 col = mix(lo, hi, step(0.5, t));

    // ---- 竖向渐变：根部偏深，尖顶偏亮
    col = mix(mix(deep_color.rgb, col, 0.5), col, smoothstep(0.0, 0.45, h));
    col = mix(col, light_color.rgb, smoothstep(0.65, 1.0, h) * 0.18);

    // ---- 面内坐标：尖顶三角面把横向坐标归一化，算到两条棱的距离
    float w = mix(1.0, max(1.0 - UV.y, 0.001), tipFace);
    float un = mix(UV.x, (UV.x - 0.5 * UV.y) / w, tipFace);
    float across = clamp(abs(un - 0.5) * 2.0, 0.0, 1.0);
    float edgeDist = (1.0 - across) * 0.5 * w;

    // 内部亮芯：面中央一条柔和的亮带，越往上越明显
    float core = pow(1.0 - across, 3.0) * (0.35 + 0.65 * h);
    col = mix(col, light_color.rgb, core * 0.22);

    // ---- 透光：轮廓（菲涅尔）+ 逆光透射
    float ndv = clamp(dot(N, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 3.0);
    float back = pow(clamp(dot(-V, L), 0.0, 1.0), 3.0);
    col += edge_color.rgb * translucency * (fres * 0.2 + back * (0.25 + 0.5 * fres) * 0.6);

    // ---- 上扫高光带（每根晶体相位不同）
    float sweep = fract(h * 0.8 - un * 0.22 - TIME * 0.35 + rnd);
    float band = smoothstep(0.0, 0.04, sweep) * (1.0 - smoothstep(0.07, 0.12, sweep));
    col += edge_color.rgb * band * (0.25 + 0.3 * t);

    // ---- 镜面闪光（平面法线 → 转到合适角度时整面一亮）
    vec3 R = reflect(-L, N);
    float spec = pow(max(dot(R, V), 0.0), 36.0);
    col += edge_color.rgb * spec * 0.9;

    // ---- 棱线：侧棱 + 柱身顶端那一圈横棱
    float line = 1.0 - smoothstep(edge_width * 0.55, edge_width, edgeDist);
    line = max(line, (1.0 - tipFace) * smoothstep(1.0 - edge_width * 1.1, 1.0 - edge_width * 0.5, UV.y));
    col = mix(col, edge_color.rgb, line * (0.35 + 0.45 * t));

    ALBEDO = col * glow;
}

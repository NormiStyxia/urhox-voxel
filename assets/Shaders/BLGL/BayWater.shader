// BayWater.shader — VoxelTown 海湾水体(SurfaceShader 实现,v3)
//
// 引擎内置 Translucent/Water.glsl 为遗产路径,本场景不依赖。
// 结构:
//   几何   — 3 个 Gerstner 方向波(深水色散 ω=√(gk),choppy 尖峰)做顶点位移,
//            解析法线在片元阶段用同一组相位函数重建(网格由 Lua CustomGeometry 细分)
//   透射   — screen_texture 折射(按水深缩放扰动 + 越水回退守卫),
//            Beer–Lambert 每通道消光(红先衰减) → EMISSION(已光照,不能二次受光)
//   反射   — PBR 管线 IBL,SPECULAR 0.35 ≈ F0 0.02;粗糙度随距离上升补偿远处微波
//   散射   — 逆光波峰 SSS 近似(Sea of Thieves 式 hack)
//   泡沫   — 岸线/吃水线深度差窄带 + 浪尖白沫,进 ALBEDO 受光
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never, world_vertex_coords;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// 细节法线(引擎 WaterNormal.png,双层滚动)与泡沫纹理(Worley 气泡花边)
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

// —— 水色/光学(UC4 向:强红衰减 + 明亮 turquoise 上涌散射)——
uniform vec3 absorption = vec3(1.05, 0.30, 0.18);              // Beer–Lambert 每米消光系数(RGB)
uniform vec4 scatter_color : source_color = vec4(0.045, 0.27, 0.30, 1.0);  // 上涌散射基色
uniform float ssr_strength : hint_range(0.0, 2.0, 0.05) = 1.0; // 屏幕空间反射强度
// SSR 投影 y 翻转:平台全局常量(D3D 纹理原点左上=1;GL=0,由 Lua 按后端设置)。
// 勿改回逐像素"自校准"——解析位置与光栅位置的微差在屏幕中线附近必然跨侧,
// 判定乱跳会画出横贯视野中心的镜像采样线(踩过两版)。
uniform float ssr_y_flip : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform vec4 foam_color : source_color = vec4(0.90, 0.95, 0.94, 1.0);
uniform vec4 sss_color : source_color = vec4(0.13, 0.62, 0.52, 1.0);
uniform vec3 sun_dir = vec3(0.424, -0.707, 0.566);             // TownDay/TownNight 方向光朝向
uniform float sss_strength : hint_range(0.0, 3.0, 0.05) = 1.0; // Lua 按昼夜缩放
// —— 波形 ——
uniform float wave_amp_scale : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float choppiness : hint_range(0.0, 4.0, 0.1) = 2.2;
uniform float detail_strength : hint_range(0.0, 2.0, 0.01) = 0.80;
// —— 表面 ——
uniform float refraction_strength : hint_range(0.0, 0.2, 0.005) = 0.055;
uniform float foam_depth_distance : hint_range(0.01, 2.0, 0.01) = 0.45;
uniform float roughness_near : hint_range(0.0, 1.0, 0.01) = 0.045;
uniform float roughness_far : hint_range(0.0, 1.0, 0.01) = 0.30;
// —— 船尾迹轨迹链(Lua 每帧喂;xy=世界位置,z=age 秒,w=强度;p0=当前船尾,新→旧)——
// 相邻点连成胶囊段做距离场:洗流带沿真实路径弯曲、随龄扩散消退,全高斯无硬边。
uniform vec4 wake0_p0 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p1 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p2 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p3 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p4 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p5 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p6 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake0_p7 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p0 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p1 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p2 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p3 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p4 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p5 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p6 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 wake1_p7 = vec4(0.0, 0.0, 0.0, 0.0);
uniform float wake_width0 = 1.0;  // 洗流带基础宽(≈0.7×船宽)
uniform float wake_width1 = 1.8;

varying vec2 world_xz;
varying float world_y;

// ============================ 噪声 ============================
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        value += noise2(p) * amp;
        p = p * 2.03 + vec2(11.7, 5.4);
        amp *= 0.5;
    }
    return value;
}

// ==================== 随机平铺法线采样(Heitz 三角网格) ====================
// 高光闪点对纹理周期是非线性放大器:哪怕 45% 稀释,闪光星座仍按 tile 重排
// (FFT 回归稳定抓获 2.9m 周期)。三角网格三抽头 + 每域随机旋转,类别性根除。
vec2 hash22(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

vec2 stoch_normal_xy(sampler2D tex, vec2 uv) {
    // 三角网格(每域约 1.7 个 tile,旋转域 ~5m 世界尺度)
    vec2 skewed = vec2(uv.x - 0.57735 * uv.y, 1.15470 * uv.y) * 0.6;
    vec2 base = floor(skewed);
    vec2 f = fract(skewed);
    float w1; float w2; float w3;
    vec2 v1; vec2 v2; vec2 v3;
    float z = 1.0 - f.x - f.y;
    if (z > 0.0) {
        w1 = z; w2 = f.y; w3 = f.x;
        v1 = base; v2 = base + vec2(0.0, 1.0); v3 = base + vec2(1.0, 0.0);
    } else {
        w1 = -z; w2 = 1.0 - f.y; w3 = 1.0 - f.x;
        v1 = base + vec2(1.0, 1.0); v2 = base + vec2(1.0, 0.0); v3 = base + vec2(0.0, 1.0);
    }
    vec2 n = vec2(0.0);
    for (int i = 0; i < 3; i++) {
        vec2 v = (i == 0) ? v1 : ((i == 1) ? v2 : v3);
        float w = (i == 0) ? w1 : ((i == 1) ? w2 : w3);
        vec2 h = hash22(v);
        float ang = h.x * 6.2831853;
        float ca = cos(ang);
        float sa = sin(ang);
        vec2 ruv = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca) + h.y * 7.13;
        vec2 s = texture(tex, ruv).xy * 2.0 - 1.0;
        // 采样时转了域,法线要转回世界系
        n += vec2(s.x * ca + s.y * sa, -s.x * sa + s.y * ca) * w;
    }
    return n;
}

// ========================= Gerstner =========================
// 单波贡献:disp = 顶点位移;slope = ∂y/∂(x,z);qsum = choppy 对法线竖直分量的收缩;
// crest = 波高(SSS/白沫用)。顶点与片元共用,保证位移与法线相位一致。
void gerstner(vec2 p, float t, vec2 dir, float wavelength, float amp, float q, float disp_scale,
              inout vec3 disp, inout vec2 slope, inout float qsum, inout float crest) {
    float k = 6.2831853 / wavelength;
    float w = sqrt(9.8 * k);            // 深水色散:长波跑得快
    vec2 d = normalize(dir);
    float ph = k * dot(d, p) - w * t;
    float s = sin(ph);
    float c = cos(ph);
    // disp_scale=0 时该波只贡献法线不位移顶点(短波低于网格 Nyquist 会走样成格子)
    disp += vec3(q * amp * d.x * c, amp * s, q * amp * d.y * c) * disp_scale;
    slope += d * (k * amp * c);
    qsum += q * k * amp * s;
    crest += s * amp;
}

// 三个分量:主涌浪 + 两个斜交次波,整体向西岸推进
void wave_field(vec2 p, float t,
                inout vec3 disp, inout vec2 slope, inout float qsum, inout float crest) {
    // 相位域扭曲:固定波向的正弦叠加会形成周期性干涉晶格(远景规则亮斑阵,
    // 踩过)。真实海谱是连续随机相位;用 30m 级噪声揉皱采样域,浪线有机弯曲。
    p = p + vec2(fbm2(p * 0.033) - 0.5, fbm2(p * 0.029 + vec2(37.7, 11.3)) - 0.5) * 5.0;
    // 频谱分工(FFT 回归逼出来的定论):Gerstner 只留两道长涌浪做位移与大尺度
    // 光影;短尺度细节全部交给宽谱纹理法线。单频短波正弦在任何局部窗口都是
    // 周期的,域扭曲救不了——λ4.2/2.4 短波曾以稳定次峰 0.21-0.25 被回归抓获。
    // 波幅总和 ≈0.148m:water_level + Σamp 必须低于码头顶,否则浪尖穿甲板(踩过)。
    // 波向朝 -X(向西岸沙滩推进)——岸沫推进方向必须与波向一致才可信。
    float a = wave_amp_scale;
    gerstner(p, t, vec2(-0.94, 0.34), 18.0, 0.095 * a, choppiness, 1.0, disp, slope, qsum, crest);
    gerstner(p, t, vec2(-0.98, -0.28), 9.5, 0.053 * a, choppiness, 1.0, disp, slope, qsum, crest);
}

// ========================= 船尾迹(轨迹链) =========================
// 相邻轨迹点连成胶囊段:到段距离 d 做高斯洗流带(宽度随龄扩散,强度随龄
// 指数消退),外加从路径向外传播的环形涟漪。全部软衰减——无 step、无裁剪窗,
// 不存在硬边;转弯时轨迹链自然弯曲。
void wake_segment(vec2 world, vec4 pa, vec4 pb, float base_w,
                  inout float foam_acc, inout vec2 slope_acc, inout float rough_acc) {
    if (pa.w < 0.01 || pb.w < 0.01) { return; }
    vec2 ab = pb.xy - pa.xy;
    float len2 = dot(ab, ab);
    if (len2 < 1e-4 || len2 > 36.0) { return; }   // 空段 / 传送跳变
    float h = clamp(dot(world - pa.xy, ab) / len2, 0.0, 1.0);
    vec2 closest = pa.xy + ab * h;
    vec2 away = world - closest;
    float d = length(away);
    if (d > 9.0) { return; }
    float age = mix(pa.z, pb.z, h);
    float inten = mix(pa.w, pb.w, h);
    float life = exp(-age * 0.85);                 // ~4s 消退
    float w = base_w * (0.55 + age * 0.50);        // 洗流带随龄扩散
    float band = exp(-(d * d) / (w * w));
    foam_acc += band * life * inten * 0.9;
    // 环形涟漪:自路径向外传播(1.7 m/s),近处强远处弱
    float ripple = sin((d - age * 1.7) * 4.6) * exp(-d * 0.55);
    vec2 dir = away / max(d, 0.05);
    slope_acc += dir * (ripple * 0.22 * life * inten);
    rough_acc += band * life * inten * 0.45;
}

float linearize_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection_matrix) {
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
    vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
    view.xyz /= view.w;
    return -view.z;
}

// ========================= SSR =========================
// 屏幕空间反射:视空间步进 + 深度比较,命中采 screen_texture。
// 岛屿/城镇/船只的倒影只有它能给(IBL 只有天空)。
// y_flip 由调用方用"自身位置重投影 vs SCREEN_UV"自校准,平台无关。
vec3 ssr_trace(vec3 vs_pos, vec3 vs_dir, float y_flip, mat4 proj, mat4 inv_proj,
               sampler2D depth_tex, sampler2D color_tex, out float confidence) {
    confidence = 0.0;
    float step_len = 0.55;
    vec3 p = vs_pos;
    for (int i = 0; i < 20; i++) {
        p += vs_dir * step_len;
        step_len *= 1.22;                         // 指数步长,近细远粗
        vec4 cp = proj * vec4(p, 1.0);   // Godot 列向量约定(M*v)
        if (cp.w <= 0.05) { return vec3(0.0); }
        vec2 uv = cp.xy / cp.w * 0.5 + vec2(0.5);
        uv.y = mix(uv.y, 1.0 - uv.y, y_flip);
        if (uv.x < 0.001 || uv.x > 0.999 || uv.y < 0.001 || uv.y > 0.999) { return vec3(0.0); }
        float scene_z = linearize_depth(texture(depth_tex, uv).r, uv, inv_proj);
        float ray_fwd = abs(p.z);                 // 引擎视空间 +Z 朝前
        if (ray_fwd > scene_z + 0.08 && ray_fwd < scene_z + 3.5) {
            // 命中:屏幕边缘渐隐 × 步数渐隐
            vec2 edge = min(uv, vec2(1.0) - uv);
            float edge_fade = clamp(min(edge.x, edge.y) * 8.0, 0.0, 1.0);
            confidence = edge_fade * (1.0 - float(i) / 20.0 * 0.5);
            return texture(color_tex, uv).rgb;
        }
    }
    return vec3(0.0);
}

void vertex() {
    world_xz = VERTEX.xz;
    world_y = VERTEX.y;
    vec3 disp = vec3(0.0);
    vec2 slope = vec2(0.0);
    float qsum = 0.0;
    float crest = 0.0;
    wave_field(world_xz, TIME, disp, slope, qsum, crest);
    // 顶点色 R = 离岸波幅衰减(Lua 网格烘焙):近岸波幅归零,防止浪峰顶进滩坡穿模
    VERTEX += disp * COLOR.r;
}

void fragment() {
    float t = TIME;

    // —— Gerstner 解析法线(与顶点同相位)——
    vec3 disp = vec3(0.0);
    vec2 slope = vec2(0.0);
    float qsum = 0.0;
    float crest = 0.0;
    wave_field(world_xz, t, disp, slope, qsum, crest);
    // 与顶点位移同源的近岸衰减:法线/浪高一并压平,光影才不会"平地起浪"
    slope *= COLOR.r;
    qsum *= COLOR.r;
    crest *= COLOR.r;
    float crest_norm = clamp(crest / (0.148 * max(wave_amp_scale, 0.001)) * 0.5 + 0.5, 0.0, 1.0);

    // —— 细节法线:双层滚动纹理法线(替代程序 fbm——value noise 天生糊,
    //    纹理法线才有真实水面的高频结构;UV=世界坐标,波向 -X 同步滚动)——
    // 解析水面位置(含波高):顶点位移经光栅化是分段平面的,直接用会把
    // 1.5m 网格的面片刻进后续所有深度相关运算(踩过:屏幕空间固定网格伪影)
    vec3 world_pos = vec3(world_xz.x, world_y + disp.y * COLOR.r, world_xz.y);
    float cam_dist = length(CAMERA_POSITION_WORLD - world_pos);
    float near_fade = 1.0 - smoothstep(15.0, 60.0, cam_dist);

    // 细节层 = 随机平铺采样(闪光星座级别的防周期);粗层旋转 37° + 低频罩调制
    vec2 tn1 = stoch_normal_xy(detail_normal, world_xz * 0.34 + vec2(t * 0.045, -t * 0.017));
    vec2 uv2 = vec2(world_xz.x * 0.799 - world_xz.y * 0.602,
                    world_xz.x * 0.602 + world_xz.y * 0.799);   // 旋转 37°
    vec3 tn2 = texture(detail_normal, uv2 * 0.071 + vec2(t * 0.019, t * 0.011)).rgb * 2.0 - 1.0;
    vec2 tn2r = vec2(tn2.x * 0.799 + tn2.y * 0.602, -tn2.x * 0.602 + tn2.y * 0.799);
    float tile_var = 0.45 + 1.10 * fbm2(world_xz * 0.030);
    vec2 gm = (tn1 * (0.42 + 0.28 * near_fade) + tn2r * 0.55) * detail_strength * tile_var;
    vec2 gn = vec2(0.0);

    // —— 船尾迹(法线/泡沫/粗糙度三路贡献)——
    float wake_foam = 0.0;
    float wake_rough = 0.0;
    vec2 wake_slope = vec2(0.0);
    wake_segment(world_xz, wake0_p0, wake0_p1, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p1, wake0_p2, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p2, wake0_p3, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p3, wake0_p4, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p4, wake0_p5, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p5, wake0_p6, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake0_p6, wake0_p7, wake_width0, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p0, wake1_p1, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p1, wake1_p2, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p2, wake1_p3, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p3, wake1_p4, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p4, wake1_p5, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p5, wake1_p6, wake_width1, wake_foam, wake_slope, wake_rough);
    wake_segment(world_xz, wake1_p6, wake1_p7, wake_width1, wake_foam, wake_slope, wake_rough);

    vec2 slope_total = vec2(-slope.x, -slope.y) + gm + gn + wake_slope;
    NORMAL_MAP = normalize(vec3(slope_total.x, slope_total.y, max(1.0 - qsum, 0.15))) * 0.5 + vec3(0.5);

    // —— 深度 ——
    vec2 screen_uv = SCREEN_UV;
    // 用解析水面深度替代 FRAGCOORD(面片化深度会把网格刻进 Beer-Lambert 颜色,
    // FFT 回归以屏幕固定周期 (dy10,dx24) 稳定抓获——正是用户问的"mesh 格子")。
    // Surface Shader 内建矩阵使用 Godot 列向量约定，统一写成 M*v；兼容层负责适配
    // UrhoX 的内部矩阵布局。
    float water_depth = abs((VIEW_MATRIX * vec4(world_pos, 1.0)).z);
    float scene_depth0 = linearize_depth(texture(depth_texture, screen_uv).r, screen_uv, INV_PROJECTION_MATRIX);
    // 前景污染守卫(Water.glsl 同款判断的泡沫版):剪影边缘的深度采样会因
    // 光栅对齐/TAA 抖动踩到"水面之前"的前景物体,差值为负;若直接 max 钳零,
    // 泡沫会把它误读成"零水深=岸线",沿所有前景物体剪影描白边(踩过)。
    float raw_delta0 = scene_depth0 - water_depth;
    float not_foreground = step(0.0, raw_delta0);
    float depth_delta0 = max(raw_delta0, 0.0);

    // —— 折射:扰动按水深缩放(贴水物体不扭曲),越水回退守卫 ——
    vec2 distortion = slope_total * refraction_strength * clamp(depth_delta0 / 1.2, 0.0, 1.0);
    vec2 refract_uv = clamp(screen_uv + distortion, vec2(0.001), vec2(0.999));
    float refr_scene_depth = linearize_depth(texture(depth_texture, refract_uv).r, refract_uv, INV_PROJECTION_MATRIX);
    if (refr_scene_depth < water_depth) {
        refract_uv = screen_uv;
        refr_scene_depth = scene_depth0;
    }
    vec3 refracted = texture(screen_texture, refract_uv).rgb;
    float depth_delta = max(refr_scene_depth - water_depth, 0.0);

    // —— Beer–Lambert 每通道消光:红先死,深水收敛到上涌散射色 ——
    // 散射按深度分级:浅水阳光触底回散更亮(UC4 那种发光 turquoise 的来源)
    vec3 extinction = exp(-absorption * depth_delta);
    float absorb01 = 1.0 - (extinction.g + extinction.b) * 0.5;
    vec3 scatter_eff = scatter_color.rgb * mix(1.55, 0.55, absorb01);
    vec3 transmission = refracted * extinction + scatter_eff * (1.0 - extinction);

    // —— 泡沫:岸线/吃水线窄带 + 浪尖白沫 ——
    float foam_noise = fbm2(world_xz * 2.6 + vec2(t * 0.5, -t * 0.4));
    // —— CE 风格岸沫:向岸推进的条纹层 + 冲滩/回撤涌动 + 水线致密带 ——
    // 开阔水面不放白沫(0.19m 柔浪不破碎,贴片白斑出戏——踩过,勿回加)。
    float shore_prox = 1.0 - smoothstep(0.0, 1.9, depth_delta0);   // 0-1.9m 浅水棚
    // 冲滩涌动:慢速向岸行波,噪声打散相位(整条岸线同步呼吸会假)
    float surge = 0.5 + 0.5 * sin(world_xz.x * 0.55 + t * 1.3 + fbm2(world_xz * 0.35) * 2.6);
    // 沿岸线拉长的碎条纹,随浪向岸(-X)推进
    float streaks = fbm2(vec2(world_xz.x * 3.6 + t * 0.95, world_xz.y * 1.3));
    float wash = shore_prox * smoothstep(0.42, 0.86,
        streaks * (0.72 + 0.28 * surge) + shore_prox * 0.30 * surge);
    // 水线致密带(吃水线/滩线 0-0.45m)
    float shore = 1.0 - smoothstep(0.0, foam_depth_distance, depth_delta0);
    float shore_foam = shore * smoothstep(0.25, 0.70, foam_noise + shore * 0.35);
    float foam_mask = clamp(shore_foam + wash * 0.65
        + wake_foam * (0.45 + 0.55 * foam_noise), 0.0, 1.0);
    // 泡沫纹理化:双尺度 Worley 气泡花边(向岸推进),薄处碎成真实泡壁
    float ftex = texture(foam_tex, world_xz * 0.50 + vec2(t * 0.055, -t * 0.02)).r;
    float ftex2 = texture(foam_tex, world_xz * 0.16 + vec2(t * 0.024, t * 0.013)).r;
    float foam_pattern = ftex * 0.6 + ftex2 * 0.4;
    // not_foreground:前景污染像素(负 delta)禁沫,防剪影白边
    float foam = smoothstep(0.28, 0.85, foam_mask * (0.35 + 0.95 * foam_pattern)) * not_foreground;

    // —— SSS:逆光看波峰的透光(浅水+高波峰+视线迎着阳光水平分量)——
    vec3 view_to_surf = normalize(world_pos - CAMERA_POSITION_WORLD);
    vec2 sun_h = normalize(sun_dir.xz);
    float towards_sun = clamp(dot(view_to_surf.xz, sun_h), 0.0, 1.0);
    // 距离衰减:SSS 是近景浪峰透光;远处它把每条浪脊点亮成周期行(FFT 回归抓到的)。
    // 噪声破碎:同一条浪脊不同段透光不同,消掉均匀亮带。
    float sss = pow(towards_sun, 3.0) * pow(crest_norm, 3.0)
        * clamp(depth_delta * 0.6, 0.0, 1.0) * sss_strength * 0.6
        * (1.0 - smoothstep(18.0, 55.0, cam_dist))
        * (0.5 + 0.5 * foam_noise);

    // —— 输出:透射(已光照)→ EMISSION;泡沫(真表面)→ ALBEDO;反射靠 PBR IBL ——
    // —— SSR:岛屿/城镇/船只倒影(IBL 只有天空);掠射角才值得走 ——
    vec3 ssr_col = vec3(0.0);
    float ssr_conf = 0.0;
    vec3 world_n = normalize(vec3(slope_total.x * 0.6, max(1.0 - qsum, 0.15), slope_total.y * 0.6));
    vec3 v_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
    float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(world_n, v_dir), 0.0, 1.0), 5.0);
    if (fres * ssr_strength > 0.04 && foam < 0.6) {
        vec3 refl = reflect(-v_dir, world_n);
        if (refl.y > 0.01) {
            vec3 vs_pos = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
            vec3 vs_dir = normalize((VIEW_MATRIX * vec4(refl, 0.0)).xyz);
            ssr_col = ssr_trace(vs_pos, vs_dir, ssr_y_flip, PROJECTION_MATRIX, INV_PROJECTION_MATRIX,
                depth_texture, screen_texture, ssr_conf);
        }
    }
    float ssr_w = clamp(fres * ssr_conf * ssr_strength, 0.0, 1.0) * (1.0 - foam);

    // 泡沫留 8% 透水:纯不透明白是"贴纸感"的另一半来源
    ALBEDO = foam_color.rgb * foam;
    EMISSION = transmission * (1.0 - foam * 0.92) * (1.0 - ssr_w * 0.75)
        + ssr_col * ssr_w
        + sss_color.rgb * sss * (1.0 - foam);
    ALPHA = 1.0;
    METALLIC = 0.0;
    SPECULAR = 0.35; // F0 ≈ 0.02(水,IOR 1.33)
    ROUGHNESS = clamp(mix(mix(roughness_near, roughness_far, smoothstep(18.0, 110.0, cam_dist)), 0.55, foam)
        + wake_rough * 0.25, 0.0, 1.0);
    AO = 1.0;
}

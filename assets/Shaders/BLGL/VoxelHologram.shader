// VoxelHologram.shader — 体素全息投影(SurfaceShader × 调色板纹理参考示例)
//
// 这是"UGC 自定义体素材质"路径的最小完整参考:体素网格的顶点色不携带颜色,
// 只携带调色板索引(R = 索引/255,G = 内部体素标记/断面)。自定义 shader 从
// world:GetPaletteTexture() 拿到调色板图集,自己决定怎么用这些数据——
// 这里把 .vox 模型原本的调色板颜色重新演绎成一座会呼吸的全息投影。
//
// 调色板寻址交给引擎 include(下方 #include):voxel_palette_uv(索引, 层) 直接给出
// 采样坐标,层用 VOXEL_PALETTE_ALBEDO / PBR / EMISSIVE / CUT。体积所在的图集槽位和
// 图集布局由引擎写进材质,engine.json 切到 virtualized 布局也无需改这里。
//   ALBEDO 反照率 RGBA           PBR 粗糙度/金属度/高光
//   EMISSIVE 自发光 rgb + 强度/16 CUT 断面色
// 颜色层(ALBEDO / EMISSIVE.rgb / CUT)按 sRGB 写入，采样后要先 srgb_to_linear；
// PBR 层是线性标量，不要解码。整张纹理混了颜色行和标量行，不能靠 source_color
// 自动解码——那会把 PBR 层一起弄坏，必须按层手动处理。
//
// 动态效果:扫描线上滚 + 全息闪烁 + 菲涅尔轮廓光 + 逐高度波纹抖动 + 随机
// 故障条。被打掉的碎块继承本材质(引擎行为),断面(COLOR.g)显示为故障红
// ——破坏本身成了表演的一部分。
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, world_vertex_coords;

// 调色板纹理:Lua 侧 material:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())。
// nearest 是硬要求——索引查表,linear 会把相邻调色板槽位混出错误颜色。
// 不要给 palette_tex 加 source_color（见上方：整张图混了颜色行和标量行）。
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

// 引擎提供的调色板寻址:voxel_palette_index / voxel_palette_uv 及其所需的槽位 uniform。
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"
uniform vec4 holo_tint : source_color = vec4(0.25, 0.85, 1.0, 1.0);  // 全息基色(青)
uniform vec4 glitch_tint : source_color = vec4(1.0, 0.25, 0.35, 1.0); // 断面/故障色(红)
uniform float scan_speed : hint_range(0.0, 4.0, 0.05) = 0.7;   // 扫描线上滚速度(m/s)
uniform float scan_density : hint_range(1.0, 40.0, 0.5) = 14.0; // 扫描线密度(条/米)
uniform float base_alpha : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 1.4;  // 菲涅尔轮廓光强度

varying vec3 wpos;
varying vec3 wnormal;

// SurfaceShader 没有引擎内建 GammaToLinearSpace，本地近似 sRGB→linear
vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453123);
}

void vertex() {
    wpos = VERTEX;
    wnormal = NORMAL;
    // 整体悬浮呼吸 + 逐高度水平波纹(投影仪不稳定感)
    VERTEX.y += sin(TIME * 1.4) * 0.05;
    VERTEX.x += sin(TIME * 2.2 + VERTEX.y * 3.1) * 0.018;
    // 随机故障条:按高度分带,偶尔整条横向撕裂一下
    float band = floor(VERTEX.y * 9.0);
    float tear = step(0.965, hash11(band + floor(TIME * 7.0)));
    VERTEX.x += tear * (hash11(band * 3.7 + floor(TIME * 7.0)) - 0.5) * 0.12;
}

void fragment() {
    // —— 调色板查表 ——
    // voxel_palette_uv 由引擎 include 提供,槽位与图集布局由引擎维护。
    // ALBEDO 层是 sRGB 颜色 → srgb_to_linear 后再参与乘色/混合。
    float idx = voxel_palette_index(COLOR);
    vec3 albedo = srgb_to_linear(texture(palette_tex, voxel_palette_uv(idx, VOXEL_PALETTE_ALBEDO)).rgb);

    // 断面(内部体素,COLOR.g=1):全息数据"损坏",显示故障红
    float interior = step(0.5, COLOR.g);
    vec3 body = mix(albedo * holo_tint.rgb * 1.6, glitch_tint.rgb, interior * 0.85);

    // —— 扫描线:世界高度上滚的亮暗条 ——
    float scan = 0.55 + 0.45 * sin((wpos.y - TIME * scan_speed) * scan_density * 6.2831853);

    // —— 菲涅尔轮廓:侧掠视角发亮,全息体积感的来源 ——
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
    // cull_disabled 会看到背面,法线翻正保证轮廓对称
    vec3 n = normalize(wnormal) * sign(dot(normalize(wnormal), view_dir) + 1e-4);
    float rim = pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 2.0) * rim_strength;

    // —— 全息闪烁:两个不可通约频率相乘,亮度轻微抖动 ——
    float flicker = 0.90 + 0.10 * sin(TIME * 23.0) * sin(TIME * 7.3);

    vec3 color = (body * scan + holo_tint.rgb * rim) * flicker;
    float alpha = clamp(base_alpha * (0.6 + 0.4 * scan) + rim * 0.35 + interior * 0.3, 0.0, 1.0);

    ALBEDO = color;
    ALPHA = alpha * holo_tint.a;
}

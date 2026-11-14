// RuinsGrassTuft.shader — 兜底草簇（设备不支持 GrassField 时）
// 几何草叶：每叶一个细三角，按 UV.y（0 根 → 1 尖）做风摆和根→尖渐变；
// 法线统一朝上，让草和下面的地面落在同一档光照里（不会出现一圈亮边）。
shader_type spatial;
render_mode shading_model_pbr, cull_disabled, world_vertex_coords;

uniform vec3 root_color = vec3(0.10, 0.20, 0.06);
uniform vec3 tip_color = vec3(0.42, 0.58, 0.22);
uniform vec3 daynight_tint = vec3(1.0);
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_strength = 0.18;

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

void vertex() {
    float h = UV.y;
    vec2 w = normalize(wind_dir);
    float phase = dot(VERTEX.xz, w) * 0.35 - TIME * 1.6;
    float gust = 0.6 + 0.4 * sin(phase) + 0.25 * sin(VERTEX.x * 1.7 + VERTEX.z * 1.3 + TIME * 3.1);
    vec2 bend = w * gust * wind_strength * h * h;
    VERTEX.xz += bend;
    VERTEX.y -= dot(bend, bend) * 0.5;
    NORMAL = vec3(0.0, 1.0, 0.0);
}

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    float h = UV.y;
    vec3 col = mix(root_color, tip_color, pow(h, 0.8)) * COLOR.rgb;
    ALBEDO = srgb_to_linear(col) * daynight_tint;
    if (cloud_shadow_strength>0.0) { ALBEDO*=cloud_illumination(VERTEX); }
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
    SPECULAR = 0.2;
}

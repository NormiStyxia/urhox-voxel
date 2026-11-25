// A travelling cut through the original voxel mesh. The irregular boundary is
// fixed in world space, so reversing the clock retraces exactly the same cells.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#include "res://Shaders/BLGL/Voxel/VoxelPalette.shaderinc"
uniform vec4 wave = vec4(0.0); // origin X, origin Z, cut height, assembling

vec3 linear_color(vec3 c) {
    return c * (c * (c * .305306011 + .682171111) + .012522878);
}

void fragment() {
    vec2 uv = voxel_palette_uv(voxel_palette_index(COLOR), VOXEL_PALETTE_ALBEDO);
    vec3 body = linear_color(textureLod(palette_tex, uv, 0.0).rgb);
    vec3 cell = floor((VERTEX - NORMAL * .003) * 8.0);
    vec3 p = fract(cell * vec3(.1031,.1030,.0973));
    p += dot(p,p.yzx+33.33);
    float chip = fract((p.x+p.y)*p.z);
    float level = VERTEX.y + dot(VERTEX.xz-wave.xy,vec2(.10,.05)) + chip*.19;
    float depth = wave.z-level;
    float lip = 1.0-smoothstep(.025,.27,depth);
    vec3 light = mix(vec3(.35,.64,.90),vec3(1.0,.80,.43),wave.w);
    ALBEDO = mix(body,light,lip*.65);
    EMISSION = lip * light * (1.05 + chip*.85);
    ROUGHNESS = .78;
    if (depth < 0.0) discard;
}

shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
varying float cascade;

vec2 phases(vec2 p, float t) {
    return vec2(dot(p,vec2(.86,1.25))-t*1.1, dot(p,vec2(-1.65,.92))+t*1.45);
}
void vertex() {
    cascade=COLOR.r;
    vec2 waves=sin(phases(UV,TIME));
    // The falling sheet and pool share a stationary lip at the outlet.
    VERTEX.y+=dot(waves,vec2(.028,.012))*(1.0-cascade)*smoothstep(-16.0,-13.0,UV.y);
}
float depth_at(vec2 uv, mat4 inv_proj, sampler2D depth_map) {
    vec4 q=inv_proj*vec4(uv*2.0-1.0,texture(depth_map,uv).r,1.0);
    return -q.z/q.w;
}
void fragment() {
    vec2 c=cos(phases(UV,TIME));
    vec2 slope=c.x*.028*vec2(.86,1.25)+c.y*.012*vec2(-1.65,.92);
    slope+=.016*vec2(sin(UV.y*4.0+UV.x+TIME),cos(UV.x*3.4-UV.y+TIME*.8));
    vec3 pool_normal=normalize(vec3(-slope.x,1.0,-slope.y));
    float strands=.5+.5*sin(UV.x*9.0+sin(UV.y*1.3+TIME*4.5));
    NORMAL=normalize(mix(pool_normal,vec3(.12*(strands-.5),.06,-1.0),cascade));
    float surface_depth=abs((VIEW_MATRIX*vec4(VERTEX,1.0)).z);
    vec2 uv=SCREEN_UV;
    vec2 bend=clamp(uv+.027*slope,vec2(.001),vec2(.999));
    if(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)<surface_depth) {bend=uv;}
    float thickness=clamp(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)-surface_depth,0.0,6.0);
    vec3 transmit=exp(-vec3(.85,.32,.24)*thickness);
    float fres=pow(1.0-clamp(dot(pool_normal,normalize(CAMERA_POSITION_WORLD-VERTEX)),0.0,1.0),5.0);
    ALBEDO=mix(vec3(.033,.24,.21)*(1.0-transmit),mix(vec3(.11,.38,.40),vec3(.40,.67,.66),strands),cascade);
    EMISSION=texture(scene_color,bend).rgb*transmit*(1.0-fres)*(1.0-cascade);
    ROUGHNESS=mix(.115,.29,cascade); METALLIC=0.0; SPECULAR=.38;
    ALPHA=mix(1.0,.55+.19*strands,cascade);
}

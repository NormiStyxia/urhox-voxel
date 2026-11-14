shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, world_vertex_coords;
uniform float flight_time = 0.0;
uniform float night_strength = 0.0;
uniform vec3 player_center = vec3(0.0);
varying float glow;
void vertex() {
    float phase=COLOR.r*6.283185;
    float t=flight_time;
    vec3 center=VERTEX+vec3(sin(t*0.45+phase)*0.45,sin(t*0.6+phase)*0.35,cos(t*0.3+phase*2.0)*0.45);
    vec3 ray=CAMERA_POSITION_WORLD-center;
    ray=ray/max(length(ray),0.001);
    vec3 side=cross(vec3(0.0,1.0,0.0),ray);
    side=length(side)>0.001 ? side/length(side) : vec3(1.0,0.0,0.0);
    vec3 up=cross(ray,side);
    float size=0.045+COLOR.g*0.025;
    VERTEX=center+(side*(UV.x-0.5)+up*(UV.y-0.5))*size*2.0;
    float breath=0.5+0.5*sin(t*1.2+phase);
    float awake=smoothstep(-0.94,-0.60,sin(t*0.15+phase*3.0));
    float range=length(center.xz-player_center.xz);
    glow=(0.18+0.82*breath*breath)*awake*COLOR.a*night_strength;
    glow*=smoothstep(0.65,2.0,range)*(1.0-smoothstep(23.0,28.0,range));
}
void fragment() {
    vec2 q=(UV-vec2(0.5))*2.0;
    float roundness=max(0.0,1.0-dot(q,q));
    float core=roundness*roundness*roundness;
    ALBEDO=mix(vec3(0.8,1.05,0.12),vec3(2.0,2.1,0.65),core);
    ALPHA=clamp((core*0.60+roundness*0.08)*glow,0.0,0.68);
}

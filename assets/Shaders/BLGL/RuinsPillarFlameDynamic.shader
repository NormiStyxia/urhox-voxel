shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, world_vertex_coords;
uniform float night_strength = 0.0;
uniform float flame_time = 0.0;
uniform float flame_detail = 1.0;
varying float spark_life;
void vertex() {
    float phase=COLOR.r*255.0*2.1;
    float t=flame_time;
    vec3 origin=(MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xyz;
    vec3 offset=VERTEX-origin;
    spark_life=1.0;
    if (COLOR.g>0.5) {
        vec3 ray=CAMERA_POSITION_WORLD-origin;
        ray=ray/max(length(ray),0.001);
        vec3 side=cross(vec3(0.0,1.0,0.0),ray);
        side=length(side)>0.001 ? side/length(side) : vec3(1.0,0.0,0.0);
        vec3 up=cross(ray,side);
        VERTEX=origin+side*offset.x+up*(offset.y-0.8)+vec3(0.0,0.8,0.0);
        if (COLOR.b>0.05) {
            float age=fract(t*0.3+COLOR.b+phase*0.1);
            vec3 center=origin+vec3(sin(t*1.2+phase+COLOR.b*8.0)*0.17,0.40+age*2.1,cos(t*0.9+phase)*0.12);
            VERTEX=center+(side*(UV.x-0.5)+up*(UV.y-0.5))*0.055;
            spark_life=smoothstep(0.0,0.12,age)*(1.0-smoothstep(0.55,1.0,age));
        }
    } else {
        float y=max(offset.y,0.0);
        float wind=sin(t*2.0+phase)*0.08+sin(t*11.0+phase)*0.012*flame_detail;
        VERTEX.x+=wind*y*y;
        VERTEX.z+=sin(t*1.7+phase)*0.045*y*y;
    }
}
void fragment() {
    float phase=COLOR.r*255.0*2.1;
    float t=flame_time;
    float y=UV.y;
    float x=UV.x*2.0-1.0;
    // Continuous upward travelling analytic noise; no derivative or texture.
    float rise=y*10.0-t*5.0;
    float noise=sin(rise+phase+x*3.0)*0.65+sin(rise*1.7-phase+x*7.0)*0.35;
    float sway=sin(y*7.0-t*3.0+phase)*0.14*y+noise*0.10*y*flame_detail;
    float width=0.52*pow(max(1.0-y,0.0),0.85)*(0.86+noise*0.14);
    float body=1.0-smoothstep(width*0.55,width+0.04,abs(x-sway));
    float tongueWidth=0.24*pow(max(1.0-y/0.76,0.0),0.8);
    float tongue=1.0-smoothstep(tongueWidth*0.55,tongueWidth+0.025,abs(x+0.30-sway));
    tongue*=1.0-smoothstep(0.66,0.78,y);
    float flame=max(body,tongue)*smoothstep(0.0,0.05,y)*(1.0-smoothstep(0.9,1.0,y));
    float core=(1.0-smoothstep(0.05,0.30,abs(x-sway)))*(1.0-smoothstep(0.12,0.65,y));
    vec3 color=mix(vec3(1.8,0.12,0.015),vec3(2.7,0.85,0.08),1.0-y);
    color=mix(color,vec3(3.3,2.5,1.1),core);
    float flicker=0.94+0.04*sin(t*7.0+phase)+0.02*sin(t*13.0+phase*1.7);
    float alpha=flame*0.76*flicker;
    if (COLOR.g>0.5) {
        vec2 q=(UV-vec2(0.5))*2.0;
        float halo=max(0.0,1.0-dot(q,q));
        color=vec3(1.6,0.32,0.035);
        alpha=halo*halo*halo*0.065*flicker;
        if (COLOR.b>0.05) {
            color=vec3(2.5,0.95,0.18);
            alpha=halo*halo*spark_life*0.65;
        }
    }
    float distance_to_eye=length(VERTEX-CAMERA_POSITION_WORLD);
    float nearFade=smoothstep(0.2,0.8,distance_to_eye)*(1.0-smoothstep(85.0,110.0,distance_to_eye));
    ALBEDO=color;
    ALPHA=clamp(alpha*night_strength*COLOR.a*nearFade,0.0,0.82);
}

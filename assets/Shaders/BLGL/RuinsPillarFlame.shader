shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, world_vertex_coords;
uniform float night_strength = 0.0;
void vertex() {
    if (COLOR.g>0.5) {
        vec3 origin=(MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xyz;
        vec3 offset=VERTEX-origin;
        vec3 ray=CAMERA_POSITION_WORLD-origin;
        ray=length(ray)>0.001 ? ray/length(ray) : vec3(0.0,0.0,1.0);
        vec3 side=cross(vec3(0.0,1.0,0.0),ray);
        side=length(side)>0.001 ? side/length(side) : vec3(1.0,0.0,0.0);
        vec3 up=cross(ray,side);
        VERTEX=origin+side*offset.x+up*(offset.y-0.8)+vec3(0.0,0.8,0.0);
    }
}
void fragment() {
    float y=UV.y;
    float x=UV.x*2.0-1.0;
    float phase=COLOR.r*6.283185;
    float sway=sin(y*8.0-TIME*2.0+phase)*0.12*y
        +sin(y*14.0-TIME*3.0+phase)*0.045*y;
    float width=0.48*pow(max(1.0-y,0.0),0.90);
    float body=1.0-smoothstep(width*0.65,width+0.03,abs(x-sway));
    float left_width=0.30*pow(max(1.0-y/(0.68+sin(TIME*1.8+phase)*0.06),0.0),0.75);
    float tongue=1.0-smoothstep(left_width*0.65,left_width+0.015,abs(x+0.36-sway*0.7));
    tongue*=1.0-smoothstep(0.62,0.75,y);
    float right_width=0.26*pow(max(1.0-y/(0.54+sin(TIME*2.2+phase)*0.05),0.0),0.75);
    float other=1.0-smoothstep(right_width*0.65,right_width+0.015,abs(x-0.35-sway));
    other*=1.0-smoothstep(0.48,0.61,y);
    float flame=max(body,max(tongue,other))*smoothstep(0.0,0.06,y)*(1.0-smoothstep(0.94,1.0,y));
    float core=(1.0-smoothstep(0.07,0.32,abs(x-sway*0.4)))*(1.0-smoothstep(0.10,0.60,y));
    vec3 color=mix(vec3(2.3,0.28,0.025),vec3(3.2,1.9,0.45),core);
    float alpha=flame*0.76;
    if (COLOR.g>0.5) {
        vec2 q=(UV-vec2(0.5))*2.0;
        float halo=max(0.0,1.0-dot(q,q));
        color=vec3(1.6,0.32,0.035);
        alpha=halo*halo*halo*0.065;
    }
    float distance_to_eye=length(VERTEX-CAMERA_POSITION_WORLD);
    float nearFade=smoothstep(0.2,0.8,distance_to_eye)*(1.0-smoothstep(85.0,110.0,distance_to_eye));
    ALBEDO=color;
    ALPHA=clamp(alpha*night_strength*COLOR.a*nearFade,0.0,0.82);
}

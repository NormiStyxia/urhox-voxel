// Silver ash, mother-of-pearl leaf, spun silk and a fine silver cord.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 wood_color : source_color = vec4(0.56,0.63,0.72,1.0);
uniform vec3 paint_tint = vec3(1.0,1.0,1.0);
uniform vec4 leaf_color : source_color = vec4(0.91,0.93,0.99,1.0);
uniform vec4 grip_color : source_color = vec4(0.31,0.33,0.45,1.0);
uniform vec4 string_color : source_color = vec4(0.79,0.84,0.92,1.0);
uniform float bend = 0.0;
varying vec3 wood_pos;
void vertex() {
    wood_pos = VERTEX;
    float t = clamp(abs(VERTEX.y)*2.0,0.0,1.0);
    VERTEX.z -= bend*t*t;
}
void fragment() {
    vec3 c = clamp(COLOR.rgb,0.0,1.0);
    vec3 w = c*(c*(c*0.305306011+0.682171111)+0.012522878);
    float silk = clamp(1.0-w.r-w.g-w.b,0.0,1.0);
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(CAMERA_POSITION_WORLD-VERTEX);
    vec3 reflected = reflect(-v,n);
    float rim = pow(1.0-clamp(dot(n,v),0.0,1.0),3.2);
    float glint = pow(clamp(dot(reflected,MAIN_LIGHT_DIRECTION),0.0,1.0),92.0);
    float sky = smoothstep(-0.34,0.67,reflected.y);
    float curve = wood_pos.x*320.0 + wood_pos.z*162.0 + 4.2*sin(wood_pos.y*32.0);
    float pores = pow(0.5+0.5*sin(curve*2.9+1.35*sin(curve*0.34+UV.y*25.0)),5.0);
    float latewood = 0.5+0.5*sin(curve+1.5*sin(UV.y*26.0));
    // Brushed silver pigment lies over the longitudinal grain, below the clear finish.
    vec3 ash = wood_color.rgb*paint_tint*(0.79+0.29*latewood-0.10*pores);
    float vein = pow(0.5+0.5*sin(curve*1.12+UV.y*42.0),9.0);
    vec3 nacre = leaf_color.rgb*mix(vec3(0.58,0.62,0.78),vec3(1.0,0.99,0.96),sky);
    nacre *= 0.92+0.08*vein*smoothstep(0.0,0.35,UV.x);
    nacre += vec3(0.09,0.11,0.16)*rim + vec3(0.17)*glint;
    float warp = sin(wood_pos.y*3400.0+wood_pos.z*1190.0);
    float weft = sin(wood_pos.x*3210.0-wood_pos.y*1380.0);
    float overlap = smoothstep(0.02,0.31,COLOR.a)*(1.0-smoothstep(0.84,1.0,COLOR.a));
    vec3 cloth = grip_color.rgb*(0.57+0.46*overlap+0.06*warp*weft);
    vec3 silver = string_color.rgb*(0.65+0.32*sky+0.22*glint);
    ALBEDO = w.r*ash+w.g*nacre+silk*cloth+w.b*silver;
    METALLIC = 0.62*w.r+0.44*w.g+0.80*w.b;
    ROUGHNESS = 0.36*w.r+0.32*w.g+0.72*silk+0.29*w.b;
    SPECULAR = 0.50*w.r+0.62*w.g+0.32*silk+0.80*w.b;
    CLEARCOAT = 0.82*w.r;
    CLEARCOAT_ROUGHNESS = 0.16;
    EMISSION = rim*(0.022*w.r*wood_color.rgb+0.043*w.g*leaf_color.rgb+0.08*w.b*string_color.rgb);
}

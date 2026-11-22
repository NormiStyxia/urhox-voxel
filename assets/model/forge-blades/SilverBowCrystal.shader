// An ice bud with a pavilion, a girdle and a pointed crown.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 crystal_color : source_color = vec4(0.35,0.78,1.0,1.0);
uniform float absorption = 1.55;
uniform float shell_alpha = 0.51;
uniform float core_glow = 0.24;
uniform float bend = 0.0;
varying vec3 cut_normal;
varying vec3 gem_pos;
void vertex() {
    cut_normal = NORMAL;
    gem_pos = VERTEX;
    float t = clamp(abs(VERTEX.y)*2.0,0.0,1.0);
    VERTEX.z -= bend*t*t;
}
void fragment() {
    vec3 c = clamp(COLOR.rgb,0.0,1.0);
    vec3 weights = c*(c*(c*0.305306011+0.682171111)+0.012522878);
    vec3 hue = crystal_color.rgb/max(0.001,max(crystal_color.r,max(crystal_color.g,crystal_color.b)));
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(CAMERA_POSITION_WORLD-VERTEX);
    float ndv = clamp(dot(n,v),0.0,1.0);
    float fres = 0.043+0.957*pow(1.0-ndv,4.0);
    float crown = smoothstep(0.35,1.0,UV.x);
    float path = (0.33+0.67*COLOR.a+0.12*(1.0-crown))/max(0.34,ndv);
    vec3 transmitted = exp(-absorption*path*(vec3(1.0)-0.88*hue));
    vec3 ray = refract(-v,n,0.641);
    vec3 cut = normalize(cut_normal);
    vec3 pavilion = normalize(n + vec3(-0.53,0.42,0.61));
    float backplane = abs(dot(reflect(ray,pavilion),normalize(vec3(-0.63,0.37,0.68))));
    float facet = clamp(0.47+dot(cut,vec3(0.39,0.26,-0.23)),0.0,1.0);
    float fire = smoothstep(0.45,0.93,backplane)*facet;
    vec3 deep = 0.25*hue*hue;
    vec3 mid = mix(deep,0.72*hue,facet);
    vec3 bright = mix(mid,mix(hue,vec3(0.77,0.94,1.0),0.46),fire);
    float ridge = pow(clamp(dot(reflect(-v,n),MAIN_LIGHT_DIRECTION),0.0,1.0),105.0);
    float centre = exp(-abs(gem_pos.x)*60.0)*pow(1.0-ndv*0.48,1.5);
    float beat = 0.86+0.14*sin(TIME*1.45+floor(facet*7.0)*1.37);
    ALBEDO = bright*transmitted;
    METALLIC = 0.0;
    ROUGHNESS = 0.081+0.035*(1.0-facet);
    SPECULAR = 0.83;
    EMISSION = weights.b*(core_glow*centre*(1.28-0.28*crown)*beat*hue+0.28*fres*hue+ridge*vec3(0.49,0.76,0.93));
    ALPHA = clamp(shell_alpha+0.24*fres+0.14*(1.0-transmitted.r),0.24,0.94);
}

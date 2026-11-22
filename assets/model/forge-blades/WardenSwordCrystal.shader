// Closed amber guard stones and blue pommel stones share the gem pass.
shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 amber_color : source_color = vec4(1.0,0.54,0.075,1.0);
uniform vec4 accent_color : source_color = vec4(0.08,0.46,0.92,1.0);
uniform float absorption = 1.8;
uniform float internal_return = 0.42;
uniform float gem_alpha = 0.78;
uniform float flow_strength = 0.24;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}
void fragment() {
    float amber = step(0.20,UV.y);
    vec3 tint = mix(accent_color.rgb,amber_color.rgb,amber);
    vec3 hue = tint / max(max(max(tint.r,tint.g),tint.b),0.001);
    vec3 deep = hue*hue*0.18;
    vec3 middle = mix(hue*hue,hue,0.66)*0.60;
    vec3 bright = mix(hue,vec3(1.0),0.085);
    vec3 n = normalize(NORMAL);
    vec3 view_delta = CAMERA_POSITION_WORLD-VERTEX;
    vec3 v = view_delta/max(length(view_delta),0.0001);
    float ndv = clamp(dot(v,n),0.0,1.0);
    vec3 reflected = 2.0*dot(n,v)*n-v;
    float fres = pow(1.0-ndv,2.7);
    // The optical axis passes through each stone's girdle. Pommel side cuts
    // use a lateral axis; object-space depth stays fixed when wielded.
    float side = (1.0-amber)*step(abs(local_position.z),abs(local_position.x));
    float z = mix(abs(local_position.z),abs(local_position.x),side);
    float girdle = mix(mix(0.029,0.048,side),0.055,amber);
    float thickness = clamp((z-girdle)/mix(0.014,0.020,amber),0.0,1.0);
    float trans = 1.0/(1.0+absorption*(0.28+thickness)/max(ndv,0.20));
    float cut = local_normal.x*0.54+local_normal.y*0.38+local_position.x*9.0;
    float bounce = smoothstep(-0.10,0.12,cut+reflected.y*0.3);
    vec3 body = mix(mix(deep,middle,trans),bright,bounce*internal_return*trans);
    float s = COLOR.a;
    float tone = s*(s*(s*0.305306011+0.682171111)+0.012522878);
    ALBEDO = body*tone;
    METALLIC = 0.0;
    ROUGHNESS = mix(0.095,0.14,amber);
    SPECULAR = mix(0.88,0.76,amber);
    float sparkle = pow(clamp(dot(reflected,MAIN_LIGHT_DIRECTION),0.0,1.0),95.0);
    float head = fract(TIME*0.12)*1.4-0.2;
    float pulse = 1.0-smoothstep(0.005,0.024,abs(UV.y+cut*0.021-head));
    EMISSION = bright*(0.045+0.19*fres+0.06*pulse*flow_strength)+mix(bright,vec3(1.0),0.35)*sparkle*0.68;
    ALPHA = clamp(gem_alpha+fres*0.18+sparkle*0.08,0.0,0.98);
}

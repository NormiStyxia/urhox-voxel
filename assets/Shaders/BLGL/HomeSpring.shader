shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform sampler2D mirror_color : hint_default_transparent, filter_linear, repeat_disable;
uniform float mirror_weight = 0.0;
uniform vec4 mirror_eye = vec4(0.0);
uniform vec3 mirror_right = vec3(0.0);
uniform vec3 mirror_up = vec3(0.0);
uniform vec3 mirror_forward = vec3(0.0);
// Island-local XZ, age in seconds, strength. Empty slots have zero strength.
uniform vec4 foot_wave1 = vec4(0.0);
uniform vec4 foot_wave2 = vec4(0.0);
uniform vec4 foot_wave3 = vec4(0.0);
uniform vec4 foot_wave4 = vec4(0.0);
// Linear Zone horizon and replacement weight while the sky probe is unavailable.
uniform vec4 zone_fallback = vec4(0.0);
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
    return abs(q.z)/max(abs(q.w),.00001);
}

// Two soft crests travel outwards. XY bends the normal/refraction and Z
// scatters a little light at the crest so it also reads away from the glint.
vec3 foot_ripple(vec2 p, vec4 wave) {
    if (wave.w<=0.0) { return vec3(0.0); }
    vec2 delta=p-wave.xy;
    float r=length(delta);
    float width=.065+.05*wave.z;
    float q=(r-.105-1.12*wave.z)/width;
    float trail=q+2.6;
    float lead=exp(-q*q);
    float echo=.46*exp(-trail*trail);
    float fade=wave.w*(1.0-smoothstep(.08,1.4,wave.z));
    return vec3(delta/max(r,.025)*(q*lead+trail*echo)*.44,lead+echo)*fade;
}
void fragment() {
    vec2 c=cos(phases(UV,TIME));
    vec2 slope=c.x*.028*vec2(.86,1.25)+c.y*.012*vec2(-1.65,.92);
    vec2 wind=vec2(sin(UV.y*4.0+UV.x+TIME),cos(UV.x*3.4-UV.y+TIME*.8));
    slope+=.048*wind;
    vec3 ripple=vec3(0.0);
    if (cascade<.5) {
        ripple=foot_ripple(UV,foot_wave1)+foot_ripple(UV,foot_wave2)
            +foot_ripple(UV,foot_wave3)+foot_ripple(UV,foot_wave4);
        slope+=ripple.xy;
    }
    vec3 pool_normal=normalize(vec3(-slope.x,1.0,-slope.y));
    float strands=.5+.5*sin(UV.x*9.0+sin(UV.y*1.3+TIME*4.5));
    NORMAL=normalize(mix(pool_normal,vec3(.12*(strands-.5),.06,-1.0),cascade));
    vec3 view_pos=(VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
    float surface_depth=abs(view_pos.z);
    vec2 uv=SCREEN_UV;
    vec2 bend=clamp(uv+.027*slope,vec2(.001),vec2(.999));
    if(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)<surface_depth) {bend=uv;}
    float thickness=clamp(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)-surface_depth,0.0,6.0);
    vec3 transmit=exp(-vec3(.85,.32,.24)*thickness);
    vec3 view_dir=normalize(CAMERA_POSITION_WORLD-VERTEX);
    float facing=clamp(dot(pool_normal,view_dir),0.0,1.0);
    // Water IOR 1.33. Transmission yields energy at grazing angles; the
    // engine applies the angular response to indirect specular exactly once.
    float fres=.02+.98*pow(1.0-facing,5.0);
    float local_weight=0.0;
    vec3 local_light=vec3(0.0);
    if (cascade<.5 && mirror_weight>.001) {
        vec3 on_plane=vec3(VERTEX.x,mirror_eye.w,VERTEX.z)-mirror_eye.xyz;
        float z=dot(mirror_forward,on_plane);
        vec2 capture=vec2(dot(mirror_right,on_plane),dot(mirror_up,on_plane))/max(z,.03)+.5;
        vec3 delta=reflect(-view_dir,pool_normal)-reflect(-view_dir,vec3(0.0,1.0,0.0));
        delta.y=-delta.y;
        capture+=clamp(vec2(dot(mirror_right,delta),dot(mirror_up,delta))*.095,vec2(-.018),vec2(.018));
        vec2 edge=min(capture,1.0-capture);
        float border=smoothstep(.006,.10,min(edge.x,edge.y))*smoothstep(.03,.5,z);
        // A camera rotation preserves planar projection. Translation changes the
        // reflected ray, especially in water close to the player.
        vec3 present=vec3(VERTEX.x,mirror_eye.w,VERTEX.z)-CAMERA_POSITION_WORLD;
        float alignment=dot(present,on_plane)/max(length(present)*length(on_plane),.0001);
        vec4 sample_color=texture(mirror_color,clamp(capture,vec2(.001),vec2(.999)));
        float coverage=clamp(sample_color.a,0.0,1.0);
        local_weight=mirror_weight*border*smoothstep(.967,.997,alignment)*coverage;
        local_light=sample_color.rgb/max(coverage,.001);
    }
    // Transparent capture pixels inherit the live Zone sky. While the probe
    // is unavailable, their fallback comes from the same Zone horizon.
    float fallback_weight=(1.0-local_weight)*zone_fallback.a;
    float weight=local_weight+fallback_weight;
    RADIANCE=vec4((local_light*local_weight+zone_fallback.rgb*fallback_weight)/max(weight,.001),weight);
    float crest=min(ripple.z,1.0);
    vec3 scatter=vec3(.025,.135,.119)*(1.0-transmit)*(1.0-fres)+vec3(.12,.24,.22)*crest;
    ALBEDO=mix(scatter,mix(vec3(.11,.38,.40),vec3(.40,.67,.66),strands),cascade);
    // Opaque scene colour already includes Zone fog; the Forward mirror fogs
    // its own shore geometry. Fogging this composite would haze both twice.
    EMISSION=texture(scene_color,bend).rgb*transmit*(1.0-fres)*(1.0-cascade);
    // PBR supplies the moving sun, moon and local fire highlights in their
    // actual light colours. Small differences in facet roughness break up the path.
    ROUGHNESS=mix(.12+.045*wind.x+.035*crest,.29,cascade); METALLIC=0.0; SPECULAR=mix(.25,.48,cascade);
    ALPHA=mix(1.0,.55+.19*strands,cascade);
}

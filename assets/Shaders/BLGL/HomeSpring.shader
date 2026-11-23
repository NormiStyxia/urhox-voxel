shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform sampler2D mirror_color : hint_default_black, filter_linear, repeat_disable;
uniform float mirror_ready = 0.0;
uniform vec4 mirror_eye = vec4(0.0);
uniform vec3 mirror_right = vec3(0.0);
uniform vec3 mirror_up = vec3(0.0);
uniform vec3 mirror_forward = vec3(0.0);
// Island-local XZ, age in seconds, strength. Empty slots have zero strength.
uniform vec4 foot_wave1 = vec4(0.0);
uniform vec4 foot_wave2 = vec4(0.0);
uniform vec4 foot_wave3 = vec4(0.0);
uniform vec4 foot_wave4 = vec4(0.0);
uniform vec3 sky_phase = vec3(1.0,0.0,0.0); // DayNight.day, dusk, nightK
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

// Reduced capability path. Trace an upward reflected ray in the opaque depth
// buffer; blend missed silhouettes/edges into the environment rather than clamp.
vec4 screen_reflection(vec3 start,vec3 direction,vec2 screen,vec2 ndc_scale,
        mat4 proj,mat4 inv_proj,sampler2D depth_map,sampler2D color_map) {
    vec4 base_clip=proj*vec4(start,1.0);
    vec2 base_ndc=base_clip.xy/base_clip.w;
    float step_m=.27;
    vec3 p=start;
    for (int i=0;i<16;i++) {
        p+=direction*step_m;
        step_m*=1.23;
        vec4 clip=proj*vec4(p,1.0);
        if (clip.w<=.03) { break; }
        vec2 uv=screen+(clip.xy/clip.w-base_ndc)*ndc_scale;
        vec2 edge=min(uv,1.0-uv);
        if (min(edge.x,edge.y)<=.002) { break; }
        float gap=abs(p.z)-depth_at(uv,inv_proj,depth_map);
        if (gap>=0.0 && gap<.10+.75*step_m) {
            return vec4(texture(color_map,uv).rgb,smoothstep(.002,.055,min(edge.x,edge.y)));
        }
    }
    return vec4(0.0);
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
    // Low angles carry the opposite bank. Looking down through thin water
    // leaves almost all of the refracted bed visible.
    float fres=.028+.94*pow(1.0-facing,2.65);
    vec3 sky=mix(vec3(.075,.10,.16),vec3(.41,.61,.83),sky_phase.x);
    sky=mix(sky,vec3(.69,.31,.16),.72*sky_phase.y*(1.0-sky_phase.z));
    // A broader sky reflection surrounds the direct PBR glint, strongest near sunset.
    float sky_lobe=max(dot(reflect(-view_dir,pool_normal),MAIN_LIGHT_DIRECTION),0.0);
    float solar_glow=.46*sky_phase.x+.80*sky_phase.y*(1.0-sky_phase.z);
    sky+=MAIN_LIGHT_COLOR*pow(sky_lobe,12.0)*(solar_glow+.045*sky_phase.z);
    vec3 reflected=sky;
    float ysign=1.0;
    if (mirror_ready<.5) {
        // Evaluate quad derivatives under a draw-uniform branch, including at the lip.
        vec4 clip=PROJECTION_MATRIX*vec4(view_pos,1.0);
        ysign=sign(dFdy(SCREEN_UV.y)*dFdy(clip.y/clip.w));
    }
    if (cascade<.5) {
        if (mirror_ready>.5) {
            // A point on the mirror plane projects identically from the real
            // and mirrored cameras. Use the pose of the last captured texture.
            vec3 on_plane=vec3(VERTEX.x,mirror_eye.w,VERTEX.z)-mirror_eye.xyz;
            float z=dot(mirror_forward,on_plane);
            vec2 capture=vec2(dot(mirror_right,on_plane),dot(mirror_up,on_plane))/max(z,.03)+.5;
            // Project the world-space perturbation onto capture axes; waves
            // keep their direction as the player turns around the spring.
            vec3 delta_ray=reflect(-view_dir,pool_normal)-reflect(-view_dir,vec3(0.0,1.0,0.0));
            delta_ray.y=-delta_ray.y;
            vec2 offset=vec2(dot(mirror_right,delta_ray),dot(mirror_up,delta_ray));
            capture+=clamp(offset*.16,vec2(-.032),vec2(.032));
            vec2 edge=min(capture,1.0-capture);
            float confidence=step(.03,z)*smoothstep(.002,.045,min(edge.x,edge.y));
            reflected=mix(sky,texture(mirror_color,clamp(capture,vec2(.001),vec2(.999))).rgb,confidence);
        } else {
            vec3 ray=(VIEW_MATRIX*vec4(reflect(-view_dir,pool_normal),0.0)).xyz;
            vec4 hit=screen_reflection(view_pos,ray,uv,vec2(.5,.5*ysign),PROJECTION_MATRIX,
                INV_PROJECTION_MATRIX,scene_depth,scene_color);
            reflected=mix(sky,hit.rgb,hit.a);
        }
    }
    float crest=min(ripple.z,1.0);
    vec3 scatter=vec3(.025,.135,.119)*(1.0-transmit)*(1.0-fres)+vec3(.12,.24,.22)*crest;
    ALBEDO=mix(scatter,mix(vec3(.11,.38,.40),vec3(.40,.67,.66),strands),cascade);
    EMISSION=(texture(scene_color,bend).rgb*transmit*(1.0-fres)+reflected*fres)*(1.0-cascade);
    // PBR supplies the moving sun, moon and local fire highlights in their
    // actual light colours. Small differences in facet roughness break up the path.
    ROUGHNESS=mix(.12+.045*wind.x+.035*crest,.29,cascade); METALLIC=0.0; SPECULAR=.48;
    ALPHA=mix(1.0,.55+.19*strands,cascade);
}

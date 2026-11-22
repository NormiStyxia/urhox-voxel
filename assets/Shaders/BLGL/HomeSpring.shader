shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
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
    return -q.z/q.w;
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
    float surface_depth=abs((VIEW_MATRIX*vec4(VERTEX,1.0)).z);
    vec2 uv=SCREEN_UV;
    vec2 bend=clamp(uv+.027*slope,vec2(.001),vec2(.999));
    if(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)<surface_depth) {bend=uv;}
    float thickness=clamp(depth_at(bend,INV_PROJECTION_MATRIX,scene_depth)-surface_depth,0.0,6.0);
    vec3 transmit=exp(-vec3(.85,.32,.24)*thickness);
    vec3 view_dir=normalize(CAMERA_POSITION_WORLD-VERTEX);
    float fres=.02+.98*pow(1.0-clamp(dot(pool_normal,view_dir),0.0,1.0),5.0);
    vec3 sky=mix(vec3(.075,.10,.16),vec3(.41,.61,.83),sky_phase.x);
    sky=mix(sky,vec3(.69,.31,.16),.72*sky_phase.y*(1.0-sky_phase.z));
    // A broader sky reflection surrounds the direct PBR glint, strongest near sunset.
    float sky_lobe=max(dot(reflect(-view_dir,pool_normal),MAIN_LIGHT_DIRECTION),0.0);
    float solar_glow=.46*sky_phase.x+.80*sky_phase.y*(1.0-sky_phase.z);
    sky+=MAIN_LIGHT_COLOR*pow(sky_lobe,12.0)*(solar_glow+.045*sky_phase.z);
    float crest=min(ripple.z,1.0);
    vec3 scatter=vec3(.033,.24,.21)*(1.0-transmit)+vec3(.12,.24,.22)*crest;
    ALBEDO=mix(scatter,mix(vec3(.11,.38,.40),vec3(.40,.67,.66),strands),cascade);
    EMISSION=(texture(scene_color,bend).rgb*transmit*(1.0-fres)+sky*fres)*(1.0-cascade);
    // PBR supplies the moving sun, moon and local fire highlights in their
    // actual light colours. Small differences in facet roughness break up the path.
    ROUGHNESS=mix(.12+.045*wind.x+.035*crest,.29,cascade); METALLIC=0.0; SPECULAR=.48;
    ALPHA=mix(1.0,.55+.19*strands,cascade);
}

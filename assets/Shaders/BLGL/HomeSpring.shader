shader_type spatial;
render_mode shading_model_pbr, blend_mix, cull_disabled, depth_draw_never;
varying float cascade;
void vertex(){cascade=COLOR.r;}
void fragment(){
    vec2 p=floor(UV*14.0)/14.0;
    float ripple=sin(p.y*3.2+TIME*1.45+sin(p.x*1.3+TIME*.5)*.75);
    float reflection=smoothstep(.88,.99,ripple)*smoothstep(.1,.75,sin(p.x*1.6-p.y*.6));
    float shoal=clamp(length((p-vec2(-7.5,-5.25))/vec2(10.,6.25)),0.,1.);
    vec3 pool=mix(vec3(.025,.23,.235),vec3(.10,.48,.41),shoal*.85)+reflection*.10;
    float filament=smoothstep(.55,.94,sin(p.x*8.+sin(p.y*.85+TIME*4.)*.6));
    ALBEDO=mix(pool,mix(vec3(.09,.44,.50),vec3(.54,.83,.80),filament),cascade);
    ROUGHNESS=.29; METALLIC=.04; SPECULAR=.42;
    ALPHA=mix(.76-.20*shoal,.57+.20*filament,cascade);
}

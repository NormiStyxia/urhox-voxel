// Forge RGB selects steel / gilt / stone; residual coverage selects leather.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 primary_color : source_color = vec4(0.78,0.84,0.93,1.0);
uniform vec4 secondary_color : source_color = vec4(0.84,0.65,0.36,1.0);
uniform vec4 grip_color : source_color = vec4(0.12,0.17,0.31,1.0);
uniform float steel_roughness = 0.27;
uniform float gold_roughness = 0.39;
uniform float reflection_strength = 0.30;
varying vec3 local_position;
void vertex() {
    local_position = VERTEX;
}
void fragment() {
    float steel = COLOR.r;
    float gilt = COLOR.g;
    float hide = clamp(1.0 - steel - gilt - COLOR.b,0.0,1.0);
    // Only the baked face tone is sRGB. The material IDs are numerical weights.
    float s = clamp(COLOR.a,0.0,1.0);
    float tone = s*(s*(s*0.305306011+0.682171111)+0.012522878);
    float recess = step(0.30,UV.x);
    vec3 alloy = primary_color.rgb * mix(vec3(1.0),vec3(0.43,0.54,0.70),recess);
    float grain_phase = local_position.y*680.0 + local_position.x*255.0 - local_position.z*195.0;
    float fibres = sin(grain_phase)*0.60 + sin(2.7*grain_phase + local_position.z*145.0)*0.40;
    ALBEDO = (alloy*steel + secondary_color.rgb*gilt + grip_color.rgb*hide*(1.0+0.08*fibres))*tone;
    METALLIC = steel*0.86+gilt*0.73;
    float surface_roughness = clamp(steel*(steel_roughness+0.16*(1.0-tone))+gilt*gold_roughness+hide*(0.75+0.055*fibres),0.12,0.9);
    // The .51 face-tone band belongs to the machined heel and the ferrule rebate.
    // Keep that contact surface matte as the polished rim turns into the light.
    float contact = (1.0 - smoothstep(0.53, 0.58, COLOR.a)) * (1.0 - hide);
    ROUGHNESS = mix(surface_roughness, 0.58, contact);
    SPECULAR = 0.55*steel + 0.48*gilt + 0.24*hide;
    vec3 n = normalize(NORMAL);
    vec3 view_delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 v = view_delta/max(length(view_delta),0.0001);
    float ndv = clamp(dot(n,v),0.0,1.0);
    vec3 r = 2.0*dot(n,v)*n-v;
    float rl = clamp(dot(r,MAIN_LIGHT_DIRECTION),0.0,1.0);
    float sky = smoothstep(-0.12,0.01,r.y)*0.5+smoothstep(0.46,0.56,r.y)*0.5;
    float fres = pow(1.0-ndv,3.5);
    vec3 steel_return = alloy*(sky*0.38+fres*0.30) + vec3(0.82,0.92,1.0)*pow(rl,110.0);
    vec3 gilt_return = secondary_color.rgb*(sky*0.27+fres*0.15+0.72*pow(rl,66.0));
    EMISSION = reflection_strength*(1.0-0.72*contact)*(steel*steel_return + gilt*gilt_return)*tone;
}

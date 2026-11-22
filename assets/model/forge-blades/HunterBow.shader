shader_type spatial;
render_mode shading_model_pbr, cull_back;
// Binary RGB selects wood, bone, or cord. The remaining channel is leather.
// Alpha is a continuous growth coordinate across the swept cross-section.
uniform vec4 wood_color : source_color = vec4(0.385,0.267,0.220,1.0);
uniform vec4 bone_color : source_color = vec4(0.835,0.714,0.604,1.0);
uniform vec4 leather_color : source_color = vec4(0.314,0.220,0.196,1.0);
uniform vec4 string_color : source_color = vec4(0.600,0.522,0.471,1.0);
uniform float bend = 0.0;
varying vec3 rest;
void vertex() {
    rest = VERTEX;
    float k = clamp(abs(rest.y)*2.0,0.0,1.0);
    VERTEX.z -= bend*k*k;
    NORMAL = normalize(vec3(NORMAL.x, NORMAL.y + 4.0*bend*k*sign(rest.y)*NORMAL.z, NORMAL.z));
}
// Smooth value noise in growth-coordinate / axial space follows the curved limb.
float grain_hash(vec2 cell) {
    return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
}
float fibre_noise(vec2 p) {
    vec2 i=floor(p);
    vec2 f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    return mix(mix(grain_hash(i),grain_hash(i+vec2(1.0,0.0)),u.x),
               mix(grain_hash(i+vec2(0.0,1.0)),grain_hash(i+vec2(1.0)),u.x),u.y);
}
void fragment() {
    vec3 c = clamp(COLOR.rgb,0.0,1.0);
    vec3 w = c*(c*(c*0.305306011+0.682171111)+0.012522878);
    float leather = clamp(1.0-w.r-w.g-w.b,0.0,1.0);
    float cord = w.b*step(0.75,UV.x);
    float grain = COLOR.a;
    float height = UV.y;
    vec2 fibrespace=vec2(grain*14.25,height*6.75);
    float runout=0.68*fibre_noise(fibrespace)+0.32*fibre_noise(fibrespace*2.7);
    float drift=sin(22.0*rest.y+2.2*sin(9.0*height));
    float rings=sin(grain*20.0+3.1*runout);
    float fibres=sin(210.0*grain+2.2*drift+4.0*runout);
    vec3 wood=wood_color.rgb*(0.66+0.55*runout+0.19*rings+0.075*fibres);
    // Perturb the normal across the local lamination direction and preserve unit length.
    vec3 axis=normalize(MODEL_NORMAL_MATRIX*vec3(0.26,0.0,1.0));
    vec3 tangent=axis-dot(axis,NORMAL)*NORMAL;
    NORMAL=normalize(NORMAL+0.045*w.r*tangent*cos(210.0*grain+2.2*drift+4.0*runout));
    float striae = sin(28.0*grain+1.3*sin(57.0*rest.y));
    float pores = sin(grain*110.0+rest.y*38.0)*sin(rest.x*371.0-rest.z*120.0);
    vec3 bone = bone_color.rgb*(0.96+0.09*striae+0.04*pores);
    float hide = sin(1510.0*rest.x+127.0*rest.y)*sin(1190.0*rest.z-711.0*rest.y);
    float crease = sin(220.0*rest.y+6.283185*grain);
    vec3 strap = leather_color.rgb*(0.92+0.07*hide+0.12*crease);
    float ply = sin(2250.0*rest.y+6.283185*grain);
    vec3 flax = string_color.rgb*(0.93+0.13*ply);
    vec3 v = CAMERA_POSITION_WORLD-VERTEX;
    float ndv = clamp(dot(normalize(NORMAL),v/max(length(v),0.00001)),0.0,1.0);
    float fres = pow(1.0-ndv,3.0);
    ALBEDO = (wood*w.r+bone*w.g+strap*leather+flax*cord)*(1.0+fres*(0.09*w.r+0.13*w.g+0.04*leather+0.07*cord));
    ROUGHNESS = (0.66+0.035*fibres)*w.r+(0.60+0.03*striae)*w.g+(0.81+0.035*hide)*leather+(0.87+0.02*ply)*cord;
    // All four partitions are dielectrics, including the pale ferrules.
    METALLIC = 0.0;
    SPECULAR = 0.21*w.r+0.32*w.g+0.14*leather+0.09*cord;
    EMISSION = vec3(0.0);
}

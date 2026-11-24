shader_type spatial;
render_mode shading_model_pbr, cull_disabled;
uniform sampler2D fault_atlas : filter_nearest, repeat_disable;
uniform float bed = 0.0;
uniform float heat = 0.0;
void fragment() {
    vec2 px = floor(clamp(UV,vec2(0.0),vec2(0.9999))*vec2(64.0,32.0));
    vec4 ink = textureLod(fault_atlas,(px+vec2(64.5,bed*32.0+.5))/vec2(192.0,160.0),0.0);
    float seam = step(.84,ink.r);
    float crest = 1.0-smoothstep(.05,.23,abs(heat-px.y/32.0));
    ALBEDO = ink.rgb*ink.rgb;
    EMISSION = vec3(1.0,.75,.40)*seam*heat*(.55+1.7*crest);
    ROUGHNESS=.90;
    METALLIC=0.0;
    SPECULAR=.38;
}

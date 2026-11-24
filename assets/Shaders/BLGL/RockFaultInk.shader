shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D fault_atlas : filter_nearest, repeat_disable;
uniform float bed = 0.0;
uniform float plume = 0.0;
uniform float brush = 0.0;
uniform float ash = -1.0;
void fragment() {
    vec2 px = floor(clamp(UV,vec2(0.0),vec2(0.9999))*vec2(64.0,32.0));
    vec2 at = (px+vec2(plume*128.0,bed*32.0)+0.5)/vec2(192.0,160.0);
    vec4 ink = textureLod(fault_atlas,at,0.0);
    float grain = mod(px.x*7.0+px.y*11.0,17.0)/17.0;
    float vein = step(0.89,ink.r);
    float along = px.y/32.0 + abs(px.x-mix(54.0,32.0,step(.5,bed)))/150.0 + grain*0.07;
    float fresh = step(along,brush);
    float rim = fresh*(1.0-step(0.16,brush-along));
    vec3 cold = ink.rgb*vec3(.75,.49,.64);
    vec3 col = mix(cold,ink.rgb,fresh);
    col += rim*(.25+.65*vein)*vec3(1.0,.66,.36);
    float a = ink.a*.96;
    if (ash>=0.0) {
        col = mix(vec3(.66,.22,.09),vec3(1.0,.65,.26),grain);
        a *= vein*step(ash,grain)*.65*(1.0-ash);
    }
    if (plume>.5) {
        col=ink.rgb;
        a=ink.a*.88*step(max(0.0,ash),grain);
    }
    ALBEDO = col*col;
    ALPHA = a;
}

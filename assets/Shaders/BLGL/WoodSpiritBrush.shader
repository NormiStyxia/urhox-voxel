shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D brush_atlas : filter_nearest, repeat_disable;
uniform float phase = 0.0;
uniform float impact = 0.0;

void fragment() {
    vec2 cell = min(floor(clamp(UV, vec2(0.0), vec2(1.0))*64.0), vec2(63.0));
    vec2 p = (cell+0.5)/64.0;
    vec4 ink = textureLod(brush_atlas, vec2(p.x, (p.y+impact)*0.5), 0.0);
    float grain = mod(cell.x*3.0 + floor(cell.y*0.5)*5.0, 11.0)/11.0;
    float distance_to_brush = mix(p.y, length((p-0.5)*2.0), impact);
    float edge = floor(clamp(phase,0.0,1.0)*24.0)/24.0*1.85 + 0.08;
    float reveal = step(distance_to_brush+grain*0.07, edge);
    float rim = 1.0-step(0.12,abs(edge-distance_to_brush));
    float wipe = step((phase-0.63)/0.37, grain*0.65+distance_to_brush*0.35+0.01);
    vec3 stroke = mix(ink.rgb,vec3(1.0,0.81,0.42),0.68*rim);
    float a = ink.a*reveal*wipe*mix(0.86,0.98,impact);
    // Banded clay remains after the root brush clears. Keep the middle translucent.
    float shoulder = abs(p.x-0.5)*1.7 + abs(p.y-0.52)*0.65;
    float band = 0.5*step(0.34,shoulder) + 0.5*step(0.62,shoulder);
    float soil = (1.0-impact)*(0.37 + 0.19*band + 0.08*step(0.78,phase));
    vec3 clay = mix(vec3(0.83,0.25,0.12),vec3(0.65,0.10,0.08),band);
    float opacity = a+soil*(1.0-a);
    ALBEDO = (stroke*a+clay*soil*(1.0-a))/max(0.001,opacity);
    ALPHA = opacity;
}

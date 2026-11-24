// The four hand-pixelled cuts are stacked vertically. Sample texel centres at
// LOD zero before alpha kill, including on WebGL/Metal derivative paths.
shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D fibre_ink : filter_nearest, repeat_disable;
uniform vec4 silk_tint = vec4(1.0);
uniform float cut = 0.0;
uniform float brush_age = 0.0;
uniform float rate = 1.0;
uniform float backing = 0.0;
void fragment() {
    vec2 size = vec2(64.0,32.0);
    vec2 cell = floor(clamp(UV,vec2(0.0),vec2(0.9999))*size);
    vec2 q = (cell+0.5)/size;
    vec4 ink = textureLod(fibre_ink,vec2(q.x,(cut+q.y)*0.25),0.0);
    float fibre = fract(dot(cell,vec2(0.15625,0.359375)));
    float reveal = 1.0;
    if (cut<1.5) reveal=step(q.x*0.45+q.y*0.17+fibre*0.25,0.16+brush_age*1.65);
    if (cut>2.5) reveal=step(brush_age*1.18,0.12+q.x*0.42+fibre*0.52);
    float sweep=fract(brush_age*rate+0.15);
    float edge=1.0-step(0.10,abs(q.x*0.75+q.y*0.2-sweep));
    vec3 dyed=mix(ink.rgb*silk_tint.rgb,ink.rgb,0.35);
    vec3 color=mix(silk_tint.rgb*0.59,dyed,ink.a);
    color=mix(color,vec3(1.0,0.91,0.68),ink.a*edge*0.68);
    float alpha=mix(backing,1.0,ink.a)*silk_tint.a*reveal;
    if (alpha<0.06) discard;
    ALBEDO=color; ALPHA=alpha;
}

shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, fog_disabled, world_vertex_coords;
// Ordinary depth-tested celestial patches. No screen/depth reads, forced clip depth,
// inverse projection, full-screen proxy or runtime density integration.
uniform sampler2D cloud_atlas : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float cloud_enabled = 0.0;
uniform float day = 1.0;
uniform float dusk = 0.0;
uniform float drift_time = 0.0;
uniform float motion_detail = 0.0; // Vertex breathing only; low tier stays static.
uniform vec4 cloud_wind = vec4(0.0); // displacement XZ metres / velocity XZ m/s
uniform vec4 sky_top = vec4(0.05,0.16,0.46,1.0);
uniform vec4 sky_horizon = vec4(0.45,0.60,0.83,1.0);
uniform vec4 sky_bottom = vec4(0.07,0.10,0.15,1.0);
varying vec3 cloud_direction;
varying vec3 cloud_right;
varying vec4 cloud_data;

void vertex() {
    // Input is already world space. Follow() moves only this model's origin for
    // CPU culling; subtract it before reading the fixed celestial directions.
    vec3 model_origin=(MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xyz;
    vec3 world_offset=VERTEX-model_origin;
    float radius=length(world_offset);
    vec3 direction=world_offset/max(radius,0.0001);
    vec3 right=vec3(NORMAL.z,0.0,-NORMAL.x);
    right=right/max(length(right),0.0001);
    vec3 up=cross(NORMAL,right);
    float denominator=max(dot(direction,NORMAL),0.0001);
    vec2 local_patch=vec2(dot(direction,right),dot(direction,up))/denominator;
    // UNORM vertex colours: horizon=.25, lower=.45, upper=.65.
    float layer_speed=0.5+step(0.35,COLOR.r)-0.5*step(0.55,COLOR.r);
    vec3 centre=NORMAL*radius;
    // Independent local wrap windows retain the approved all-around layout.
    // A global translated ring would accumulate clouds on the downwind horizon.
    vec2 start_phase=(vec2(COLOR.g,fract(COLOR.g*5.37))-vec2(0.5))*180.0;
    vec2 moved=cloud_wind.xy*layer_speed+start_phase;
    vec2 wrapped=fract((moved+vec2(180.0))/360.0)*360.0-vec2(180.0);
    vec2 centre_xz=centre.xz+wrapped-start_phase;
    float phase=COLOR.g*6.28318530718;
    float breathe_x=1.0+motion_detail*0.02*(sin(drift_time*0.012+phase)-sin(phase));
    float breathe_y=1.0+motion_detail*0.03*(sin(drift_time*0.008+phase*1.7)-sin(phase*1.7));
    float heave=motion_detail*1.5*(sin(drift_time*0.006+phase)-sin(phase));
    vec3 axis=normalize(vec3(centre_xz.x,centre.y+heave,centre_xz.y));
    // Stable tangent even when a cloud passes directly over/under the camera.
    vec3 tangent=vec3(axis.z,0.0,-axis.x);
    float tangent_length=length(tangent);
    cloud_right=mix(right,tangent/max(tangent_length,0.0001),step(0.0001,tangent_length));
    vec3 vertical=cross(axis,cloud_right);
    cloud_direction=normalize(axis+cloud_right*local_patch.x*breathe_x+vertical*local_patch.y*breathe_y);
    float wrap_fade=1.0-smoothstep(120.0,170.0,max(abs(wrapped.x),abs(wrapped.y)));
    cloud_data=vec4(COLOR.rgb,COLOR.a*wrap_fade);
    // Recenter by translation ONLY. Return world space, leaving the single
    // view/projection to the engine; never recover it through INV_VIEW_MATRIX.
    // Real 522..548m depth; current camera farClip=600m.
    VERTEX=CAMERA_POSITION_WORLD+cloud_direction*radius;
}

void fragment() {
    if (cloud_enabled<0.5) { discard; }
    // Stable silhouette: whole-cloud angular drift remains in vertex().
    // Do not wobble the AA edge by subpixel UV distortion.
    vec2 uv=UV;
    vec4 data=texture(cloud_atlas,uv);
    if (data.a<0.003) { discard; }
    vec3 dir=normalize(cloud_direction);
    vec3 sun=MAIN_LIGHT_DIRECTION;
    sun=length(sun)>0.001 ? sun/length(sun) : vec3(0.0,1.0,0.0);
    float toward=smoothstep(0.45,0.98,dot(dir,sun));
    float lateral=dot(sun,cloud_right);
    float shape_light=clamp(data.r+(data.b-0.5)*lateral*0.16,0.0,1.0);
    // Retain fine shoulder values instead of flattening the brightest lobes.
    float lit=mix(shape_light,smoothstep(0.28,0.98,shape_light),0.70);
    vec3 dark=mix(vec3(0.009,0.018,0.042),vec3(0.26,0.38,0.58),day);
    dark=mix(dark,vec3(0.18,0.105,0.20),dusk*0.82);
    vec3 light=mix(vec3(0.055,0.085,0.15),vec3(0.98,0.96,0.91),day);
    light=mix(light,vec3(1.0,0.40,0.18),dusk*(0.62+0.25*toward));
    vec3 color=mix(dark,light,lit);
    vec3 rim=mix(vec3(0.08,0.13,0.22),vec3(1.0,0.94,0.77),day);
    rim=mix(rim,vec3(1.0,0.67,0.28),dusk);
    color+=rim*data.g*toward*(0.22+0.40*dusk);
    vec3 air=dir.y>=0.0 ? mix(sky_horizon.rgb,sky_top.rgb,pow(max(dir.y,0.0),0.18))
        : mix(sky_horizon.rgb,sky_bottom.rgb,pow(max(-dir.y,0.0),0.28));
    float horizon=1.0-smoothstep(0.015,0.24,abs(dir.y));
    float haze=clamp(cloud_data.b*0.32+horizon*0.40,0.0,0.68);
    ALBEDO=clamp(mix(color,air,haze),vec3(0.0),vec3(1.15));
    // Body stays opaque, only the far horizon/AA boundary dissolves into the sky.
    ALPHA=clamp(data.a*(1.0-horizon*0.22)*cloud_data.a,0.0,1.0);
}

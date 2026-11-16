shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never, fog_disabled, world_vertex_coords;
// Ordinary depth-tested celestial patches. No screen/depth reads, forced clip depth,
// inverse projection, full-screen proxy or runtime density integration.
uniform sampler2D cloud_atlas : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float cloud_enabled = 0.0;
uniform float day = 1.0;
uniform float dusk = 0.0;
uniform float drift_time = 0.0;
uniform float motion_detail = 0.0; // Vertex breathing only; low still follows cloud_wind.
uniform vec4 cloud_wind = vec4(0.0); // displacement XZ metres / velocity XZ m/s
uniform vec4 sky_top = vec4(0.05,0.16,0.46,1.0);
uniform vec4 sky_horizon = vec4(0.45,0.60,0.83,1.0);
uniform vec4 sky_bottom = vec4(0.07,0.10,0.15,1.0);
// Real sun (not the moon-blended light node): xyz toward sun, w = solar elevation -1..1.
uniform vec4 sun_dir = vec4(0.0);
uniform vec4 sun_tint = vec4(1.0,0.95,0.86,1.0);
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
    vec3 sun=sun_dir.xyz;
    float elev=sun_dir.w;
    if (length(sun)<0.001) {
        sun=MAIN_LIGHT_DIRECTION;
        elev=sun.y;
    }
    sun=length(sun)>0.001 ? sun/length(sun) : vec3(0.0,1.0,0.0);
    float cos_sun=dot(dir,sun);
    float toward=smoothstep(0.45,0.98,cos_sun);
    // Horizontal facing: 1 = cloud in the sunset direction, 0 = opposite (anti-twilight) side.
    vec2 dxz=dir.xz/max(length(dir.xz),0.0001);
    vec2 sxz=sun.xz/max(length(sun.xz),0.0001);
    float facing=dot(dxz,sxz)*0.5+0.5;
    // Height inside the baked silhouette: 0 = cloud base, 1 = top.
    float height=1.0-fract(uv.y*2.0);
    // Afterglow: higher clouds keep catching the sun a little after sunset.
    float sun_alive=smoothstep(-0.20,0.02,elev+max(dir.y,0.0)*0.20);
    // sqrt widens the dusk window so the fire clouds last longer and saturate fully.
    float fire=clamp(sqrt(dusk)*1.45-0.10,0.0,1.0)*sun_alive;
    float lateral=dot(sun,cloud_right);
    float shape_light=clamp(data.r+(data.b-0.5)*lateral*0.16,0.0,1.0);
    // Low sun lights the cloud from below/side; base glows, tops on the far side go shaded.
    float low_sun=1.0-smoothstep(0.02,0.30,elev);
    shape_light=clamp(shape_light+fire*low_sun*(0.50-height)*(0.35+0.55*facing)+fire*0.12,0.0,1.0);
    // Retain fine shoulder values instead of flattening the brightest lobes.
    float lit=mix(shape_light,smoothstep(0.28,0.98,shape_light),0.70);

    // Shadow side takes the surrounding sky, so clouds sit inside the same atmosphere.
    vec3 sky_amb=mix(sky_horizon.rgb,sky_top.rgb,0.6);
    vec3 dark=mix(vec3(0.009,0.018,0.042),vec3(0.26,0.38,0.58),day);
    dark=mix(dark,sky_amb*0.80,0.30*day);
    vec3 dusk_dark=mix(vec3(0.34,0.12,0.34),sky_amb*0.75,0.20);
    dusk_dark=mix(dusk_dark,vec3(0.62,0.18,0.22),facing*0.60);
    dark=mix(dark,dusk_dark,max(dusk*0.75,fire));

    vec3 light=mix(vec3(0.055,0.085,0.15),vec3(0.98,0.96,0.91),day);
    light=mix(light,light*mix(vec3(1.0),sun_tint.rgb,0.35),day*(1.0-day));
    // Fire clouds: gold right at the sun, orange around it, pink/rose on the opposite sky.
    vec3 fire_lit=mix(vec3(1.0,0.42,0.56),vec3(1.0,0.34,0.08),smoothstep(0.20,0.80,facing));
    fire_lit=mix(fire_lit,vec3(1.0,0.72,0.30),toward);
    fire_lit=mix(fire_lit,fire_lit*sun_tint.rgb*1.25,0.30)*1.15;
    light=mix(light,fire_lit,fire);
    vec3 color=mix(dark,light,lit);
    // Hot base on the sunset side: the classic burning underside.
    float belly=fire*low_sun*(1.0-smoothstep(0.0,0.55,height))*smoothstep(0.30,0.95,facing);
    color+=vec3(1.0,0.30,0.06)*belly*data.a*0.75;

    // Silver/gold lining: thin edges forward-scatter the sun.
    float edge=clamp(data.a*(1.0-data.a)*4.0,0.0,1.0);
    float mie=pow(max(cos_sun,0.0),6.0);
    vec3 rim=mix(vec3(0.08,0.13,0.22),vec3(1.0,0.96,0.85),day);
    rim=mix(rim,vec3(1.0,0.70,0.32),fire);
    color+=rim*data.g*toward*(0.22+0.80*fire);
    color+=rim*(edge*0.6+data.g*0.4)*mie*(0.30*day+1.30*fire);
    vec3 air=dir.y>=0.0 ? mix(sky_horizon.rgb,sky_top.rgb,pow(max(dir.y,0.0),0.18))
        : mix(sky_horizon.rgb,sky_bottom.rgb,pow(max(-dir.y,0.0),0.28));
    float horizon=1.0-smoothstep(0.015,0.24,abs(dir.y));
    float haze=clamp(cloud_data.b*0.32+horizon*0.40,0.0,0.68)*(1.0-0.70*fire);
    ALBEDO=clamp(mix(color,air,haze),vec3(0.0),vec3(1.60));
    // Body stays opaque, only the far horizon/AA boundary dissolves into the sky.
    ALPHA=clamp(data.a*(1.0-horizon*0.22)*cloud_data.a,0.0,1.0);
}

shader_type spatial;
render_mode shading_model_unlit, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled, skip_vertex_transform;
uniform highp sampler2D scene_depth : hint_depth_texture;
uniform float day = 1.0;
uniform float dusk = 0.0;
// Lua传入Color，材质API自动转线性；不得再次做sRGB解码。
uniform vec4 sky_top = vec4(0.30, 0.50, 0.80, 1.0);
uniform vec4 sky_horizon = vec4(0.65, 0.75, 0.90, 1.0);

// 256x96x256 scalar voxels packed into 16x16 slices. R/G/B are quality fields.
// No albedo image, visible quad, normal shell, temporal history or compute dependency.
uniform sampler2D density_volume : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D occupancy_volume : filter_nearest, repeat_disable, hint_default_black;
uniform vec3 volume_dims = vec3(256.0,96.0,256.0);
uniform vec2 atlas_dims = vec2(4096.0,1536.0);
uniform float use_occupancy = 0.0;
uniform float use_volume = 0.0;
uniform int quality_channel = 0;
uniform int view_steps = 64;
uniform int traversal_steps = 96;
uniform int light_steps = 1;
uniform float upper_enabled = 1.0;
uniform float lower_enabled = 1.0;
uniform float horizon_only = 0.0;
uniform float drift_time = 0.0;
uniform float fog_start = 100.0;
uniform float fog_end = 300.0;
uniform int diagnostic = 0;

bool finite3(vec3 v) { return all(lessThan(abs(v), vec3(1000000.0))); }

void vertex() {
    // REVERSED_Z 下深度0是远平面（可能在无穷远），取两个端点中更近的有效点。
    vec4 a = INV_PROJECTION_MATRIX * vec4(UV * 2.0 - 1.0, 0.0, 1.0);
    vec4 b = INV_PROJECTION_MATRIX * vec4(UV * 2.0 - 1.0, 1.0, 1.0);
    vec3 pa = abs(a.w)>0.000001 ? a.xyz/a.w : vec3(1e12);
    vec3 pb = abs(b.w)>0.000001 ? b.xyz/b.w : vec3(1e12);
    VERTEX = length(pa)<=length(pb) ? pa : pb;
    Z_CLIP_SCALE = 0.0;
}

// Explicit parallel slab avoids 0*Inf and handles origins on a face.
vec2 slab(float o, float d, float lo, float hi) {
    if (abs(d) < 0.000001) {
        if (o < lo || o > hi) { return vec2(1.0, -1.0); }
        return vec2(-2000000.0, 2000000.0);
    }
    float a = (lo-o)/d;
    float b = (hi-o)/d;
    return vec2(min(a,b),max(a,b));
}

vec2 volume_interval(vec3 ro, vec3 rd) {
    vec2 x = slab(ro.x,rd.x,-320.0,320.0);
    vec2 z = slab(ro.z,rd.z,-320.0,320.0);
    if (x.y < x.x || z.y < z.x) { return vec2(1.0,-1.0); }
    // 不能命名为 common：GLES 保留字会让整个着色器编译失败。
    vec2 bounds=vec2(max(0.0,max(x.x,z.x)),min(600.0,min(x.y,z.y)));
    vec2 upper=slab(ro.y,rd.y,30.0,160.0);
    vec2 lower=slab(ro.y,rd.y,-96.0,-8.0);
    upper=vec2(max(bounds.x,upper.x),min(bounds.y,upper.y));
    lower=vec2(max(bounds.x,lower.x),min(bounds.y,lower.y));
    bool has_upper=upper_enabled>0.5 && upper.y>upper.x;
    bool has_lower=lower_enabled>0.5 && lower.y>lower.x;
    if (has_upper && has_lower) { return vec2(min(upper.x,lower.x),max(upper.y,lower.y)); }
    if (has_upper) { return upper; }
    if (has_lower) { return lower; }
    return vec2(1.0,-1.0);
}

vec2 slice_uv(vec2 xy, float z) {
    return (vec2(mod(z,16.0)*volume_dims.x,floor(z/16.0)*volume_dims.y)+xy+vec2(0.5))/atlas_dims;
}
vec3 volume_position(vec3 world) {
    float speed=world.y < 0.0 ? 0.7 : 1.0;
    return world-vec3(sin(drift_time*0.01*speed)*7.0,0.0,sin(drift_time*0.006*speed)*5.0);
}
float next_face(float p,float d,float lo,float width) {
    if (abs(d)<0.000001) { return 100000.0; }
    float cell=floor((p-lo)/width);
    float face=lo+(cell+(d>0.0 ? 1.0 : 0.0))*width;
    return max((face-p)/d,0.0);
}
float cell_exit(vec3 p,vec3 rd) {
    return min(next_face(p.x,rd.x,-320.0,20.0),min(next_face(p.y,rd.y,-96.0,8.0),next_face(p.z,rd.z,-320.0,20.0)));
}
float occupied(vec3 p) {
    vec3 cell=floor((p-vec3(-320.0,-96.0,-320.0))/vec3(20.0,8.0,20.0));
    if (any(lessThan(cell,vec3(0.0))) || any(greaterThan(cell,vec3(31.0)))) { return 0.0; }
    vec2 uv=(vec2(mod(cell.z,8.0)*32.0,floor(cell.z/8.0)*32.0)+cell.xy+vec2(0.5))/vec2(256.0,128.0);
    vec3 mask=textureLod(occupancy_volume,uv,0.0).rgb;
    return quality_channel==0 ? mask.r : mask.g;
}
float ellipsoid(vec3 p, vec3 center, vec3 radii) {
    float d=length((p-center)/radii);
    return 0.8*(1.0-smoothstep(0.65,1.0,d));
}
float density(vec3 world) {
    // The authored fields and analytic fallback are empty in the playable-height gap.
    // This also skips texture work while rays cross between upper and lower layers.
    if (world.y > -8.0 && world.y < 30.0) { return 0.0; }
    if (world.y < 0.0 && lower_enabled < 0.5) { return 0.0; }
    if (world.y >= 0.0 && upper_enabled < 0.5) { return 0.0; }
    vec3 p=volume_position(world);
    if (use_volume < 0.5) {
        if (horizon_only > 0.5) {
            return max(ellipsoid(p,vec3(-160.0,52.0,180.0),vec3(65.0,12.0,38.0)),ellipsoid(p,vec3(140.0,54.0,-160.0),vec3(70.0,13.0,35.0)));
        }
        float upper=max(ellipsoid(p,vec3(-70.0,65.0,30.0),vec3(35.0,24.0,28.0)),ellipsoid(p,vec3(80.0,70.0,-50.0),vec3(43.0,30.0,32.0)));
        float lower=max(ellipsoid(p,vec3(-90.0,-50.0,70.0),vec3(60.0,16.0,45.0)),ellipsoid(p,vec3(95.0,-54.0,-60.0),vec3(58.0,18.0,48.0)));
        return max(upper*upper_enabled,lower*lower_enabled);
    }
    vec3 q=(p-vec3(-320.0,-96.0,-320.0))/vec3(640.0,256.0,640.0);
    if (any(lessThan(q,vec3(0.0))) || any(greaterThan(q,vec3(1.0)))) { return 0.0; }
    vec3 v=q*(volume_dims-vec3(1.0));
    float z=floor(v.z);
    // Explicit LOD: derivatives inside a divergent integration loop are undefined.
    vec3 a=textureLod(density_volume,slice_uv(v.xy,z),0.0).rgb;
    vec3 b=textureLod(density_volume,slice_uv(v.xy,min(z+1.0,volume_dims.z-1.0)),0.0).rgb;
    vec3 d=mix(a,b,fract(v.z));
    float selected=quality_channel==0 ? d.r : (quality_channel==1 ? d.g : d.b);
    return clamp(selected,0.0,1.0);
}

void fragment() {
    ALBEDO=vec3(0.0); ALPHA=0.0;
    vec2 ndc=SCREEN_UV*2.0-1.0;
    // 深度约定可能是正向（近0远1）或 REVERSED_Z（近1远0）。射线不再依赖它：
    // 起点固定为相机，方向取相机到反投影点；两个深度端点都在相机前方。
    vec4 v0=INV_PROJECTION_MATRIX*vec4(ndc,0.0,1.0);
    vec4 v1=INV_PROJECTION_MATRIX*vec4(ndc,1.0,1.0);
    bool ok0=abs(v0.w)>0.000001, ok1=abs(v1.w)>0.000001;
    vec3 p0=ok0 ? v0.xyz/v0.w : vec3(0.0);
    vec3 p1=ok1 ? v1.xyz/v1.w : vec3(0.0);
    ok0=ok0 && finite3(p0); ok1=ok1 && finite3(p1);
    if (!ok0 && !ok1) { discard; }
    // 远端可能在无穷远（w≈0）；取更近的有效端点定方向，并据此判定哪个深度值是远平面。
    float d0=ok0 ? length(p0) : 1e12;
    float d1=ok1 ? length(p1) : 1e12;
    vec3 dir_view=d0<=d1 ? p0 : p1;
    float far_raw=d0<=d1 ? 1.0 : 0.0;
    vec3 ro=INV_VIEW_MATRIX[3].xyz;
    vec3 delta=(INV_VIEW_MATRIX*vec4(dir_view,0.0)).xyz;
    float ray_length=length(delta);
    if (!finite3(ro) || !finite3(delta) || !(ray_length>0.000001)) { discard; }
    vec3 rd=delta/ray_length;
    vec2 hit=volume_interval(ro,rd);
    if (!(hit.y>hit.x)) { discard; }
    float raw=textureLod(scene_depth,SCREEN_UV,0.0).r;
    // Invalid depth fails transparent; cleared far plane never divides by far w.
    if (!(raw>=0.0 && raw<=1.0)) { discard; }
    float scene_t=600.0;
    if (abs(raw-far_raw)>0.000001) {
        vec4 sv=INV_PROJECTION_MATRIX*vec4(ndc,raw,1.0);
        if (!(abs(sv.w)>0.000001)) { discard; }
        vec3 view=sv.xyz/sv.w;
        if (!finite3(view)) { discard; }
        scene_t=clamp(length(view),0.0,600.0);
    }
    hit.y=min(hit.y,scene_t);
    if (!(hit.y>hit.x)) { discard; }
    int steps=clamp(view_steps,8,64);
    bool adaptive=use_volume>0.5 && use_occupancy>0.5 && horizon_only<0.5;
    int iterations=adaptive ? clamp(traversal_steps,steps,96) : steps;
    float fixed_step=(hit.y-hit.x)/float(steps);
    vec3 sun=MAIN_LIGHT_DIRECTION;
    float sun_length=length(sun);
    if (!finite3(sun) || !(sun_length>0.001)) { sun=vec3(0.0,1.0,0.0); }
    else { sun=sun/sun_length; }
    float mu=clamp(dot(rd,sun),-1.0,1.0);
    // Bounded Henyey-Greenstein forward lobe (g=.45), normalized relative to isotropic.
    float phase=0.7975/pow(max(1.2025-0.9*mu,0.30),1.5);
    vec3 horizon=clamp(sky_horizon.rgb,vec3(0.0),vec3(1.0));
    vec3 zenith=clamp(sky_top.rgb,vec3(0.0),vec3(1.0));
    vec3 dark=mix(vec3(0.012,0.023,0.052),vec3(0.13,0.21,0.36),day);
    dark=mix(dark,vec3(0.24,0.18,0.31),dusk*0.65);
    vec3 light=mix(vec3(0.07,0.11,0.20),vec3(0.94,0.93,0.88),day);
    light=mix(light,vec3(1.0,0.56,0.29),dusk*0.72);
    float trans=1.0;
    vec3 scatter=vec3(0.0);
    float t=hit.x;
    int samples=0;
    for (int i=0;i<96;i++) {
        if (i>=iterations || samples>=steps || trans<0.008 || t>=hit.y) { break; }
        float ds=fixed_step;
        if (adaptive) {
            vec3 probe=volume_position(ro+rd*(t+0.002));
            float edge=cell_exit(probe,rd)+0.004;
            if (occupied(probe)<0.5) { t+=max(edge,0.004); continue; }
            float fine=quality_channel==0 ? clamp(1.25+t*0.004,1.25,2.6) : clamp(3.0+t*0.008,3.0,5.5);
            ds=min(fine,edge);
        }
        ds=min(ds,hit.y-t);
        float sample_t=t+0.5*ds;
        vec3 p=ro+rd*sample_t;
        float d=density(p)*smoothstep(0.25,2.0,sample_t)*smoothstep(0.0,2.0,scene_t-sample_t);
        samples+=1;
        if (d>0.001) {
            float shadow=0.0;
            if (light_steps>0) { shadow=density(p+sun*8.0)*28.0; }
            float visibility=exp(-min(shadow*0.11,12.0));
            float band=0.35*smoothstep(0.12,0.42,visibility)+0.65*smoothstep(0.48,0.88,visibility);
            float height=smoothstep(p.y<0.0 ? -75.0 : 42.0,p.y<0.0 ? -28.0 : 115.0,p.y);
            vec3 ambient=mix(dark,zenith,0.12+height*0.12);
            vec3 lum=ambient*(0.48+height*0.12)+light*(0.08+0.92*mix(visibility,band,0.3))*(0.72+0.22*phase);
            // Air perspective per integration sample, not at an invisible proxy surface.
            float fog=smoothstep(fog_start,max(fog_start+1.0,fog_end),sample_t)*0.55;
            lum=mix(lum,horizon,fog);
            float tr=exp(-min(d*0.11*ds,12.0));
            scatter+=trans*(1.0-tr)*lum;
            trans*=tr;
        }
        t+=max(ds,0.004);
    }
    float opacity=clamp(1.0-trans,0.0,1.0);
    if (!finite3(scatter) || !(opacity>=0.0 && opacity<=1.0)) { discard; }
    ALBEDO=clamp(scatter,vec3(0.0),vec3(2.0));
    ALPHA=opacity;
    if (diagnostic==1) { ALBEDO=vec3(opacity); }
    if (diagnostic==2) { ALBEDO=vec3(hit.x/600.0,hit.y/600.0,0.0)*opacity; }
    // Scatter already premultiplied. Exactly one composite for all overlapping volumes.
    PREMUL_ALPHA_FACTOR=1.0;
}

// Common-tier iron. Vertex RGB selects steel / carved fitting / reserved.
// The residual channel is indigo leather. UV.x=.35 marks inset steel or stone.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform vec4 primary_color : source_color = vec4(0.84, 0.89, 0.96, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.72, 0.78, 0.86, 1.0);
uniform vec4 grip_color : source_color = vec4(0.15, 0.25, 0.43, 1.0);
uniform float steel_roughness = 0.27;
uniform float grind_variation = 0.044;
uniform float iron_roughness = 0.40;
uniform float leather_roughness = 0.76;
uniform float fibre_strength = 0.10;
uniform float environment_strength = 0.32;
uniform float highlight_strength = 0.26;
varying vec3 local_position;

void vertex() {
    local_position = VERTEX;
}

void fragment() {
    vec3 c = clamp(COLOR.rgb, 0.0, 1.0);
    // Iron exports one-hot material selectors. Exact 0/1 survives sRGB decode.
    vec3 weights = c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
    float steel = weights.r;
    float iron = weights.g;
    float leather = clamp(1.0 - weights.r - weights.g - weights.b, 0.0, 1.0);
    float inset = step(0.30, UV.x);
    // RGB carries categorical weights. The artist-authored tonal value in A
    // encodes sRGB brightness. Linearise it before modulating the PBR colors.
    float s = clamp(COLOR.a, 0.0, 1.0);
    float linear_shade = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878);
    float grain = sin(local_position.x * 1120.0 + local_position.z * 755.0 + UV.y * 95.0);
    float fibres = grain * sin(local_position.y * 780.0 + grain * 2.3);
    vec3 leather_base = grip_color.rgb * (1.0 + fibres * fibre_strength);
    float carved = iron * inset;
    vec3 steel_base = mix(primary_color.rgb, primary_color.rgb * vec3(0.90,0.93,0.97), inset);
    vec3 base = steel_base * steel + secondary_color.rgb * iron * (1.0 - 0.30 * carved) + leather_base * leather;
    METALLIC = steel * 0.88 + iron * (0.76 - 0.53 * carved);
    float grind = sin(local_position.x * 293.0 + local_position.z * 517.0 + local_position.y * 8.0);
    float brushing = grind * sin(local_position.x * 451.0 - local_position.y * 12.0);
    float surface_roughness = clamp(steel * (steel_roughness + 0.06 * inset + grind_variation * brushing) + iron * (iron_roughness + 0.19 * carved)
                    + leather * clamp(leather_roughness + fibres * 0.045, 0.55, 0.90), 0.12, 0.90);
    // The .51 face-tone band belongs to the machined heel and the ferrule rebate.
    // Keep that contact surface matte as the polished rim turns into the light.
    float contact = (1.0 - smoothstep(0.53, 0.58, COLOR.a)) * (1.0 - leather);
    ROUGHNESS = mix(surface_roughness, 0.58, contact);
    SPECULAR = 0.64 * steel + (0.52 - 0.20 * carved) * iron + 0.23 * leather;

    vec3 N = normalize(NORMAL);
    vec3 delta = CAMERA_POSITION_WORLD - VERTEX;
    vec3 V = delta / max(length(delta), 0.0001);
    float ndv = clamp(dot(N, V), 0.0, 1.0);
    float fresnel = pow(1.0 - ndv, 3.0);
    vec3 R = 2.0 * dot(N, V) * N - V;
    float up = R.y * 0.5 + 0.5;
    float sky = 0.52 * smoothstep(0.36, 0.48, up) + 0.48 * smoothstep(0.66, 0.76, up);
    vec3 reflection = mix(vec3(0.27,0.34,0.44), vec3(0.96,0.98,1.0), sky);
    float rl = clamp(dot(R, MAIN_LIGHT_DIRECTION), 0.0, 1.0);
    float glint = steel * pow(rl, 108.0) + iron * (1.0 - 0.7 * carved) * pow(rl, 72.0);
    vec3 metal_return = base * (reflection - vec3(0.45)) * environment_strength * METALLIC;
    vec3 rim = base * fresnel * (0.18 * steel + 0.11 * iron + 0.04 * leather);
    ALBEDO = clamp((base + (metal_return + rim) * (1.0 - 0.72 * contact)) * linear_shade
                 + MAIN_LIGHT_COLOR * glint * highlight_strength * (1.0 - contact), 0.0, 1.0);
    EMISSION = vec3(0.0);
}

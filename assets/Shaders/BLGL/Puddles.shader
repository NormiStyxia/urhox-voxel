shader_type spatial;
render_mode gbuffer_postprocess;

uniform float coverage : hint_range(0.0, 1.0) = 0.48;
uniform float puddle_size : hint_range(0.5, 10.0) = 3.5;
uniform float puddle_roughness : hint_range(0.02, 0.4) = 0.045;

float hash21(vec2 p)
{
    vec3 h = fract(vec3(p.x, p.y, p.x) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

float noise2(vec2 p)
{
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
               mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment()
{
    if (SHADING_MODEL == SHADING_MODEL_PBR || SHADING_MODEL == SHADING_MODEL_TOON)
    {
        // The sample's crossing roads are 8 m wide with their surface at world y = 0.
        // Height and slope limit the demo to pavement; they do not provide rain occlusion.
        float road = 1.0 - smoothstep(3.7, 4.0, min(abs(VERTEX.x), abs(VERTEX.z)));
        float ground = 1.0 - smoothstep(0.05, 0.18, abs(VERTEX.y));
        float upward = smoothstep(0.88, 0.98, NORMAL.y);
        float exposed = road * ground * upward * RAIN_EXPOSURE;
        if (exposed > 0.0 && coverage > 0.0)
        {
            // Static world-space noise keeps puddle edges fixed while the camera moves.
            vec2 p = VERTEX.xz / max(puddle_size, 0.5);
            float field = noise2(p) * 0.65
                + noise2(p * 2.17 + vec2(7.3, 19.1)) * 0.25
                + noise2(p * 4.11 + vec2(23.7, 5.9)) * 0.10;
            float threshold = 1.0 - coverage;
            float damp = smoothstep(threshold - 0.09, threshold, field) * exposed;
            float puddle = smoothstep(threshold, threshold + 0.065, field) * exposed;

            ALBEDO *= mix(1.0, 0.68, damp) * mix(1.0, 0.68, puddle);
            ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.3), damp);
            ROUGHNESS = mix(ROUGHNESS, puddle_roughness, puddle);
            SPECULAR = mix(SPECULAR, 0.35, puddle);
            METALLIC = mix(METALLIC, 0.0, puddle);
        }
    }
}

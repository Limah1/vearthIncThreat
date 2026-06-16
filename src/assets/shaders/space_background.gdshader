// res://src/assets/shaders/space_background.gdshader
shader_type canvas_item;

uniform vec4 left_color : source_color = vec4(0.28, 0.02, 0.45, 1.0);
uniform vec4 right_color : source_color = vec4(0.02, 0.01, 0.12, 1.0);
uniform float speed : hint_range(0.0, 5.0) = 0.3;

// Simple pseudo-random function
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    // 1. Base Gradient (vibrant purple on left, dark indigo on right)
    float grad_t = UV.x;
    vec4 base_gradient = mix(left_color, right_color, grad_t);
    
    // Add a subtle glowing nebulous center-left light source
    vec2 glow_center = vec2(-0.1, 0.5);
    float dist_to_glow = distance(UV, glow_center);
    float glow = smoothstep(1.3, 0.0, dist_to_glow) * 0.22;
    base_gradient.rgb += vec3(0.75, 0.15, 0.85) * glow;

    // 2. Faint drifting bokeh circles
    float stars = 0.0;
    
    // Create 2 layers of grid-based stars for depth
    for (float i = 0.0; i < 2.0; i++) {
        // Different grid scale for each layer
        float scale = 6.0 + i * 4.0;
        vec2 uv = UV * vec2(scale, scale * 0.5625); // Aspect ratio correction
        vec2 id = floor(uv);
        vec2 gv = fract(uv) - 0.5;
        
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 offs = vec2(float(x), float(y));
                vec2 cur_id = id + offs;
                
                float h = hash(cur_id + vec2(i * 15.7, i * 82.4));
                if (h > 0.4) { // 60% spawn chance
                    // Slow time-based drifting motion
                    float time_offset = TIME * speed * (0.6 + 0.4 * h);
                    vec2 move = vec2(
                        sin(time_offset + h * 6.28),
                        cos(time_offset + h * 6.28)
                    ) * 0.3;
                    
                    vec2 star_pos = offs + move;
                    
                    // Soft circle size and blur factor
                    float size = 0.04 + 0.08 * hash(cur_id + vec2(12.0, 34.0));
                    // Add pulsing brightness
                    float pulse = 0.7 + 0.3 * sin(TIME * (0.5 + h * 1.5) + h * 6.28);
                    float intensity = (0.05 + 0.12 * hash(cur_id + vec2(56.0, 78.0))) * pulse;
                    
                    float d = length(gv - star_pos);
                    // Draw soft blurred dot
                    stars += smoothstep(size, 0.0, d) * intensity;
                }
            }
        }
    }
    
    COLOR = vec4(base_gradient.rgb + vec3(0.75, 0.85, 1.0) * stars, 1.0);
}

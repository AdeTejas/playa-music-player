#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;

out vec4 fragColor;

// Simple noise function
float noise(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    
    // Create a subtle grain/frost effect
    float n = noise(uv + uTime * 0.5);
    
    // Base color: Dark glass tint
    vec3 baseColor = vec3(0.05, 0.05, 0.08);
    
    // Add noise to alpha for "frosted" texture
    float alpha = 0.85 + n * 0.05;
    
    fragColor = vec4(baseColor, alpha);
}

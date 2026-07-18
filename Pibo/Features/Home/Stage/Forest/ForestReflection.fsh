void main() {
    float height = mix(u_height_min, u_height_max, v_tex_coord.y);
    float waterDepth = clamp(height, 0.0, 1.0);
    float powerScale = mix(0.52, 1.0, u_ripple_detail);
    float broad = sin(waterDepth * 13.2 + v_tex_coord.x * 7.074 - u_ripple_phase * 5.7);
    float fine = sin(waterDepth * 31.0 + v_tex_coord.x * 16.113 - u_ripple_phase * 10.4)
        * 0.34 * u_ripple_detail;
    float ripple = (broad + fine) * (0.6 + 1.8 * waterDepth)
        * u_ripple_strength * powerScale * u_ripple_scale;
    vec2 sampleCoordinate = vec2(v_tex_coord.x - ripple, v_tex_coord.y);
    vec4 reflected = texture2D(u_texture, sampleCoordinate);
    float fade = mix(1.0, 0.18, pow(clamp(height, 0.0, 1.0), 0.75));
    vec3 waterTint = vec3(0.090, 0.290, 0.225);
    vec3 straightColor = reflected.rgb / max(reflected.a, 0.002);
    straightColor = mix(straightColor, waterTint, 0.56);
    float outputAlpha = reflected.a * fade;
    gl_FragColor = vec4(straightColor * outputAlpha, outputAlpha);
}

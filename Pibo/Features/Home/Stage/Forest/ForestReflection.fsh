void main() {
    vec4 reflected = texture2D(u_texture, v_tex_coord);
    float height = mix(u_height_min, u_height_max, v_tex_coord.y);
    float fade = mix(1.0, 0.18, pow(clamp(height, 0.0, 1.0), 0.75));
    vec3 waterTint = vec3(0.090, 0.290, 0.225);
    vec3 straightColor = reflected.rgb / max(reflected.a, 0.002);
    straightColor = mix(straightColor, waterTint, 0.56);
    float outputAlpha = reflected.a * fade;
    gl_FragColor = vec4(straightColor * outputAlpha, outputAlpha);
}

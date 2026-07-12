void main() {
    vec4 sample = texture2D(u_texture, v_tex_coord);
    if (sample.a > 0.001) {
        // Work in straight alpha so tinting never creates a colored fringe
        // around transparent edges of the vector-derived textures.
        vec3 color = sample.rgb / sample.a;
        float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = mix(vec3(luminance), color, u_saturation);
        color *= 1.0 - u_darkness;
        color = mix(color, color * u_tint, u_tint_amount);
        color = clamp(color + vec3(u_lift), 0.0, 1.0);
        gl_FragColor = vec4(color * sample.a, sample.a);
    } else {
        gl_FragColor = vec4(0.0);
    }
}

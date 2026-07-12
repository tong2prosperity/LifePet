void main() {
    vec2 uv = v_tex_coord;
    vec4 mask = texture2D(u_texture, uv);
    float t = u_flow_time * u_flow_speed;
    float flowY = 1.0 - uv.y;

    float broad = sin(flowY * 24.0 + uv.x * 5.0 - t * 4.2);
    float fine = 0.0;
    float vertical = 0.0;
    if (u_low_power < 0.5) {
        fine = sin(flowY * 57.0 - uv.x * 9.0 - t * 8.4);
        vertical = sin(uv.x * 18.0 + flowY * 7.0 - t * 3.1);
    }
    vec2 offset = vec2(
        (broad * 0.0100 + fine * 0.0034) * u_ripple_strength,
        vertical * 0.0035 * u_ripple_strength
    );
    vec4 shifted = texture2D(u_texture, clamp(uv + offset, 0.0, 1.0));

    vec3 base = vec3(0.247, 0.792, 0.773);
    float shiftedVisible = step(0.002, shifted.a);
    vec3 shiftedColor = shifted.rgb / max(shifted.a, 0.002);
    vec3 color = mix(base, shiftedColor, shiftedVisible);
    color *= 1.0 - u_darkness;
    color = mix(color, color * u_tint, u_tint_amount);
    color = clamp(color, 0.0, 1.0);
    gl_FragColor = vec4(color * mask.a, mask.a);
}

void main() {
    vec2 uv = v_tex_coord;
    vec4 original = texture2D(u_texture, uv);

    float t = u_flow_time * u_flow_speed;
    // SpriteKit texture V increases from bottom to top. Invert it so the
    // animated phase increases in the river's downstream screen direction.
    float flowY = 1.0 - uv.y;
    float light = 0.0;
    if (u_low_power < 0.5) {
        float bandCurve = sin(uv.x * 9.0) * 0.08;
        float sparkleCurve = sin(uv.x * 19.0 + 1.4) * 0.06;
        float band = pow(max(0.0, sin((flowY * 14.0 + bandCurve - t) * 6.28318)), 10.0);
        float sparkle = pow(max(0.0, sin((flowY * 67.0 + sparkleCurve - t * 2.2) * 6.28318)), 18.0);
        light = (band * 0.12 + sparkle * 0.20) * u_highlight_strength;
    }

    float outputAlpha = original.a * light;
    vec4 outputColor = vec4(vec3(outputAlpha), outputAlpha);
    if (u_mask_preview > 0.5) {
        outputAlpha = original.a * 0.76;
        outputColor = vec4(vec3(0.05, 0.85, 1.0) * outputAlpha, outputAlpha);
    }
    gl_FragColor = outputColor;
}

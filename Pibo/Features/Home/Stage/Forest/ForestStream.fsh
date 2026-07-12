void main() {
    vec2 uv = v_tex_coord;
    vec4 original = texture2D(u_texture, uv);

    float t = u_flow_time * u_flow_speed;
    // SpriteKit texture V increases from bottom to top. Invert it so the
    // animated phase increases in the river's downstream screen direction.
    float flowY = 1.0 - uv.y;
    float broadCurve = sin(uv.x * 8.0) * 0.45;
    float broad = sin(flowY * 33.0 + broadCurve - t * 5.7);
    float fine = 0.0;
    if (u_low_power < 0.5) {
        float fineCurve = sin(uv.x * 17.0 + 0.8) * 0.32;
        fine = sin(flowY * 79.0 + fineCurve - t * 11.0);
    }
    vec2 offset = vec2((broad * 0.0028 + fine * 0.0012) * u_ripple_strength,
                       0.0);
    vec4 water = texture2D(u_texture, clamp(uv + offset, 0.0, 1.0));

    float light = 0.0;
    if (u_low_power < 0.5) {
        float bandCurve = sin(uv.x * 9.0) * 0.08;
        float sparkleCurve = sin(uv.x * 19.0 + 1.4) * 0.06;
        float band = pow(max(0.0, sin((flowY * 14.0 + bandCurve - t) * 6.28318)), 12.0);
        float sparkle = pow(max(0.0, sin((flowY * 67.0 + sparkleCurve - t * 2.2) * 6.28318)), 22.0);
        light = (band * 0.045 + sparkle * 0.085) * u_highlight_strength;
    }

    vec3 cool = vec3(0.055, 0.105, 0.15) * u_darkness;
    vec3 warm = vec3(0.11, 0.055, 0.0) * u_warmth;
    water.rgb = clamp(water.rgb - cool + warm + light, 0.0, 1.0);
    water.a = original.a;
    if (u_mask_preview > 0.5) {
        water.rgb = mix(water.rgb, vec3(0.05, 0.85, 1.0), 0.76);
    }
    gl_FragColor = water;
}

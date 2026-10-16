// The new wallpaper spilling over the old one: a blob whose edge is domain-warped
// noise, so it bleeds out in lobes and tendrils instead of a clean circle.
// Rebuild after editing:  /usr/lib/qt6/bin/qsb --qt6 -o spill.frag.qsb spill.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0..1
    float aspect;     // width / height
    float seed;
    float reach;      // blob radius at progress = 1 (covers every corner)
    vec2 origin;      // in uv
};
layout(binding = 1) uniform sampler2D src;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(17.1, 9.7);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - origin) * vec2(aspect, 1.0);
    float d = length(p);

    // the edge: warped noise that drifts as it spreads
    vec2 s = vec2(seed, seed * 1.7);
    float drift = progress * 0.8;
    vec2 q = p * 1.6 + s + vec2(fbm(p * 1.3 + s + drift), fbm(p * 1.3 + s + 4.7 - drift)) * 1.4;
    float wob = fbm(q * 2.2) - 0.5;

    float r = progress * reach;
    // lobes grow in as it spreads and calm down at the end so the last pockets close cleanly
    float amp = 0.55 * (0.35 + 0.65 * smoothstep(0.0, 0.25, r)) * (1.0 - 0.6 * smoothstep(0.55, 1.0, progress));
    float edge = d + wob * amp;
    float feather = 0.01 + 0.012 * progress;
    float inside = 1.0 - smoothstep(r - feather, r, edge);

    // a faint wet rim just inside the edge, and a soft shadow just outside it
    float rim = smoothstep(r - 0.06, r - feather, edge) * inside;
    float shade = (1.0 - smoothstep(r, r + 0.05, edge)) * (1.0 - inside);

    vec4 c = texture(src, uv);
    c.rgb *= 1.0 - 0.18 * rim;
    vec4 col = c * inside + vec4(0.0, 0.0, 0.0, 0.22 * shade);
    fragColor = col * qt_Opacity;
}

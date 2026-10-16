#version 320 es
precision mediump float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 color = texture(tex, v_texcoord);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(gray);

    // Warm tint: boost red, keep some green, kill blue
    vec3 warm = vec3(grayscale.r * 1.2, grayscale.g * 0.9, grayscale.b * 0.3);

    fragColor = vec4(warm, color.a);
}

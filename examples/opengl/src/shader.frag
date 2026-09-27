#version 410 core

layout(location = 0) in vec3 color;

void main() {
    gl_FragColor = vec4(color, 1.0);
}

#version 410 core

layout(location = 0) in vec3 vertex;
layout(location = 1) in vec3 color;

layout(location = 0) out vec3 out_color;

void main() {
    gl_Position = vec4(vertex, 1.0);
    out_color = color;
}

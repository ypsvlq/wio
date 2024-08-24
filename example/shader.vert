attribute vec4 vertex;
varying vec3 color;

void main() {
    gl_Position = vertex;
    color = vertex.xyz + 0.5;
}

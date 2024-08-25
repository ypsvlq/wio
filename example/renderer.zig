const std = @import("std");
const wio = @import("wio");
const gl = @import("gl.zig");

const vertices = [_]f32{
    -0.5, -0.5,
    0.5,  -0.5,
    0.0,  0.5,
};

var loaded: bool = false;

pub fn init() void {
    gl.load(wio.glGetProcAddress) catch return;
    loaded = true;

    gl.clearColor(0, 0, 0, 1);

    const vs = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vs, 1, &[_][*:0]const u8{@embedFile("shader.vert")}, null);
    gl.compileShader(vs);

    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fs, 1, &[_][*:0]const u8{@embedFile("shader.frag")}, null);
    gl.compileShader(fs);

    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);

    gl.useProgram(program);

    var buffer: u32 = undefined;
    gl.genBuffers(1, &buffer);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);

    const index: u32 = @bitCast(gl.getAttribLocation(program, "vertex"));
    gl.enableVertexAttribArray(index);
    gl.vertexAttribPointer(index, 2, gl.FLOAT, gl.FALSE, 0, null);
}

pub fn resize(size: wio.Size) void {
    if (!loaded) return;
    gl.viewport(0, 0, size.width, size.height);
}

pub fn draw() void {
    if (!loaded) return;
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
}

const std = @import("std");
const wio = @import("wio");
const gl = @import("gl");

const gl_options: wio.GlOptions = .{
    .major_version = 4,
    .minor_version = 1,
    .profile = .core,
};

pub fn main(init: std.process.Init) !void {
    try wio.init(.{
        .allocator = init.gpa,
        .io = init.io,
        .eventFn = wio.EventQueue.eventFn,
    });
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    var window = try wio.Window.create(.{
        .event_fn_data = &events,
        .title = "OpenGL",
        .scale = 1,
        .gl_options = gl_options,
    });
    defer window.destroy();

    var context = try window.glCreateContext(.{ .options = gl_options });
    defer context.destroy();

    window.glMakeContextCurrent(context);
    window.glSwapInterval(1);
    try gl.load(wio.glGetProcAddress);

    var renderer = Renderer.init();
    defer renderer.deinit();

    while (true) {
        wio.update();
        while (events.pop()) |event| {
            switch (event) {
                .close => return,
                .size_physical => |size| gl.viewport(0, 0, size.width, size.height),
                else => {},
            }
        }

        gl.clearColor(0, 0, 0, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
        renderer.draw();
        window.glSwapBuffers();
    }
}

const Renderer = struct {
    program: u32,
    vao: u32,
    vbos: [2]u32,

    const vertex_location = 0;
    const color_location = 1;

    fn init() Renderer {
        const vs = gl.createShader(gl.VERTEX_SHADER);
        defer gl.deleteShader(vs);
        gl.shaderSource(vs, 1, &[1][*:0]const u8{@embedFile("shader.vert")}, null);
        gl.compileShader(vs);

        const fs = gl.createShader(gl.FRAGMENT_SHADER);
        defer gl.deleteShader(fs);
        gl.shaderSource(fs, 1, &[1][*:0]const u8{@embedFile("shader.frag")}, null);
        gl.compileShader(fs);

        const program = gl.createProgram();
        gl.attachShader(program, vs);
        defer gl.detachShader(program, vs);
        gl.attachShader(program, fs);
        defer gl.detachShader(program, fs);
        gl.linkProgram(program);

        var vao: u32 = undefined;
        gl.genVertexArrays(1, &vao);
        gl.bindVertexArray(vao);

        var vbos: [2]u32 = undefined;
        gl.genBuffers(2, &vbos);

        gl.bindBuffer(gl.ARRAY_BUFFER, vbos[vertex_location]);
        gl.bufferData(gl.ARRAY_BUFFER, 9 * @sizeOf(f32), &[9]f32{
            0,    0.5,  0,
            0.5,  -0.5, 0,
            -0.5, -0.5, 0,
        }, gl.STATIC_DRAW);
        gl.vertexAttribPointer(vertex_location, 3, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(vertex_location);

        gl.bindBuffer(gl.ARRAY_BUFFER, vbos[color_location]);
        gl.bufferData(gl.ARRAY_BUFFER, 9 * @sizeOf(f32), &[9]f32{
            1,   0,   0.5,
            0.5, 1,   0,
            0,   0.5, 1,
        }, gl.STATIC_DRAW);
        gl.vertexAttribPointer(color_location, 3, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(color_location);

        return .{
            .program = program,
            .vao = vao,
            .vbos = vbos,
        };
    }

    fn deinit(self: Renderer) void {
        gl.deleteBuffers(self.vbos.len, &self.vbos);
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteProgram(self.program);
    }

    fn draw(self: Renderer) void {
        gl.useProgram(self.program);
        gl.bindVertexArray(self.vao);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
};

const std = @import("std");
const builtin = @import("builtin");
const APIENTRY = if (builtin.os.tag == .windows) std.builtin.CallingConvention.winapi else std.builtin.CallingConvention.c;
pub const Enum = u32;
pub const Boolean = u8;
pub const Bitfield = u32;
pub const SizeI = i32;
pub const COLOR_BUFFER_BIT = 0x00004000;
pub const FALSE = 0;
pub const TRIANGLES = 0x0004;
pub const ARRAY_BUFFER = 0x8892;
pub const STATIC_DRAW = 0x88E4;
pub const FLOAT = 0x1406;
pub const FRAGMENT_SHADER = 0x8B30;
pub const VERTEX_SHADER = 0x8B31;
pub var attachShader: *const fn (program: u32, shader: u32) callconv(APIENTRY) void = undefined;
pub var bindBuffer: *const fn (target: Enum, buffer: u32) callconv(APIENTRY) void = undefined;
pub var bufferData: *const fn (target: Enum, size: isize, data: ?*const anyopaque, usage: Enum) callconv(APIENTRY) void = undefined;
pub var clear: *const fn (mask: Bitfield) callconv(APIENTRY) void = undefined;
pub var clearColor: *const fn (red: f32, green: f32, blue: f32, alpha: f32) callconv(APIENTRY) void = undefined;
pub var compileShader: *const fn (shader: u32) callconv(APIENTRY) void = undefined;
pub var createProgram: *const fn () callconv(APIENTRY) u32 = undefined;
pub var createShader: *const fn (type: Enum) callconv(APIENTRY) u32 = undefined;
pub var drawArrays: *const fn (mode: Enum, first: i32, count: SizeI) callconv(APIENTRY) void = undefined;
pub var enableVertexAttribArray: *const fn (index: u32) callconv(APIENTRY) void = undefined;
pub var genBuffers: *const fn (n: SizeI, buffers: [*c]u32) callconv(APIENTRY) void = undefined;
pub var getAttribLocation: *const fn (program: u32, name: [*c]const u8) callconv(APIENTRY) i32 = undefined;
pub var linkProgram: *const fn (program: u32) callconv(APIENTRY) void = undefined;
pub var shaderSource: *const fn (shader: u32, count: SizeI, string: [*c]const [*c]const u8, length: [*c]const i32) callconv(APIENTRY) void = undefined;
pub var useProgram: *const fn (program: u32) callconv(APIENTRY) void = undefined;
pub var vertexAttribPointer: *const fn (index: u32, size: i32, type: Enum, normalized: Boolean, stride: SizeI, pointer: ?*const anyopaque) callconv(APIENTRY) void = undefined;
pub var viewport: *const fn (x: i32, y: i32, width: SizeI, height: SizeI) callconv(APIENTRY) void = undefined;
pub fn load(getProcAddress: anytype) !void {
    if (builtin.cpu.arch.isWasm()) {
        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
            switch (@typeInfo(@TypeOf(@field(@This(), decl.name)))) {
                .pointer => |info| @field(@This(), decl.name) = @extern(*const info.child, .{ .name = decl.name, .library_name = "gl" }),
                else => {},
            }
        }
    } else {
        attachShader = @ptrCast(getProcAddress("glAttachShader") orelse return error.RequiredFunctionMissing);
        bindBuffer = @ptrCast(getProcAddress("glBindBuffer") orelse return error.RequiredFunctionMissing);
        bufferData = @ptrCast(getProcAddress("glBufferData") orelse return error.RequiredFunctionMissing);
        clear = @ptrCast(getProcAddress("glClear") orelse return error.RequiredFunctionMissing);
        clearColor = @ptrCast(getProcAddress("glClearColor") orelse return error.RequiredFunctionMissing);
        compileShader = @ptrCast(getProcAddress("glCompileShader") orelse return error.RequiredFunctionMissing);
        createProgram = @ptrCast(getProcAddress("glCreateProgram") orelse return error.RequiredFunctionMissing);
        createShader = @ptrCast(getProcAddress("glCreateShader") orelse return error.RequiredFunctionMissing);
        drawArrays = @ptrCast(getProcAddress("glDrawArrays") orelse return error.RequiredFunctionMissing);
        enableVertexAttribArray = @ptrCast(getProcAddress("glEnableVertexAttribArray") orelse return error.RequiredFunctionMissing);
        genBuffers = @ptrCast(getProcAddress("glGenBuffers") orelse return error.RequiredFunctionMissing);
        getAttribLocation = @ptrCast(getProcAddress("glGetAttribLocation") orelse return error.RequiredFunctionMissing);
        linkProgram = @ptrCast(getProcAddress("glLinkProgram") orelse return error.RequiredFunctionMissing);
        shaderSource = @ptrCast(getProcAddress("glShaderSource") orelse return error.RequiredFunctionMissing);
        useProgram = @ptrCast(getProcAddress("glUseProgram") orelse return error.RequiredFunctionMissing);
        vertexAttribPointer = @ptrCast(getProcAddress("glVertexAttribPointer") orelse return error.RequiredFunctionMissing);
        viewport = @ptrCast(getProcAddress("glViewport") orelse return error.RequiredFunctionMissing);
    }
}

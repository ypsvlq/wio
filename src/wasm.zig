const std = @import("std");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

const js = struct {
    pub extern "wio" fn write([*]const u8, usize) void;
    pub extern "wio" fn flush() void;
    pub extern "wio" fn shift() u32;
    pub extern "wio" fn shiftFloat() f32;
    pub extern "wio" fn setCursor(u8) void;
    pub extern "wio" fn setCursorMode(u8) void;
    pub extern "wio" fn createContext() void;
    pub extern "wio" fn getJoysticks() u32;
    pub extern "wio" fn getJoystickIdLen(u32) u32;
    pub extern "wio" fn getJoystickId(u32, [*]u8) void;
    pub extern "wio" fn openJoystick(u32, *[2]u32) bool;
    pub extern "wio" fn getJoystickState(u32, [*]u16, usize, [*]bool, usize) bool;
    pub extern "wio" fn messageBox([*]const u8, usize) void;
    pub extern "wio" fn setClipboardText([*]const u8, usize) void;
};

fn writeFn(_: void, bytes: []const u8) !usize {
    js.write(bytes.ptr, bytes.len);
    return bytes.len;
}

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const writer = std.io.GenericWriter(void, error{}, writeFn){ .context = {} };
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    js.flush();
}

pub fn init(_: wio.InitOptions) !void {}

pub fn deinit() void {}

var loop: *const fn () anyerror!bool = undefined;

pub fn run(func: fn () anyerror!bool, _: wio.RunOptions) !void {
    loop = func;
}

export fn wioLoop() bool {
    return loop() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
}

pub fn createWindow(options: wio.CreateWindowOptions) !@This() {
    var self = @This(){};
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);
    return self;
}

pub fn destroy(_: *@This()) void {}

pub fn getEvent(_: *@This()) ?wio.Event {
    const event: wio.EventType = @enumFromInt(js.shift());
    return switch (event) {
        .close => null, // never sent, EventType 0 is reused to indicate empty queue
        .create => .create,
        .focused => .focused,
        .unfocused => .unfocused,
        .size => .{ .size = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .framebuffer => .{ .framebuffer = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .scale => .{ .scale = js.shiftFloat() },
        .char => .{ .char = @intCast(js.shift()) },
        .button_press => .{ .button_press = @enumFromInt(js.shift()) },
        .button_release => .{ .button_release = @enumFromInt(js.shift()) },
        .mouse => .{ .mouse = .{ .x = @intCast(js.shift()), .y = @intCast(js.shift()) } },
        .scroll_vertical => .{ .scroll_vertical = js.shiftFloat() },
        .scroll_horizontal => .{ .scroll_horizontal = js.shiftFloat() },
        .joystick => .joystick,
        else => unreachable,
    };
}

pub fn setTitle(_: *@This(), _: []const u8) void {}

pub fn setSize(_: *@This(), _: wio.Size) void {}

pub fn setMaximized(_: *@This(), _: bool) void {}

pub fn setCursor(_: *@This(), shape: wio.Cursor) void {
    js.setCursor(@intFromEnum(shape));
}

pub fn setCursorMode(_: *@This(), mode: wio.CursorMode) void {
    js.setCursorMode(@intFromEnum(mode));
}

pub fn createContext(_: *@This(), _: wio.CreateContextOptions) !void {
    js.createContext();
}

pub fn makeContextCurrent(_: *@This()) void {}

pub fn swapBuffers(_: *@This()) void {}

pub fn swapInterval(_: *@This(), _: i32) void {}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    const count = js.getJoysticks();
    var list = try std.ArrayList(wio.JoystickInfo).initCapacity(allocator, count);
    errdefer {
        for (list.items) |info| {
            allocator.free(info.id);
            allocator.free(info.name);
        }
        list.deinit();
    }
    for (0..count) |index| {
        const len = js.getJoystickIdLen(index);
        if (len > 0) {
            const id = try std.fmt.allocPrint(allocator, "{}", .{index});
            const name = try allocator.alloc(u8, len);
            js.getJoystickId(index, name.ptr);
            list.appendAssumeCapacity(.{ .id = id, .name = name });
        }
    }
    return list.toOwnedSlice();
}

pub fn resolveJoystickId(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return allocator.dupe(u8, id);
}

pub fn openJoystick(id: []const u8) !?Joystick {
    const index = std.fmt.parseInt(u32, id, 10) catch return null;
    var lengths: [2]u32 = undefined;
    if (!js.openJoystick(index, &lengths)) return null;
    const axes = try wio.allocator.alloc(u16, lengths[0]);
    errdefer wio.allocator.free(axes);
    const buttons = try wio.allocator.alloc(bool, lengths[1]);
    errdefer wio.allocator.free(buttons);
    return .{ .index = index, .axes = axes, .buttons = buttons };
}

pub const Joystick = struct {
    index: u32,
    axes: []u16,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        wio.allocator.free(self.axes);
        wio.allocator.free(self.buttons);
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        if (!js.getJoystickState(self.index, self.axes.ptr, self.axes.len, self.buttons.ptr, self.buttons.len)) return null;
        return .{
            .axes = self.axes,
            .hats = &.{},
            .buttons = self.buttons,
        };
    }
};

pub fn messageBox(_: ?@This(), _: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    js.messageBox(message.ptr, message.len);
}

pub fn setClipboardText(text: []const u8) void {
    js.setClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(_: std.mem.Allocator) ?[]u8 {
    return null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return if (@hasDecl(gl, name)) @field(gl, name) else null;
}

const gl = struct {
    extern "wio" fn glActiveTexture(u32) void;
    extern "wio" fn glAttachShader(u32, u32) void;
    extern "wio" fn glBindAttribLocation(u32, u32, [*c]const u8) void;
    extern "wio" fn glBindBuffer(u32, u32) void;
    extern "wio" fn glBindFramebuffer(u32, u32) void;
    extern "wio" fn glBindRenderbuffer(u32, u32) void;
    extern "wio" fn glBindTexture(u32, u32) void;
    extern "wio" fn glBlendColor(f32, f32, f32, f32) void;
    extern "wio" fn glBlendEquation(u32) void;
    extern "wio" fn glBlendEquationSeparate(u32, u32) void;
    extern "wio" fn glBlendFunc(u32, u32) void;
    extern "wio" fn glBlendFuncSeparate(u32, u32, u32, u32) void;
    extern "wio" fn glBufferData(u32, isize, ?*const anyopaque, u32) void;
    extern "wio" fn glBufferSubData(u32, isize, isize, ?*const anyopaque) void;
    extern "wio" fn glCheckFramebufferStatus(u32) u32;
    extern "wio" fn glClear(u32) void;
    extern "wio" fn glClearColor(f32, f32, f32, f32) void;
    extern "wio" fn glClearDepthf(f32) void;
    extern "wio" fn glClearStencil(i32) void;
    extern "wio" fn glColorMask(u8, u8, u8, u8) void;
    extern "wio" fn glCompileShader(u32) void;
    extern "wio" fn glCompressedTexImage2D(u32, i32, u32, i32, i32, i32, i32, ?*const anyopaque) void;
    extern "wio" fn glCompressedTexSubImage2D(u32, i32, i32, i32, i32, i32, u32, i32, ?*const anyopaque) void;
    extern "wio" fn glCopyTexImage2D(u32, i32, u32, i32, i32, i32, i32, i32) void;
    extern "wio" fn glCopyTexSubImage2D(u32, i32, i32, i32, i32, i32, i32, i32) void;
    extern "wio" fn glCreateProgram() u32;
    extern "wio" fn glCreateShader(u32) u32;
    extern "wio" fn glCullFace(u32) void;
    extern "wio" fn glDeleteBuffers(i32, [*c]const u32) void;
    extern "wio" fn glDeleteFramebuffers(i32, [*c]const u32) void;
    extern "wio" fn glDeleteProgram(u32) void;
    extern "wio" fn glDeleteRenderbuffers(i32, [*c]const u32) void;
    extern "wio" fn glDeleteShader(u32) void;
    extern "wio" fn glDeleteTextures(i32, [*c]const u32) void;
    extern "wio" fn glDepthFunc(u32) void;
    extern "wio" fn glDepthMask(u8) void;
    extern "wio" fn glDepthRangef(f32, f32) void;
    extern "wio" fn glDetachShader(u32, u32) void;
    extern "wio" fn glDisable(u32) void;
    extern "wio" fn glDisableVertexAttribArray(u32) void;
    extern "wio" fn glDrawArrays(u32, i32, i32) void;
    extern "wio" fn glDrawElements(u32, i32, u32, ?*const anyopaque) void;
    extern "wio" fn glEnable(u32) void;
    extern "wio" fn glEnableVertexAttribArray(u32) void;
    extern "wio" fn glFinish() void;
    extern "wio" fn glFlush() void;
    extern "wio" fn glFramebufferRenderbuffer(u32, u32, u32, u32) void;
    extern "wio" fn glFramebufferTexture2D(u32, u32, u32, u32, i32) void;
    extern "wio" fn glFrontFace(u32) void;
    extern "wio" fn glGenBuffers(i32, [*c]u32) void;
    extern "wio" fn glGenerateMipmap(u32) void;
    extern "wio" fn glGenFramebuffers(i32, [*c]u32) void;
    extern "wio" fn glGenRenderbuffers(i32, [*c]u32) void;
    extern "wio" fn glGenTextures(i32, [*c]u32) void;
    extern "wio" fn glGetActiveAttrib(u32, u32, i32, [*c]i32, [*c]i32, [*c]u32, [*c]u8) void;
    extern "wio" fn glGetActiveUniform(u32, u32, i32, [*c]i32, [*c]i32, [*c]u32, [*c]u8) void;
    extern "wio" fn glGetAttachedShaders(u32, i32, [*c]i32, [*c]u32) void;
    extern "wio" fn glGetAttribLocation(u32, [*c]const u8) i32;
    extern "wio" fn glGetBooleanv(u32, [*c]u8) void;
    extern "wio" fn glGetBufferParameteriv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetError() u32;
    extern "wio" fn glGetFloatv(u32, [*c]f32) void;
    extern "wio" fn glGetFramebufferAttachmentParameteriv(u32, u32, u32, [*c]i32) void;
    extern "wio" fn glGetIntegerv(u32, [*c]i32) void;
    extern "wio" fn glGetProgramiv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetProgramInfoLog(u32, i32, [*c]i32, [*c]u8) void;
    extern "wio" fn glGetRenderbufferParameteriv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetShaderiv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetShaderInfoLog(u32, i32, [*c]i32, [*c]u8) void;
    extern "wio" fn glGetShaderPrecisionFormat(u32, u32, [*c]i32, [*c]i32) void;
    extern "wio" fn glGetShaderSource(u32, i32, [*c]i32, [*c]u8) void;
    extern "wio" fn glGetString(u32) u8;
    extern "wio" fn glGetTexParameterfv(u32, u32, [*c]f32) void;
    extern "wio" fn glGetTexParameteriv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetUniformfv(u32, i32, [*c]f32) void;
    extern "wio" fn glGetUniformiv(u32, i32, [*c]i32) void;
    extern "wio" fn glGetUniformLocation(u32, [*c]const u8) i32;
    extern "wio" fn glGetVertexAttribfv(u32, u32, [*c]f32) void;
    extern "wio" fn glGetVertexAttribiv(u32, u32, [*c]i32) void;
    extern "wio" fn glGetVertexAttribPointerv(u32, u32, ?*?*anyopaque) void;
    extern "wio" fn glHint(u32, u32) void;
    extern "wio" fn glIsBuffer(u32) u8;
    extern "wio" fn glIsEnabled(u32) u8;
    extern "wio" fn glIsFramebuffer(u32) u8;
    extern "wio" fn glIsProgram(u32) u8;
    extern "wio" fn glIsRenderbuffer(u32) u8;
    extern "wio" fn glIsShader(u32) u8;
    extern "wio" fn glIsTexture(u32) u8;
    extern "wio" fn glLineWidth(f32) void;
    extern "wio" fn glLinkProgram(u32) void;
    extern "wio" fn glPixelStorei(u32, i32) void;
    extern "wio" fn glPolygonOffset(f32, f32) void;
    extern "wio" fn glReadPixels(i32, i32, i32, i32, u32, u32, ?*anyopaque) void;
    fn glReleaseShaderCompiler() void {}
    extern "wio" fn glRenderbufferStorage(u32, u32, i32, i32) void;
    extern "wio" fn glSampleCoverage(f32, u8) void;
    extern "wio" fn glScissor(i32, i32, i32, i32) void;
    fn glShaderBinary() void {}
    extern "wio" fn glShaderSource(u32, i32, [*c]const [*c]const u8, [*c]const i32) void;
    extern "wio" fn glStencilFunc(u32, i32, u32) void;
    extern "wio" fn glStencilFuncSeparate(u32, u32, i32, u32) void;
    extern "wio" fn glStencilMask(u32) void;
    extern "wio" fn glStencilMaskSeparate(u32, u32) void;
    extern "wio" fn glStencilOp(u32, u32, u32) void;
    extern "wio" fn glStencilOpSeparate(u32, u32, u32, u32) void;
    extern "wio" fn glTexImage2D(u32, i32, i32, i32, i32, i32, u32, u32, ?*const anyopaque) void;
    extern "wio" fn glTexParameterf(u32, u32, f32) void;
    fn glTexParameterfv() void {}
    extern "wio" fn glTexParameteri(u32, u32, i32) void;
    fn glTexParameteriv() void {}
    extern "wio" fn glTexSubImage2D(u32, i32, i32, i32, i32, i32, u32, u32, ?*const anyopaque) void;
    extern "wio" fn glUniform1f(i32, f32) void;
    extern "wio" fn glUniform1fv(i32, i32, [*c]const f32) void;
    extern "wio" fn glUniform1i(i32, i32) void;
    extern "wio" fn glUniform1iv(i32, i32, [*c]const i32) void;
    extern "wio" fn glUniform2f(i32, f32, f32) void;
    extern "wio" fn glUniform2fv(i32, i32, [*c]const f32) void;
    extern "wio" fn glUniform2i(i32, i32, i32) void;
    extern "wio" fn glUniform2iv(i32, i32, [*c]const i32) void;
    extern "wio" fn glUniform3f(i32, f32, f32, f32) void;
    extern "wio" fn glUniform3fv(i32, i32, [*c]const f32) void;
    extern "wio" fn glUniform3i(i32, i32, i32, i32) void;
    extern "wio" fn glUniform3iv(i32, i32, [*c]const i32) void;
    extern "wio" fn glUniform4f(i32, f32, f32, f32, f32) void;
    extern "wio" fn glUniform4fv(i32, i32, [*c]const f32) void;
    extern "wio" fn glUniform4i(i32, i32, i32, i32, i32) void;
    extern "wio" fn glUniform4iv(i32, i32, [*c]const i32) void;
    extern "wio" fn glUniformMatrix2fv(i32, i32, u8, [*c]const f32) void;
    extern "wio" fn glUniformMatrix3fv(i32, i32, u8, [*c]const f32) void;
    extern "wio" fn glUniformMatrix4fv(i32, i32, u8, [*c]const f32) void;
    extern "wio" fn glUseProgram(u32) void;
    extern "wio" fn glValidateProgram(u32) void;
    extern "wio" fn glVertexAttrib1f(u32, f32) void;
    extern "wio" fn glVertexAttrib1fv(u32, [*c]const f32) void;
    extern "wio" fn glVertexAttrib2f(u32, f32, f32) void;
    extern "wio" fn glVertexAttrib2fv(u32, [*c]const f32) void;
    extern "wio" fn glVertexAttrib3f(u32, f32, f32, f32) void;
    extern "wio" fn glVertexAttrib3fv(u32, [*c]const f32) void;
    extern "wio" fn glVertexAttrib4f(u32, f32, f32, f32, f32) void;
    extern "wio" fn glVertexAttrib4fv(u32, [*c]const f32) void;
    extern "wio" fn glVertexAttribPointer(u32, i32, u32, u8, i32, ?*const anyopaque) void;
    extern "wio" fn glViewport(i32, i32, i32, i32) void;
};

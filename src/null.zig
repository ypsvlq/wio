const std = @import("std");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

pub fn init(options: wio.InitOptions) !void {
    _ = options;
}

pub fn deinit() void {}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions) !void {
    _ = func;
    _ = options;
}

pub fn createWindow(self: *@This(), options: wio.CreateWindowOptions) !void {
    _ = self;
    _ = options;
}

pub fn destroy(self: *@This()) void {
    _ = self;
}

pub fn getEvent(self: *@This()) ?wio.Event {
    _ = self;
    return null;
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    _ = self;
    _ = title;
}

pub fn setSize(self: *@This(), size: wio.Size) void {
    _ = self;
    _ = size;
}

pub fn setDisplayMode(self: *@This(), mode: wio.DisplayMode) void {
    _ = self;
    _ = mode;
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    _ = self;
    _ = shape;
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    _ = self;
    _ = mode;
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = self;
}

pub fn swapBuffers(self: *@This()) void {
    _ = self;
}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    _ = allocator;
    return &.{};
}

pub fn openJoystick(id: []const u8) !?Joystick {
    _ = id;
    return null;
}

pub const Joystick = struct {
    pub fn close(self: *Joystick) void {
        _ = self;
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        _ = self;
        return null;
    }
};

pub fn messageBox(backend: ?*@This(), style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = backend;
    _ = style;
    _ = title;
    _ = message;
}

pub fn setClipboardText(text: []const u8) void {
    _ = text;
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    _ = allocator;
    return null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    _ = name;
    return null;
}

pub fn swapInterval(interval: i32) void {
    _ = interval;
}

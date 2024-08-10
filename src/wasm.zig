const std = @import("std");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

extern "wio" fn write([*]const u8, usize) void;
extern "wio" fn flush() void;
extern "wio" fn shift() u32;
extern "wio" fn shiftFloat() f32;
extern "wio" fn jsCursor(u8) void;
extern "wio" fn jsCursorMode(u8) void;
extern "wio" fn jsMessageBox([*]const u8, usize) void;
extern "wio" fn jsSetClipboard([*]const u8, usize) void;

fn writeFn(_: void, bytes: []const u8) !usize {
    write(bytes.ptr, bytes.len);
    return bytes.len;
}

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const writer = std.io.GenericWriter(void, error{}, writeFn){ .context = {} };
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    flush();
}

pub fn init(_: wio.InitOptions) !void {}

pub fn deinit() void {}

var loop: *const fn () anyerror!bool = undefined;

pub fn run(func: *const fn () anyerror!bool, _: wio.RunOptions) !void {
    loop = func;
}

export fn wioLoop() bool {
    return loop() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
}

pub fn createWindow(self: *@This(), options: wio.CreateWindowOptions) !void {
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);
}

pub fn destroy(_: *@This()) void {}

pub fn getEvent(_: *@This()) ?wio.Event {
    const event: wio.EventType = @enumFromInt(shift());
    switch (event) {
        .close => return null, // never sent, EventType 0 is reused to indicate empty queue
        .create => return .create,
        .scale => return .{ .scale = shiftFloat() },
        .char => return .{ .char = @intCast(shift()) },
        .mouse => return .{ .mouse = .{ .x = @intCast(shift()), .y = @intCast(shift()) } },
        inline .size, .maximized, .framebuffer => |tag| return @unionInit(wio.Event, @tagName(tag), .{ .width = @intCast(shift()), .height = @intCast(shift()) }),
        inline .button_press, .button_repeat, .button_release => |tag| return @unionInit(wio.Event, @tagName(tag), @enumFromInt(shift())),
        else => unreachable,
    }
}

pub fn setTitle(_: *@This(), _: []const u8) void {}

pub fn setSize(_: *@This(), _: wio.Size) void {}

pub fn setDisplayMode(_: *@This(), _: wio.DisplayMode) void {}

pub fn setCursor(_: *@This(), shape: wio.Cursor) void {
    jsCursor(@intFromEnum(shape));
}

pub fn setCursorMode(_: *@This(), mode: wio.CursorMode) void {
    jsCursorMode(@intFromEnum(mode));
}

pub fn makeContextCurrent(_: *@This()) void {}

pub fn swapBuffers(_: *@This()) void {}

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

pub fn messageBox(_: ?*@This(), _: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    jsMessageBox(message.ptr, message.len);
}

pub fn setClipboardText(text: []const u8) void {
    jsSetClipboard(text.ptr, text.len);
}

pub fn getClipboardText(_: std.mem.Allocator) ?[]u8 {
    return null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    _ = name;
    return null;
}

pub fn swapInterval(_: i32) void {}

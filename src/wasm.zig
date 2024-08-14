const std = @import("std");
const wio = @import("wio.zig");
const js = @import("wasm/js.zig");
const log = std.log.scoped(.wio);

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

pub fn run(func: *const fn () anyerror!bool, _: wio.RunOptions) !void {
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
    switch (event) {
        .close => return null, // never sent, EventType 0 is reused to indicate empty queue
        .create => return .create,
        .scale => return .{ .scale = js.shiftFloat() },
        .char => return .{ .char = @intCast(js.shift()) },
        .mouse => return .{ .mouse = .{ .x = @intCast(js.shift()), .y = @intCast(js.shift()) } },
        .joystick => return .joystick,
        inline .size, .maximized, .framebuffer => |tag| return @unionInit(wio.Event, @tagName(tag), .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) }),
        inline .button_press, .button_repeat, .button_release => |tag| return @unionInit(wio.Event, @tagName(tag), @enumFromInt(js.shift())),
        else => unreachable,
    }
}

pub fn setTitle(_: *@This(), _: []const u8) void {}

pub fn setSize(_: *@This(), _: wio.Size) void {}

pub fn setDisplayMode(_: *@This(), _: wio.DisplayMode) void {}

pub fn setCursor(_: *@This(), shape: wio.Cursor) void {
    js.setCursor(@intFromEnum(shape));
}

pub fn setCursorMode(_: *@This(), mode: wio.CursorMode) void {
    js.setCursorMode(@intFromEnum(mode));
}

pub fn makeContextCurrent(_: *@This()) void {}

pub fn swapBuffers(_: *@This()) void {}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    var list = try std.ArrayList(wio.JoystickInfo).initCapacity(allocator, js.getJoysticks());
    errdefer {
        for (list.items) |info| allocator.free(info.id);
        list.deinit();
    }
    for (0..js.getJoysticks()) |index| {
        const len = js.getJoystickIdLen(index);
        if (len > 0) {
            const prefix = if (index > 0) std.math.log10(index) + 2 else 2;
            const id = try allocator.alloc(u8, prefix + len);
            errdefer allocator.free(id);
            _ = try std.fmt.bufPrint(id, "{} ", .{index});
            const name = id[prefix..];
            js.getJoystickId(index, name.ptr);
            list.appendAssumeCapacity(.{ .id = id, .name = name });
        }
    }
    return list.toOwnedSlice();
}

pub fn freeJoystickList(allocator: std.mem.Allocator, items: []wio.JoystickInfo) void {
    for (items) |info| allocator.free(info.id);
    allocator.free(items);
}

pub fn openJoystick(id: []const u8) !?Joystick {
    const index = std.fmt.parseInt(u32, std.mem.sliceTo(id, ' '), 10) catch return null;
    if (!js.isJoystickConnected(index)) return null;
    var lengths: [2]u32 = undefined;
    js.openJoystick(index, &lengths);
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
        if (!js.isJoystickConnected(self.index)) return null;
        for (self.axes, 0..) |*axis, i| {
            const value = js.getJoystickAxis(self.index, i);
            axis.* = @intFromFloat((value + 1) * (0xFFFF.0 / 2.0));
        }
        for (self.buttons, 0..) |*button, i| {
            button.* = js.getJoystickButton(self.index, i);
        }
        return .{
            .axes = self.axes,
            .hats = &.{},
            .buttons = self.buttons,
        };
    }
};

pub fn messageBox(_: ?*@This(), _: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    js.messageBox(message.ptr, message.len);
}

pub fn setClipboardText(text: []const u8) void {
    js.setClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(_: std.mem.Allocator) ?[]u8 {
    return null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    _ = name;
    return null;
}

pub fn swapInterval(_: i32) void {}

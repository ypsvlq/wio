const std = @import("std");
const wio = @import("wio.zig");

const js = struct {
    pub extern "wio" fn shift() u32;
    pub extern "wio" fn shiftFloat() f32;
    pub extern "wio" fn setFullscreen(bool) void;
    pub extern "wio" fn setCursor(u8) void;
    pub extern "wio" fn setCursorMode(u8) void;
    pub extern "wio" fn getJoysticks() u32;
    pub extern "wio" fn getJoystickIdLen(u32) u32;
    pub extern "wio" fn getJoystickId(u32, [*]u8) void;
    pub extern "wio" fn openJoystick(u32, *[2]u32) bool;
    pub extern "wio" fn getJoystickState(u32, [*]u16, usize, [*]bool, usize) bool;
    pub extern "wio" fn messageBox([*]const u8, usize) void;
    pub extern "wio" fn setClipboardText([*]const u8, usize) void;
};

pub fn init(_: wio.InitOptions) !void {}

pub fn deinit() void {}

var loop: *const fn () anyerror!bool = undefined;

pub fn run(func: fn () anyerror!bool) !void {
    loop = func;
}

export fn wioLoop() bool {
    return loop() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
}

pub fn messageBox(_: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    js.messageBox(message.ptr, message.len);
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
        .focused => .focused,
        .unfocused => .unfocused,
        .size => .{ .size = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .framebuffer => .{ .framebuffer = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .scale => .{ .scale = js.shiftFloat() },
        .mode => .{ .mode = @enumFromInt(js.shift()) },
        .char => .{ .char = @intCast(js.shift()) },
        .button_press => .{ .button_press = @enumFromInt(js.shift()) },
        .button_repeat => .{ .button_repeat = @enumFromInt(js.shift()) },
        .button_release => .{ .button_release = @enumFromInt(js.shift()) },
        .mouse => .{ .mouse = .{ .x = @intCast(js.shift()), .y = @intCast(js.shift()) } },
        .mouse_relative => .{ .mouse_relative = .{ .x = @intCast(@as(i32, @bitCast(js.shift()))), .y = @intCast(@as(i32, @bitCast(js.shift()))) } },
        .scroll_vertical => .{ .scroll_vertical = js.shiftFloat() },
        .scroll_horizontal => .{ .scroll_horizontal = js.shiftFloat() },
        else => unreachable,
    };
}

pub fn setTitle(_: *@This(), _: []const u8) void {}

pub fn setMode(_: *@This(), mode: wio.WindowMode) void {
    js.setFullscreen(mode == .fullscreen);
}

pub fn setCursor(_: *@This(), shape: wio.Cursor) void {
    js.setCursor(@intFromEnum(shape));
}

pub fn setCursorMode(_: *@This(), mode: wio.CursorMode) void {
    js.setCursorMode(@intFromEnum(mode));
}

pub fn requestAttention(_: *@This()) void {}

pub fn setClipboardText(_: *@This(), text: []const u8) void {
    js.setClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(_: *@This(), _: std.mem.Allocator) ?[]u8 {
    return null;
}

pub fn createContext(_: *@This(), _: wio.CreateContextOptions) !void {}

pub fn makeContextCurrent(_: *@This()) void {}

pub fn swapBuffers(_: *@This()) void {}

pub fn swapInterval(_: *@This(), _: i32) void {}

pub fn glGetProcAddress(comptime _: [:0]const u8) ?*const anyopaque {
    return null;
}

pub const JoystickDeviceIterator = struct {
    index: u32 = 0,
    count: u32,

    pub fn init() JoystickDeviceIterator {
        return .{ .count = js.getJoysticks() };
    }

    pub fn deinit(_: *JoystickDeviceIterator) void {}

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.index < self.count) {
            const device = JoystickDevice{ .index = self.index };
            self.index += 1;
            return device;
        } else {
            return null;
        }
    }
};

pub const JoystickDevice = struct {
    index: u32,

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !Joystick {
        var lengths: [2]u32 = undefined;
        if (!js.openJoystick(self.index, &lengths)) return error.Unexpected;
        const axes = try wio.allocator.alloc(u16, lengths[0]);
        errdefer wio.allocator.free(axes);
        const buttons = try wio.allocator.alloc(bool, lengths[1]);
        errdefer wio.allocator.free(buttons);
        return .{ .index = self.index, .axes = axes, .buttons = buttons };
    }

    pub fn getId(_: JoystickDevice, _: std.mem.Allocator) !?[]u8 {
        return null;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        const len = js.getJoystickIdLen(self.index);
        const name = try allocator.alloc(u8, len);
        js.getJoystickId(self.index, name.ptr);
        return name;
    }
};

pub const Joystick = struct {
    index: u32,
    axes: []u16,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        wio.allocator.free(self.axes);
        wio.allocator.free(self.buttons);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        if (!js.getJoystickState(self.index, self.axes.ptr, self.axes.len, self.buttons.ptr, self.buttons.len)) return null;
        return .{ .axes = self.axes, .hats = &.{}, .buttons = self.buttons };
    }
};

pub const AudioDeviceIterator = struct {
    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        _ = mode;
        return .{};
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        _ = self;
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        _ = self;
        return null;
    }
};

pub const AudioDevice = struct {
    pub fn release(self: AudioDevice) void {
        _ = self;
    }

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        _ = self;
        _ = writeFn;
        _ = format;
        return error.Unexpected;
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !AudioInput {
        _ = self;
        _ = readFn;
        _ = format;
        return error.Unexpected;
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }
};

pub const AudioOutput = struct {
    pub fn close(self: *AudioOutput) void {
        _ = self;
    }
};

pub const AudioInput = struct {
    pub fn close(self: *AudioInput) void {
        _ = self;
    }
};

export fn wioJoystick(index: u32) void {
    if (wio.init_options.joystickConnectedFn) |callback| {
        callback(.{ .backend = .{ .index = index } });
    }
}

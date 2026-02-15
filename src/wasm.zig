const std = @import("std");
const build_options = @import("build_options");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");

const js = struct {
    extern "wio" fn shift(u32) u32;
    extern "wio" fn shiftFloat(u32) f32;
    extern "wio" fn messageBox([*]const u8, usize) void;
    extern "wio" fn createWindow() u32;
    extern "wio" fn enableTextInput(u32, u16, u16) void;
    extern "wio" fn disableTextInput(u32) void;
    extern "wio" fn setFullscreen(u32, bool) void;
    extern "wio" fn setCursor(u32, u8) void;
    extern "wio" fn setCursorMode(u32, u8) void;
    extern "wio" fn setSize(u32, u16, u16) void;
    extern "wio" fn setClipboardText([*]const u8, usize) void;
    extern "wio" fn getJoystickCount() u32;
    extern "wio" fn getJoystickIdLen(u32) u32;
    extern "wio" fn getJoystickId(u32, [*]u8) void;
    extern "wio" fn openJoystick(u32, *[2]u32) bool;
    extern "wio" fn getJoystickState(u32, [*]u16, usize, [*]bool, usize) bool;
};

const gl = struct {
    extern "gl" fn createContext(u32) void;
    extern "gl" fn makeContextCurrent(u32) void;
};

pub fn init() !void {}

pub fn deinit() void {}

var loop: *const fn () anyerror!bool = undefined;

pub fn run(func: fn () anyerror!bool) !void {
    loop = func;
}

pub fn wait() void {}

export fn wioLoop() bool {
    return loop() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
}

pub fn messageBox(_: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    js.messageBox(message.ptr, message.len);
}

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    const id = js.createWindow();
    if (options.mode == .fullscreen) js.setFullscreen(id, true);
    if (build_options.opengl and options.opengl != null) gl.createContext(id);
    return .{ .id = id };
}

pub const Window = struct {
    id: u32,

    pub fn destroy(_: *Window) void {}

    pub fn getEvent(self: *Window) ?wio.Event {
        const event: wio.EventType = @enumFromInt(js.shift(self.id));
        return switch (event) {
            .close => null, // never sent, EventType 0 is reused to indicate empty queue
            .focused => .focused,
            .unfocused => .unfocused,
            .visible => .visible,
            .draw => .draw,
            .size => .{ .size = .{ .width = @intCast(js.shift(self.id)), .height = @intCast(js.shift(self.id)) } },
            .framebuffer => .{ .framebuffer = .{ .width = @intCast(js.shift(self.id)), .height = @intCast(js.shift(self.id)) } },
            .scale => .{ .scale = js.shiftFloat(self.id) },
            .mode => .{ .mode = @enumFromInt(js.shift(self.id)) },
            .char => .{ .char = @intCast(js.shift(self.id)) },
            .preview_reset => .preview_reset,
            .preview_char => .{ .preview_char = @intCast(js.shift(self.id)) },
            .button_press => .{ .button_press = @enumFromInt(js.shift(self.id)) },
            .button_repeat => .{ .button_repeat = @enumFromInt(js.shift(self.id)) },
            .button_release => .{ .button_release = @enumFromInt(js.shift(self.id)) },
            .mouse => .{ .mouse = .{ .x = @intCast(js.shift(self.id)), .y = @intCast(js.shift(self.id)) } },
            .mouse_relative => .{ .mouse_relative = .{ .x = @intCast(@as(i32, @bitCast(js.shift(self.id)))), .y = @intCast(@as(i32, @bitCast(js.shift(self.id)))) } },
            .scroll_vertical => .{ .scroll_vertical = js.shiftFloat(self.id) },
            .scroll_horizontal => .{ .scroll_horizontal = js.shiftFloat(self.id) },
            else => unreachable,
        };
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        const x, const y = if (options.cursor) |cursor| .{ cursor.x, cursor.y } else .{ 0, 0 };
        js.enableTextInput(self.id, x, y);
    }

    pub fn disableTextInput(self: *Window) void {
        js.disableTextInput(self.id);
    }

    pub fn setTitle(_: *Window, _: []const u8) void {}

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        js.setFullscreen(self.id, mode == .fullscreen);
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        js.setSize(self.id, size.width, size.height);
    }

    pub fn setParent(_: *Window, _: usize) void {}

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        js.setCursor(self.id, @intFromEnum(shape));
    }

    pub fn setCursorMode(self: *Window, mode: wio.CursorMode) void {
        js.setCursorMode(self.id, @intFromEnum(mode));
    }

    pub fn requestAttention(_: *Window) void {}

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        js.setClipboardText(text.ptr, text.len);
    }

    pub fn getClipboardText(_: *Window, _: std.mem.Allocator) ?[]u8 {
        return null;
    }

    pub fn makeContextCurrent(self: *Window) void {
        gl.makeContextCurrent(self.id);
    }

    pub fn swapBuffers(_: *Window) void {}

    pub fn swapInterval(_: *Window, _: i32) void {}
};

pub fn glGetProcAddress(_: [:0]const u8) ?*const anyopaque {
    return null;
}

pub const JoystickDeviceIterator = struct {
    index: u32 = 0,
    count: u32,

    pub fn init() JoystickDeviceIterator {
        return .{ .count = js.getJoystickCount() };
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
        const axes = try internal.allocator.alloc(u16, lengths[0]);
        errdefer internal.allocator.free(axes);
        const buttons = try internal.allocator.alloc(bool, lengths[1]);
        errdefer internal.allocator.free(buttons);
        return .{ .index = self.index, .axes = axes, .buttons = buttons };
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        const len = js.getJoystickIdLen(self.index);
        if (len == 0) return error.Unexpected;
        const name = try allocator.alloc(u8, len);
        js.getJoystickId(self.index, name.ptr);
        return name;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        return self.getId(allocator);
    }
};

pub const Joystick = struct {
    index: u32,
    axes: []u16,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        internal.allocator.free(self.axes);
        internal.allocator.free(self.buttons);
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
    if (internal.init_options.joystickConnectedFn) |callback| {
        callback(.{ .backend = .{ .index = index } });
    }
}

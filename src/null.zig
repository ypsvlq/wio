const std = @import("std");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

pub fn init() !void {}

pub fn deinit() void {}

pub fn run(func: fn () anyerror!bool) !void {
    _ = func;
}

pub fn update() void {}

pub fn wait() void {}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = style;
    _ = title;
    _ = message;
}

pub fn createWindow(options: wio.CreateWindowOptions) !*Window {
    const self = try internal.allocator.create(Window);
    _ = options;
    return self;
}

pub const Window = struct {
    pub fn destroy(self: *Window) void {
        internal.allocator.destroy(self);
    }

    pub fn getEvent(self: *Window) ?wio.Event {
        _ = self;
        return null;
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        _ = self;
        _ = options;
    }

    pub fn disableTextInput(self: *Window) void {
        _ = self;
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        _ = self;
        _ = mode;
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        _ = self;
        _ = size;
    }

    pub fn setParent(self: *Window, parent: usize) void {
        _ = self;
        _ = parent;
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        _ = self;
        _ = shape;
    }

    pub fn setCursorMode(self: *Window, mode: wio.CursorMode) void {
        _ = self;
        _ = mode;
    }

    pub fn requestAttention(self: *Window) void {
        _ = self;
    }

    pub fn setClipboardText(self: *Window, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub fn getClipboardText(self: *Window, allocator: std.mem.Allocator) ?[]u8 {
        _ = self;
        _ = allocator;
        return null;
    }

    pub fn makeContextCurrent(self: *Window) void {
        _ = self;
    }

    pub fn swapBuffers(self: *Window) void {
        _ = self;
    }

    pub fn swapInterval(self: *Window, interval: i32) void {
        _ = self;
        _ = interval;
    }

    pub fn createSurface(self: *Window, instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
        _ = self;
        _ = instance;
        _ = allocator;
        _ = surface;
        return 0;
    }
};

pub fn glGetProcAddress(name: [:0]const u8) ?*const anyopaque {
    _ = name;
    return null;
}

pub fn vkGetInstanceProcAddr(instance: usize, name: [*:0]const u8) ?*const fn () void {
    _ = instance;
    _ = name;
    return null;
}

pub fn getVulkanExtensions() []const [*:0]const u8 {
    return &.{};
}

pub const JoystickDeviceIterator = struct {
    pub fn init() JoystickDeviceIterator {
        return .{};
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        _ = self;
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        _ = self;
        return null;
    }
};

pub const JoystickDevice = struct {
    pub fn release(self: JoystickDevice) void {
        _ = self;
    }

    pub fn open(self: JoystickDevice) !Joystick {
        _ = self;
        return error.Unexpected;
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }
};

pub const Joystick = struct {
    pub fn close(self: *Joystick) void {
        _ = self;
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        _ = self;
        return null;
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

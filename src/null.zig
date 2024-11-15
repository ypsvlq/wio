const std = @import("std");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

pub fn init(options: wio.InitOptions) !void {
    _ = options;
}

pub fn deinit() void {}

pub fn run(func: fn () anyerror!bool) !void {
    _ = func;
}

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    _ = options;
    return self;
}

pub fn destroy(self: *@This()) void {
    wio.allocator.destroy(self);
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

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
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

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    _ = self;
    _ = options;
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = self;
}

pub fn swapBuffers(self: *@This()) void {
    _ = self;
}

pub fn swapInterval(self: *@This(), interval: i32) void {
    _ = self;
    _ = interval;
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

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) !?[]u8 {
        _ = self;
        _ = allocator;
        return null;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return "";
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
    pub fn init(mode: wio.AudioDeviceIteratorMode) AudioDeviceIterator {
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

pub fn getChannelOrder() []wio.Channel {
    return &.{};
}

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

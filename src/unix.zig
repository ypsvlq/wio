const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const wio = @import("wio.zig");
pub const x11 = @import("unix/x11.zig");
pub const wayland = @import("unix/wayland.zig");
const joystick = switch (builtin.os.tag) {
    .linux => @import("unix/joystick/linux.zig"),
    else => @import("unix/joystick/null.zig"),
};
const audio = switch (builtin.os.tag) {
    else => @import("unix/audio/null.zig"),
};
const log = std.log.scoped(.wio);

pub var active: enum {
    x11,
    wayland,
} = undefined;

pub fn init(options: wio.InitOptions) !void {
    if (builtin.os.tag == .linux and builtin.output_mode == .Exe and builtin.link_mode == .static) @compileError("dynamic link required");

    if (options.joystick) try joystick.init();
    if (options.audio) try audio.init();

    comptime var enable_x11 = false;
    comptime var enable_wayland = false;
    comptime {
        var iter = std.mem.splitScalar(u8, build_options.unix_backends, ',');
        while (iter.next()) |name| {
            if (std.mem.eql(u8, name, "x11")) {
                enable_x11 = true;
            } else if (std.mem.eql(u8, name, "wayland")) {
                enable_wayland = true;
            } else {
                @compileError("unknown unix backend '" ++ name ++ "'");
            }
        }
    }

    var try_x11 = enable_x11;
    var try_wayland = enable_wayland;
    if (try_x11 and try_wayland) {
        if (std.c.getenv("XDG_SESSION_TYPE")) |value| {
            const session_type = std.mem.sliceTo(value, 0);
            if (std.mem.eql(u8, session_type, "x11")) {
                try_wayland = false;
            } else if (std.mem.eql(u8, session_type, "wayland")) {
                try_x11 = false;
            }
        }
    }

    if (try_wayland) {
        if (wayland.init(options)) {
            active = .wayland;
            return;
        } else |err| if (err != error.Unavailable) return err;
    }

    if (try_x11) {
        if (x11.init(options)) {
            active = .x11;
            return;
        } else |err| if (err != error.Unavailable) return err;
    }

    log.err("no backend found", .{});
    return error.Unexpected;
}

pub fn deinit() void {
    if (wio.init_options.audio) audio.deinit();
    if (wio.init_options.joystick) joystick.deinit();
    switch (active) {
        .x11 => return x11.deinit(),
        .wayland => return wayland.deinit(),
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        switch (active) {
            .x11 => x11.update(),
            .wayland => wayland.update(),
        }
        if (wio.init_options.joystick) joystick.update();
        if (wio.init_options.audio) audio.update();
    }
}

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    switch (active) {
        .x11 => return .{ .x11 = try x11.createWindow(options) },
        .wayland => return .{ .wayland = try wayland.createWindow(options) },
    }
}

pub const Window = union {
    x11: *x11,
    wayland: *wayland,

    pub fn destroy(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.destroy(),
            .wayland => self.wayland.destroy(),
        }
    }

    pub fn getEvent(self: *@This()) ?wio.Event {
        switch (active) {
            .x11 => return self.x11.getEvent(),
            .wayland => return self.wayland.getEvent(),
        }
    }

    pub fn setTitle(self: *@This(), title: []const u8) void {
        switch (active) {
            .x11 => self.x11.setTitle(title),
            .wayland => self.wayland.setTitle(title),
        }
    }

    pub fn setSize(self: *@This(), size: wio.Size) void {
        switch (active) {
            .x11 => self.x11.setSize(size),
            .wayland => self.wayland.setSize(size),
        }
    }

    pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
        switch (active) {
            .x11 => self.x11.setMode(mode),
            .wayland => self.wayland.setMode(mode),
        }
    }

    pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
        switch (active) {
            .x11 => self.x11.setCursor(shape),
            .wayland => self.wayland.setCursor(shape),
        }
    }

    pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
        switch (active) {
            .x11 => self.x11.setCursorMode(mode),
            .wayland => self.wayland.setCursorMode(mode),
        }
    }

    pub fn requestAttention(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.requestAttention(),
            .wayland => self.wayland.requestAttention(),
        }
    }

    pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
        switch (active) {
            .x11 => return self.x11.createContext(options),
            .wayland => return self.wayland.createContext(options),
        }
    }

    pub fn makeContextCurrent(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.makeContextCurrent(),
            .wayland => self.wayland.makeContextCurrent(),
        }
    }

    pub fn swapBuffers(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.swapBuffers(),
            .wayland => self.wayland.swapBuffers(),
        }
    }

    pub fn swapInterval(self: *@This(), interval: i32) void {
        switch (active) {
            .x11 => self.x11.swapInterval(interval),
            .wayland => self.wayland.swapInterval(interval),
        }
    }
};

pub const JoystickDeviceIterator = joystick.JoystickDeviceIterator;
pub const JoystickDevice = joystick.JoystickDevice;
pub const Joystick = joystick.Joystick;

pub const AudioDeviceIterator = audio.AudioDeviceIterator;
pub const AudioDevice = audio.AudioDevice;
pub const AudioOutput = audio.AudioOutput;
pub const AudioInput = audio.AudioInput;

pub fn messageBox(backend: ?Window, style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    switch (active) {
        .x11 => x11.messageBox(if (backend) |self| self.x11 else null, style, title, message),
        .wayland => wayland.messageBox(if (backend) |self| self.wayland else null, style, title, message),
    }
}

pub fn setClipboardText(text: []const u8) void {
    switch (active) {
        .x11 => x11.setClipboardText(text),
        .wayland => wayland.setClipboardText(text),
    }
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    switch (active) {
        .x11 => return x11.getClipboardText(allocator),
        .wayland => return wayland.getClipboardText(allocator),
    }
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    switch (active) {
        .x11 => return x11.glGetProcAddress(name),
        .wayland => return wayland.glGetProcAddress(name),
    }
}

const std = @import("std");
const wio = @import("wio.zig");
pub const x11 = @import("unix/x11.zig");
const log = std.log.scoped(.wio);

pub var active: enum {
    x11,
} = undefined;

pub fn init(options: wio.InitOptions) !void {
    if (x11.init(options)) {
        active = .x11;
    } else |err| switch (err) {
        error.Unavailable => {
            log.err("no backend found", .{});
            return error.Unexpected;
        },
        else => return err,
    }
}

pub usingnamespace switch (@import("builtin").os.tag) {
    .linux => @import("unix/joystick/linux.zig"),
    else => struct {
        pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
            return allocator.alloc(wio.JoystickInfo, 0);
        }

        pub fn resolveJoystickId(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
            return allocator.dupe(u8, id);
        }

        pub fn openJoystick(_: []const u8) !?Joystick {
            return null;
        }

        pub const Joystick = struct {
            pub fn close(_: *Joystick) void {}

            pub fn poll(_: *Joystick) !?wio.JoystickState {
                return null;
            }
        };
    },
};

pub fn deinit() void {
    switch (active) {
        .x11 => return x11.deinit(),
    }
}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions) !void {
    switch (active) {
        .x11 => return x11.run(func, options),
    }
}

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    switch (active) {
        .x11 => return .{ .x11 = try x11.createWindow(options) },
    }
}

pub const Window = union {
    x11: *x11,

    pub fn destroy(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.destroy(),
        }
    }

    pub fn getEvent(self: *@This()) ?wio.Event {
        switch (active) {
            .x11 => return self.x11.getEvent(),
        }
    }

    pub fn setTitle(self: *@This(), title: []const u8) void {
        switch (active) {
            .x11 => return self.x11.setTitle(title),
        }
    }

    pub fn setSize(self: *@This(), size: wio.Size) void {
        switch (active) {
            .x11 => return self.x11.setSize(size),
        }
    }

    pub fn setDisplayMode(self: *@This(), mode: wio.DisplayMode) void {
        switch (active) {
            .x11 => return self.x11.setDisplayMode(mode),
        }
    }

    pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
        switch (active) {
            .x11 => return self.x11.setCursor(shape),
        }
    }

    pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
        switch (active) {
            .x11 => return self.x11.setCursorMode(mode),
        }
    }

    pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
        switch (active) {
            .x11 => return self.x11.createContext(options),
        }
    }

    pub fn makeContextCurrent(self: *@This()) void {
        switch (active) {
            .x11 => return self.x11.makeContextCurrent(),
        }
    }

    pub fn swapBuffers(self: *@This()) void {
        switch (active) {
            .x11 => return self.x11.swapBuffers(),
        }
    }

    pub fn swapInterval(self: *@This(), interval: i32) void {
        switch (active) {
            .x11 => return self.x11.swapInterval(interval),
        }
    }
};

pub fn messageBox(backend: ?Window, style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    switch (active) {
        .x11 => x11.messageBox(if (backend) |self| self.x11 else null, style, title, message),
    }
}

pub fn setClipboardText(text: []const u8) void {
    switch (active) {
        .x11 => x11.setClipboardText(text),
    }
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    switch (active) {
        .x11 => return x11.getClipboardText(allocator),
    }
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    switch (active) {
        .x11 => return x11.glGetProcAddress(name),
    }
}

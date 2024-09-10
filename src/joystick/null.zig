const std = @import("std");
const wio = @import("../wio.zig");

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    return allocator.alloc(wio.JoystickInfo, 0);
}

pub fn resolveJoystickId(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return allocator.dupe(u8, id);
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

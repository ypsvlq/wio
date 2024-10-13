const std = @import("std");
const wio = @import("../../wio.zig");

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    return allocator.alloc(wio.JoystickInfo, 0);
}

pub fn freeJoysticks(allocator: std.mem.Allocator, list: []wio.JoystickInfo) void {
    allocator.free(list);
}

pub fn resolveJoystickId(_: []const u8) ?usize {
    return null;
}

pub fn openJoystick(_: usize) !Joystick {
    return error.Unavailable;
}

pub const Joystick = struct {
    pub fn close(_: *Joystick) void {}

    pub fn poll(_: *Joystick) !?wio.JoystickState {
        return null;
    }
};

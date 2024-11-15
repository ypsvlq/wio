const std = @import("std");
const wio = @import("../../wio.zig");

pub fn init() !void {}

pub fn deinit() void {}

pub fn update() void {}

pub const JoystickDeviceIterator = struct {
    pub fn init() JoystickDeviceIterator {
        return .{};
    }

    pub fn deinit(_: *JoystickDeviceIterator) void {}

    pub fn next(_: *JoystickDeviceIterator) ?JoystickDevice {
        return null;
    }
};

pub const JoystickDevice = struct {
    pub fn release(_: JoystickDevice) void {}

    pub fn open(_: JoystickDevice) !Joystick {
        return error.Unexpected;
    }

    pub fn getId(_: JoystickDevice, _: std.mem.Allocator) !?[]u8 {
        return null;
    }

    pub fn getName(_: JoystickDevice, _: std.mem.Allocator) ![]u8 {
        return "";
    }
};

pub const Joystick = struct {
    pub fn close(_: *Joystick) void {}

    pub fn poll(_: *Joystick) ?wio.JoystickState {
        return null;
    }
};

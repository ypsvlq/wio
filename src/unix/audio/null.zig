const std = @import("std");
const wio = @import("../../wio.zig");

pub fn init() !void {}

pub fn deinit() void {}

pub const AudioDeviceIterator = struct {
    pub fn init(_: wio.AudioDeviceIteratorMode) AudioDeviceIterator {
        return .{};
    }

    pub fn deinit(_: *AudioDeviceIterator) void {}

    pub fn next(_: *AudioDeviceIterator) ?AudioDevice {
        return null;
    }
};

pub const AudioDevice = struct {
    pub fn release(_: AudioDevice) void {}

    pub fn openOutput(_: AudioDevice, _: *const fn ([]f32) void, _: wio.AudioFormat) !AudioOutput {
        return error.Unexpected;
    }

    pub fn openInput(_: AudioDevice, _: *const fn ([]const f32) void, _: wio.AudioFormat) !AudioInput {
        return error.Unexpected;
    }

    pub fn getId(_: AudioDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }

    pub fn getName(_: AudioDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }
};

pub const AudioOutput = struct {
    pub fn close(_: *AudioOutput) void {}
};

pub const AudioInput = struct {
    pub fn close(_: *AudioInput) void {}
};

pub fn getChannelOrder() []wio.Channel {
    return &.{};
}

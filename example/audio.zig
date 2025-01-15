const std = @import("std");
const wio = @import("wio");
const main = @import("main.zig");
const log = std.log.scoped(.audio);

var maybe_output: ?wio.AudioOutput = null;
var maybe_input: ?wio.AudioInput = null;

pub fn defaultOutput(device: wio.AudioDevice) void {
    defer device.release();

    const id = device.getId(main.allocator) orelse "";
    defer main.allocator.free(id);
    const name = device.getName(main.allocator);
    defer main.allocator.free(name);
    log.info("output: {s} / {s}", .{ name, id });

    if (maybe_output) |*old| old.close();
    maybe_output = device.openOutput(write, .{ .sample_rate = 48000, .channels = .initMany(&.{ .FL, .FR }) });
}

pub fn defaultInput(device: wio.AudioDevice) void {
    defer device.release();

    const id = device.getId(main.allocator) orelse "";
    defer main.allocator.free(id);
    const name = device.getName(main.allocator);
    defer main.allocator.free(name);
    log.info("input: {s} / {s}", .{ name, id });

    if (maybe_input) |*old| old.close();
    maybe_input = device.openInput(read, .{ .sample_rate = 48000, .channels = .initOne(.FL) });
}

pub fn close() void {
    if (maybe_input) |*input| input.close();
    if (maybe_output) |*output| output.close();
}

pub var play = false;
var time: f32 = 0;

fn write(samples: []f32) void {
    if (play) {
        for (0..samples.len / 2) |i| {
            samples[i * 2] = 0.1 * @sin(2 * std.math.pi * 220 * time);
            samples[i * 2 + 1] = 0.1 * @sin(2 * std.math.pi * 440 * time);
            time += 1.0 / 48000.0;
        }
        time = @rem(time, 1); // prevent distortion from float inaccuracy
    } else {
        @memset(samples, 0);
    }
}

pub var record = false;
var amplitude: f32 = 0;
var count: usize = 0;

fn read(samples: []const f32) void {
    if (record) {
        for (samples) |sample| {
            amplitude = @max(amplitude, @abs(sample));
        }
        count += samples.len;
        if (count >= 48000) {
            log.info("amplitude {d}", .{amplitude});
            amplitude = 0;
            count = 0;
        }
    }
}

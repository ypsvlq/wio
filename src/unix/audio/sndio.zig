const std = @import("std");
const wio = @import("../../wio.zig");
const internal = @import("../../wio.internal.zig");
const c = @cImport(@cInclude("sndio.h"));

pub fn init() !void {
    if (internal.init_options.audioDefaultOutputFn) |callback| callback(.{ .backend = .{} });
    if (internal.init_options.audioDefaultInputFn) |callback| callback(.{ .backend = .{} });
}

pub fn deinit() void {}

pub fn update() void {}

pub const AudioDeviceIterator = struct {
    used: bool = false,

    pub fn init(_: wio.AudioDeviceType) AudioDeviceIterator {
        return .{};
    }

    pub fn deinit(_: *AudioDeviceIterator) void {}

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.used) return null;
        self.used = true;
        return .{};
    }
};

pub const AudioDevice = struct {
    pub fn release(_: AudioDevice) void {}

    pub fn openOutput(_: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !*AudioOutput {
        return open(.output, format, @ptrCast(writeFn));
    }

    pub fn openInput(_: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !*AudioInput {
        return open(.input, format, @ptrCast(readFn));
    }

    fn open(comptime mode: wio.AudioDeviceType, format: wio.AudioFormat, dataFn: *const fn () void) !*AudioSession {
        const handle = c.sio_open(c.SIO_DEVANY, if (mode == .output) c.SIO_PLAY else c.SIO_REC, 0) orelse return error.Unexpected;
        errdefer c.sio_close(handle);

        var param: c.sio_par = undefined;
        c.sio_initpar(&param);
        param.bits = 32;
        param.bps = 4;
        param.sig = 1;
        param.le = c.SIO_LE_NATIVE;
        (if (mode == .output) param.pchan else param.rchan) = format.channels;
        param.rate = format.sample_rate;

        if (c.sio_setpar(handle, &param) == 0) return error.Unexpected;
        if (c.sio_getpar(handle, &param) == 0) return error.Unexpected;
        if (c.sio_start(handle) == 0) return error.Unexpected;

        const buffer = try internal.allocator.alloc(f32, param.appbufsz * format.channels);
        errdefer internal.allocator.free(buffer);

        const result = try internal.allocator.create(AudioSession);
        errdefer internal.allocator.destroy(result);
        result.* = .{
            .handle = handle,
            .buffer = buffer,
            .dataFn = dataFn,
            .thread = undefined,
        };
        result.thread = try std.Thread.spawn(.{}, if (mode == .output) AudioSession.outputThread else AudioSession.inputThread, .{result});
        return result;
    }

    pub fn getId(_: AudioDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }

    pub fn getName(_: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, "sndio");
    }
};

const AudioSession = struct {
    handle: *c.sio_hdl,
    buffer: []f32,
    dataFn: *const fn () void,
    thread: std.Thread,
    stop: bool = false,

    pub fn close(self: *AudioSession) void {
        self.stop = true;
        self.thread.join();

        c.sio_close(self.handle);
        internal.allocator.free(self.buffer);
        internal.allocator.destroy(self);
    }

    fn outputThread(self: *AudioSession) void {
        const writeFn: *const fn ([]f32) void = @ptrCast(self.dataFn);
        while (!self.stop and c.sio_eof(self.handle) == 0) {
            writeFn(self.buffer);
            for (self.buffer) |*float| {
                const int: *i32 = @ptrCast(float);
                int.* = @intFromFloat(float.* * std.math.maxInt(i32));
            }
            _ = c.sio_write(self.handle, self.buffer.ptr, self.buffer.len * 4);
        }
    }

    fn inputThread(self: *AudioSession) void {
        const readFn: *const fn ([]const f32) void = @ptrCast(self.dataFn);
        while (!self.stop and c.sio_eof(self.handle) == 0) {
            const count = c.sio_read(self.handle, self.buffer.ptr, self.buffer.len * 4);
            const buffer = self.buffer[0 .. count / 4];
            for (buffer) |*float| {
                const int: *i32 = @ptrCast(float);
                float.* = @floatFromInt(int.*);
                float.* /= std.math.maxInt(i32);
            }
            readFn(buffer);
        }
    }
};

pub const AudioOutput = AudioSession;
pub const AudioInput = AudioSession;

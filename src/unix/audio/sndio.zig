const std = @import("std");
const build_options = @import("build_options");
const h = @import("c");
const wio = @import("../../wio.zig");
const internal = @import("../../wio.internal.zig");
const DynLib = @import("../DynLib.zig");

var imports: extern struct {
    sio_open: *const @TypeOf(h.sio_open),
    sio_close: *const @TypeOf(h.sio_close),
    sio_initpar: *const @TypeOf(h.sio_initpar),
    sio_setpar: *const @TypeOf(h.sio_setpar),
    sio_getpar: *const @TypeOf(h.sio_getpar),
    sio_start: *const @TypeOf(h.sio_start),
    sio_eof: *const @TypeOf(h.sio_eof),
    sio_write: *const @TypeOf(h.sio_write),
    sio_read: *const @TypeOf(h.sio_read),
} = undefined;
const c = if (build_options.system_integration) h else &imports;

var libsndio: DynLib = undefined;

pub fn init() !void {
    try DynLib.load(&imports, &.{.{ .handle = &libsndio, .name = "libsndio.so.7" }});

    if (internal.audioDefaultOutputFn) |callback| callback(internal.audio_default_output_fn_data, .{ .backend = .{} });
    if (internal.audioDefaultInputFn) |callback| callback(internal.audio_default_input_fn_data, .{ .backend = .{} });
}

pub fn deinit() void {
    libsndio.close();
}

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

    pub fn openOutput(_: AudioDevice, callback: wio.Callback([]f32), format: wio.AudioFormat) !*AudioOutput {
        return open(.output, format, .{ .write = callback });
    }

    pub fn openInput(_: AudioDevice, callback: wio.Callback([]const f32), format: wio.AudioFormat) !*AudioInput {
        return open(.input, format, .{ .read = callback });
    }

    fn open(comptime mode: wio.AudioDeviceType, format: wio.AudioFormat, callback: AudioSession.Callback) !*AudioSession {
        const handle = c.sio_open(h.SIO_DEVANY, if (mode == .output) h.SIO_PLAY else h.SIO_REC, 0) orelse return error.Unexpected;
        errdefer c.sio_close(handle);

        var param: h.sio_par = undefined;
        c.sio_initpar(&param);
        param.bits = 32;
        param.bps = 4;
        param.sig = 1;
        param.le = h.SIO_LE_NATIVE;
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
            .callback = callback,
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
    handle: *h.sio_hdl,
    buffer: []f32,
    callback: Callback,
    thread: std.Thread,
    stop: bool = false,

    const Callback = union {
        write: wio.Callback([]f32),
        read: wio.Callback([]const f32),
    };

    pub fn close(self: *AudioSession) void {
        self.stop = true;
        self.thread.join();

        c.sio_close(self.handle);
        internal.allocator.free(self.buffer);
        internal.allocator.destroy(self);
    }

    fn outputThread(self: *AudioSession) void {
        while (!self.stop and c.sio_eof(self.handle) == 0) {
            self.callback.write.call(self.buffer);
            for (self.buffer) |*float| {
                const int: *i32 = @ptrCast(float);
                int.* = @trunc(float.* * @as(f32, @floatFromInt(std.math.maxInt(i32))));
            }
            _ = c.sio_write(self.handle, self.buffer.ptr, self.buffer.len * 4);
        }
    }

    fn inputThread(self: *AudioSession) void {
        while (!self.stop and c.sio_eof(self.handle) == 0) {
            const count = c.sio_read(self.handle, self.buffer.ptr, self.buffer.len * 4);
            const buffer = self.buffer[0 .. count / 4];
            for (buffer) |*float| {
                const int: *i32 = @ptrCast(float);
                float.* = @floatFromInt(int.*);
                float.* /= @floatFromInt(std.math.maxInt(i32));
            }
            self.callback.read.call(self.buffer);
        }
    }
};

pub const AudioOutput = AudioSession;
pub const AudioInput = AudioSession;

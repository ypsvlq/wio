const std = @import("std");
const wio = @import("../../wio.zig");
const common = @import("../common.zig");
const h = @cImport(@cInclude("pulse/pulseaudio.h"));
const log = std.log.scoped(.wio);

var c: extern struct {
    pa_threaded_mainloop_new: *const @TypeOf(h.pa_threaded_mainloop_new),
    pa_threaded_mainloop_free: *const @TypeOf(h.pa_threaded_mainloop_free),
    pa_threaded_mainloop_start: *const @TypeOf(h.pa_threaded_mainloop_start),
    pa_threaded_mainloop_stop: *const @TypeOf(h.pa_threaded_mainloop_stop),
    pa_threaded_mainloop_get_api: *const @TypeOf(h.pa_threaded_mainloop_get_api),
    pa_threaded_mainloop_lock: *const @TypeOf(h.pa_threaded_mainloop_lock),
    pa_threaded_mainloop_unlock: *const @TypeOf(h.pa_threaded_mainloop_unlock),
    pa_threaded_mainloop_wait: *const @TypeOf(h.pa_threaded_mainloop_wait),
    pa_threaded_mainloop_signal: *const @TypeOf(h.pa_threaded_mainloop_signal),
    pa_threaded_mainloop_accept: *const @TypeOf(h.pa_threaded_mainloop_accept),
    pa_context_new: *const @TypeOf(h.pa_context_new),
    pa_context_unref: *const @TypeOf(h.pa_context_unref),
    pa_context_connect: *const @TypeOf(h.pa_context_connect),
    pa_context_disconnect: *const @TypeOf(h.pa_context_disconnect),
    pa_context_set_state_callback: *const @TypeOf(h.pa_context_set_state_callback),
    pa_context_get_state: *const @TypeOf(h.pa_context_get_state),
    pa_context_get_server_info: *const @TypeOf(h.pa_context_get_server_info),
    pa_context_get_sink_info_by_name: *const @TypeOf(h.pa_context_get_sink_info_by_name),
    pa_context_get_source_info_by_name: *const @TypeOf(h.pa_context_get_source_info_by_name),
    pa_context_get_sink_info_list: *const @TypeOf(h.pa_context_get_sink_info_list),
    pa_context_get_source_info_list: *const @TypeOf(h.pa_context_get_source_info_list),
    pa_operation_unref: *const @TypeOf(h.pa_operation_unref),
    pa_operation_get_state: *const @TypeOf(h.pa_operation_get_state),
    pa_channel_map_init_auto: *const @TypeOf(h.pa_channel_map_init_auto),
    pa_stream_new: *const @TypeOf(h.pa_stream_new),
    pa_stream_unref: *const @TypeOf(h.pa_stream_unref),
    pa_stream_connect_playback: *const @TypeOf(h.pa_stream_connect_playback),
    pa_stream_connect_record: *const @TypeOf(h.pa_stream_connect_record),
    pa_stream_disconnect: *const @TypeOf(h.pa_stream_disconnect),
    pa_stream_set_write_callback: *const @TypeOf(h.pa_stream_set_write_callback),
    pa_stream_set_read_callback: *const @TypeOf(h.pa_stream_set_read_callback),
    pa_stream_begin_write: *const @TypeOf(h.pa_stream_begin_write),
    pa_stream_write: *const @TypeOf(h.pa_stream_write),
    pa_stream_peek: *const @TypeOf(h.pa_stream_peek),
    pa_stream_drop: *const @TypeOf(h.pa_stream_drop),
} = undefined;

var libpulse: std.DynLib = undefined;
var loop: *h.pa_threaded_mainloop = undefined;
var context: *h.pa_context = undefined;

pub fn init() !void {
    try common.loadLibs(&c, &.{.{ .handle = &libpulse, .name = "libpulse.so.0" }});

    loop = c.pa_threaded_mainloop_new() orelse return error.Unexpected;
    errdefer c.pa_threaded_mainloop_free(loop);
    if (c.pa_threaded_mainloop_start(loop) < 0) return error.Unexpected;
    errdefer c.pa_threaded_mainloop_stop(loop);
    c.pa_threaded_mainloop_lock(loop);

    const api = c.pa_threaded_mainloop_get_api(loop);
    context = c.pa_context_new(api, null) orelse return error.Unexpected;
    errdefer c.pa_context_unref(context);
    if (c.pa_context_connect(context, null, h.PA_CONTEXT_NOFLAGS, null) < 0) return error.Unexpected;
    c.pa_context_set_state_callback(context, contextStateCallback, null);
    while (c.pa_context_get_state(context) != h.PA_CONTEXT_READY) c.pa_threaded_mainloop_wait(loop);

    if (wio.init_options.audioDefaultOutputFn != null or wio.init_options.audioDefaultInputFn != null) {
        var maybe_info: ?*const h.pa_server_info = null;
        const operation = c.pa_context_get_server_info(context, serverInfoCallback, @ptrCast(&maybe_info));
        defer c.pa_operation_unref(operation);
        while (c.pa_operation_get_state(operation) == h.PA_OPERATION_RUNNING and maybe_info == null) c.pa_threaded_mainloop_wait(loop);
        var sink: [:0]const u8 = "";
        var source: [:0]const u8 = "";
        if (maybe_info) |info| {
            if (wio.init_options.audioDefaultOutputFn != null) sink = wio.allocator.dupeZ(u8, std.mem.sliceTo(info.default_sink_name, 0)) catch "";
            if (wio.init_options.audioDefaultInputFn != null) source = wio.allocator.dupeZ(u8, std.mem.sliceTo(info.default_source_name, 0)) catch "";
        }
        c.pa_threaded_mainloop_accept(loop);
        c.pa_threaded_mainloop_unlock(loop);
        if (wio.init_options.audioDefaultOutputFn) |callback| if (sink.len > 0) callback(.{ .backend = .{ .id = sink, .type = .output } });
        if (wio.init_options.audioDefaultInputFn) |callback| if (source.len > 0) callback(.{ .backend = .{ .id = source, .type = .input } });
    } else {
        c.pa_threaded_mainloop_unlock(loop);
    }
}

pub fn deinit() void {
    c.pa_threaded_mainloop_lock(loop);
    c.pa_context_disconnect(context);
    c.pa_context_unref(context);
    c.pa_threaded_mainloop_unlock(loop);
    c.pa_threaded_mainloop_stop(loop);
    c.pa_threaded_mainloop_free(loop);
    libpulse.close();
}

pub fn update() void {}

pub const AudioDeviceIterator = struct {
    list: std.ArrayList(AudioDevice),
    index: usize = 0,

    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        var self = AudioDeviceIterator{ .list = .init(wio.allocator) };
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);
        const operation = if (mode == .output)
            c.pa_context_get_sink_info_list(context, sinkListCallback, &self.list)
        else
            c.pa_context_get_source_info_list(context, sourceListCallback, &self.list);
        defer c.pa_operation_unref(operation);
        while (c.pa_operation_get_state(operation) == h.PA_OPERATION_RUNNING) c.pa_threaded_mainloop_wait(loop);
        return self;
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        self.list.deinit();
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.index == self.list.items.len) return null;
        const device = self.list.items[self.index];
        self.index += 1;
        return device;
    }
};

pub const AudioDevice = struct {
    id: [:0]const u8,
    type: wio.AudioDeviceType,

    pub fn release(self: AudioDevice) void {
        wio.allocator.free(self.id);
    }

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);

        var map: h.pa_channel_map = undefined;
        _ = c.pa_channel_map_init_auto(&map, format.channels, h.PA_CHANNEL_MAP_DEFAULT) orelse return error.Unexpected;

        const stream = c.pa_stream_new(context, "", &.{ .format = h.PA_SAMPLE_FLOAT32, .rate = format.sample_rate, .channels = map.channels }, &map) orelse return error.Unexpected;
        errdefer c.pa_stream_unref(stream);

        c.pa_stream_set_write_callback(stream, AudioOutput.callback, @constCast(writeFn));

        const attr = h.pa_buffer_attr{
            .maxlength = std.math.maxInt(u32),
            .tlength = 1,
            .prebuf = std.math.maxInt(u32),
            .minreq = std.math.maxInt(u32),
            .fragsize = std.math.maxInt(u32),
        };
        if (c.pa_stream_connect_playback(stream, self.id, &attr, h.PA_STREAM_ADJUST_LATENCY, null, null) != 0) return error.Unexpected;

        return .{ .stream = stream };
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !AudioInput {
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);

        var map: h.pa_channel_map = undefined;
        _ = c.pa_channel_map_init_auto(&map, format.channels, h.PA_CHANNEL_MAP_DEFAULT) orelse return error.Unexpected;

        const stream = c.pa_stream_new(context, "", &.{ .format = h.PA_SAMPLE_FLOAT32, .rate = format.sample_rate, .channels = map.channels }, &map) orelse return error.Unexpected;
        errdefer c.pa_stream_unref(stream);
        c.pa_stream_set_read_callback(stream, AudioInput.callback, @constCast(readFn));

        const attr = h.pa_buffer_attr{
            .maxlength = std.math.maxInt(u32),
            .tlength = std.math.maxInt(u32),
            .prebuf = std.math.maxInt(u32),
            .minreq = std.math.maxInt(u32),
            .fragsize = 1,
        };
        if (c.pa_stream_connect_record(stream, self.id, &attr, h.PA_STREAM_ADJUST_LATENCY) != 0) return error.Unexpected;

        return .{ .stream = stream };
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.id);
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);

        var maybe_name: ?[*:0]const u8 = null;

        const operation = if (self.type == .output)
            c.pa_context_get_sink_info_by_name(context, self.id, sinkNameCallback, @ptrCast(&maybe_name))
        else
            c.pa_context_get_source_info_by_name(context, self.id, sourceNameCallback, @ptrCast(&maybe_name));
        defer c.pa_operation_unref(operation);
        while (c.pa_operation_get_state(operation) == h.PA_OPERATION_RUNNING and maybe_name == null) c.pa_threaded_mainloop_wait(loop);

        defer c.pa_threaded_mainloop_accept(loop);
        return if (maybe_name) |name| allocator.dupe(u8, std.mem.sliceTo(name, 0)) else "";
    }
};

fn openStream(format: wio.AudioFormat) !*h.pa_stream {
    var map = h.pa_channel_map{ .channels = 0, .map = undefined };
    return c.pa_stream_new(context, "", &.{ .format = h.PA_SAMPLE_FLOAT32LE, .rate = format.sample_rate, .channels = map.channels }, &map) orelse return error.Unexpected;
}

pub const AudioOutput = struct {
    stream: *h.pa_stream,

    pub fn close(self: *AudioOutput) void {
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);
        _ = c.pa_stream_disconnect(self.stream);
        c.pa_stream_unref(self.stream);
    }

    fn callback(stream: ?*h.pa_stream, _: usize, data: ?*anyopaque) callconv(.c) void {
        const writeFn: *const fn ([]f32) void = @alignCast(@ptrCast(data));
        var ptr: ?*anyopaque = undefined;
        var nbytes: usize = std.math.maxInt(usize);
        if (c.pa_stream_begin_write(stream, &ptr, &nbytes) == 0 and ptr != null) {
            const buffer: [*]f32 = @alignCast(@ptrCast(ptr));
            writeFn(buffer[0 .. nbytes / @sizeOf(f32)]);
            _ = c.pa_stream_write(stream, ptr, nbytes, null, 0, h.PA_SEEK_RELATIVE);
        }
    }
};

pub const AudioInput = struct {
    stream: *h.pa_stream,

    pub fn close(self: *AudioInput) void {
        c.pa_threaded_mainloop_lock(loop);
        defer c.pa_threaded_mainloop_unlock(loop);
        _ = c.pa_stream_disconnect(self.stream);
        c.pa_stream_unref(self.stream);
    }

    fn callback(stream: ?*h.pa_stream, _: usize, data: ?*anyopaque) callconv(.c) void {
        const readFn: *const fn ([]const f32) void = @alignCast(@ptrCast(data));
        var ptr: ?*const anyopaque = null;
        var nbytes: usize = 0;
        if (c.pa_stream_peek(stream, &ptr, &nbytes) == 0 and ptr != null) {
            const buffer: [*]const f32 = @alignCast(@ptrCast(ptr));
            readFn(buffer[0 .. nbytes / @sizeOf(f32)]);
        }
        if (nbytes != 0) _ = c.pa_stream_drop(stream);
    }
};

fn contextStateCallback(_: ?*h.pa_context, _: ?*anyopaque) callconv(.c) void {
    c.pa_threaded_mainloop_signal(loop, 0);
}

fn serverInfoCallback(_: ?*h.pa_context, info: ?*const h.pa_server_info, data: ?*anyopaque) callconv(.c) void {
    const result: *?*const h.pa_server_info = @alignCast(@ptrCast(data));
    result.* = info;
    c.pa_threaded_mainloop_signal(loop, 1);
}

fn sinkNameCallback(_: ?*h.pa_context, info: ?*const h.pa_sink_info, eol: c_int, data: ?*anyopaque) callconv(.c) void {
    const result: *?[*:0]const u8 = @alignCast(@ptrCast(data));
    if (eol == 0) {
        result.* = info.?.name;
        c.pa_threaded_mainloop_signal(loop, 1);
    } else {
        c.pa_threaded_mainloop_signal(loop, 0);
    }
}

fn sourceNameCallback(_: ?*h.pa_context, info: ?*const h.pa_source_info, eol: c_int, data: ?*anyopaque) callconv(.c) void {
    const result: *?[*:0]const u8 = @alignCast(@ptrCast(data));
    if (eol == 0) {
        result.* = info.?.name;
        c.pa_threaded_mainloop_signal(loop, 1);
    } else {
        c.pa_threaded_mainloop_signal(loop, 0);
    }
}

fn sinkListCallback(_: ?*h.pa_context, info: ?*const h.pa_sink_info, eol: c_int, data: ?*anyopaque) callconv(.c) void {
    const list: *std.ArrayList(AudioDevice) = @alignCast(@ptrCast(data));
    if (eol == 0) {
        const id = wio.allocator.dupeZ(u8, std.mem.sliceTo(info.?.name, 0)) catch return;
        list.append(.{ .id = id, .type = .output }) catch {
            wio.allocator.free(id);
            return;
        };
    } else {
        c.pa_threaded_mainloop_signal(loop, 0);
    }
}

fn sourceListCallback(_: ?*h.pa_context, info: ?*const h.pa_source_info, eol: c_int, data: ?*anyopaque) callconv(.c) void {
    const list: *std.ArrayList(AudioDevice) = @alignCast(@ptrCast(data));
    if (eol == 0) {
        const id = wio.allocator.dupeZ(u8, std.mem.sliceTo(info.?.name, 0)) catch return;
        list.append(.{ .id = id, .type = .input }) catch {
            wio.allocator.free(id);
            return;
        };
    } else {
        c.pa_threaded_mainloop_signal(loop, 0);
    }
}

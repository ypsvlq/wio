const std = @import("std");
const build_options = @import("build_options");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

var log_writer = std.Io.Writer{
    .vtable = &.{ .drain = logDrain },
    .buffer = &.{},
};

fn logDrain(_: *std.Io.Writer, data: []const []const u8, _: usize) !usize {
    js.write(data[0].ptr, data[0].len);
    return data[0].len;
}

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    log_writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    js.flush();
}

const js = struct {
    extern "wio" fn write([*]const u8, usize) void;
    extern "wio" fn flush() void;
    extern "wio" fn messageBox([*]const u8, usize) void;
    extern "wio" fn openUri([*]const u8, usize) void;
    extern "wio" fn createWindow(?*anyopaque) u32;
    extern "wio" fn enableTextInput(u32, u16, u16) void;
    extern "wio" fn disableTextInput(u32) void;
    extern "wio" fn enableRelativeMouse(u32, bool) void;
    extern "wio" fn disableRelativeMouse(u32) void;
    extern "wio" fn setFullscreen(u32, bool) void;
    extern "wio" fn setCursor(u32, u8) void;
    extern "wio" fn setSize(u32, u16, u16) void;
    extern "wio" fn setClipboardText([*]const u8, usize) void;
    extern "wio" fn presentFramebuffer(u32, [*]const u32, u16, u16) void;
    extern "wio" fn getDropFileCount(u32) u32;
    extern "wio" fn getDropFileLen(u32, u32) u32;
    extern "wio" fn getDropFile(u32, u32, [*]u8) void;
    extern "wio" fn getDropTextLen(u32) u32;
    extern "wio" fn getDropText(u32, [*]u8) void;
    extern "wio" fn getJoystickCount() u32;
    extern "wio" fn getJoystickIdLen(u32) u32;
    extern "wio" fn getJoystickId(u32, [*]u8) void;
    extern "wio" fn openJoystick(u32, *[2]u32) bool;
    extern "wio" fn getJoystickState(u32, [*]u16, usize, [*]bool, usize) bool;
    extern "wio" fn openAudioOutput(*const anyopaque, [*]f32, u32, u8) u32;
    extern "wio" fn openAudioInput(*const anyopaque, [*]f32, u32, u8) u32;
    extern "wio" fn closeAudioContext(u32) void;
};

const gl = struct {
    extern "gl" fn createContext(u32) void;
    extern "gl" fn makeContextCurrent(u32) void;
};

var joystickConnectedFn: ?*const fn (wio.JoystickDevice) void = null;

pub fn init(options: internal.BackendInitOptions) !void {
    if (build_options.joystick) {
        joystickConnectedFn = options.joystickConnectedFn;
    }
    if (build_options.audio) {
        if (options.audioDefaultOutputFn) |callback| callback(.{ .backend = .{} });
        if (options.audioDefaultInputFn) |callback| callback(.{ .backend = .{} });
    }
}

pub fn deinit() void {}

var loop: *const fn () anyerror!bool = undefined;

pub fn run(func: fn () anyerror!bool) !void {
    loop = func;
}

pub fn wait(_: wio.WaitOptions) void {}

pub fn cancelWait() void {}

pub fn messageBox(_: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    js.messageBox(message.ptr, message.len);
}

pub fn openUri(uri: []const u8) void {
    js.openUri(uri.ptr, uri.len);
}

pub const Window = struct {
    id: u32,

    pub fn create(options: wio.CreateWindowOptions) !Window {
        const id = js.createWindow(options.event_fn_data);

        internal.eventFn(options.event_fn_data, .visible);
        internal.eventFn(options.event_fn_data, .{ .mode = .normal });
        internal.eventFn(options.event_fn_data, .{ .position = .{ .x = 0, .y = 0 } });

        if (options.mode == .fullscreen) js.setFullscreen(id, true);

        return .{ .id = id };
    }

    pub fn destroy(_: *Window) void {}

    pub fn shouldPresent(_: *Window) bool {
        return true;
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        const x, const y = if (options.cursor) |cursor| .{ cursor.x, cursor.y } else .{ 0, 0 };
        js.enableTextInput(self.id, x, y);
    }

    pub fn disableTextInput(self: *Window) void {
        js.disableTextInput(self.id);
    }

    pub fn enableRelativeMouse(self: *Window, options: wio.RelativeMouseOptions) void {
        js.enableRelativeMouse(self.id, options.unaccelerated);
    }

    pub fn disableRelativeMouse(self: *Window) void {
        js.disableRelativeMouse(self.id);
    }

    pub fn setTitle(_: *Window, _: []const u8) void {}

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        js.setFullscreen(self.id, mode == .fullscreen);
    }

    pub fn setPosition(_: *Window, _: wio.RelativePosition) void {}

    pub fn setSize(self: *Window, size: wio.Size) void {
        js.setSize(self.id, size.width, size.height);
    }

    pub fn setParent(_: *Window, _: usize) void {}

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        js.setCursor(self.id, @intFromEnum(shape));
    }

    pub fn requestAttention(_: *Window) void {}

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        js.setClipboardText(text.ptr, text.len);
    }

    pub fn getClipboardText(_: *Window, _: std.mem.Allocator) ?[]u8 {
        return null;
    }

    pub fn getDropData(self: *Window, allocator: std.mem.Allocator) wio.DropData {
        return getDropDataInner(self, allocator) catch .{ .files = &.{}, .text = null };
    }

    fn getDropDataInner(self: *Window, allocator: std.mem.Allocator) !wio.DropData {
        const file_count = js.getDropFileCount(self.id);
        const files = try allocator.alloc([]const u8, file_count);
        var n: usize = 0;
        errdefer {
            for (files[0..n]) |f| allocator.free(f);
            allocator.free(files);
        }
        for (0..file_count) |i| {
            const len = js.getDropFileLen(self.id, @intCast(i));
            const buf = try allocator.alloc(u8, len);
            js.getDropFile(self.id, @intCast(i), buf.ptr);
            files[n] = buf;
            n += 1;
        }
        const text_len = js.getDropTextLen(self.id);
        const text: ?[]u8 = if (text_len > 0) blk: {
            const buf = try allocator.alloc(u8, text_len);
            js.getDropText(self.id, buf.ptr);
            break :blk buf;
        } else null;
        return .{ .files = files, .text = text };
    }

    pub fn createFramebuffer(_: *Window, size: wio.Size) !Framebuffer {
        const pixels = try internal.allocator.alloc(u32, @as(usize, size.width) * size.height);
        return .{ .pixels = pixels, .size = size };
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        js.presentFramebuffer(self.id, framebuffer.pixels.ptr, framebuffer.size.width, framebuffer.size.height);
    }

    pub fn glCreateContext(self: *Window, _: wio.GlCreateContextOptions) !GlContext {
        gl.createContext(self.id);
        return .{};
    }

    pub fn glMakeContextCurrent(self: *Window, _: GlContext) void {
        gl.makeContextCurrent(self.id);
    }

    pub fn glSwapBuffers(_: *Window) void {}

    pub fn glSwapInterval(_: *Window, _: i32) void {}
};

pub const Framebuffer = struct {
    pixels: []u32,
    size: wio.Size,

    pub fn destroy(self: *Framebuffer) void {
        internal.allocator.free(self.pixels);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        self.pixels[y * self.size.width + x] = 0xFF000000 | ((rgb & 0xFF0000) >> 16) | (rgb & 0xFF00) | ((rgb & 0xFF) << 16);
    }
};

pub const GlContext = struct {
    pub fn destroy(_: GlContext) void {}
};

pub fn glGetProcAddress(_: [*:0]const u8) ?*const anyopaque {
    return null;
}

pub fn glReleaseCurrentContext() void {}

pub const JoystickDeviceIterator = struct {
    index: u32 = 0,
    count: u32,

    pub fn init() JoystickDeviceIterator {
        return .{ .count = js.getJoystickCount() };
    }

    pub fn deinit(_: *JoystickDeviceIterator) void {}

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.index < self.count) {
            const device = JoystickDevice{ .index = self.index };
            self.index += 1;
            return device;
        } else {
            return null;
        }
    }
};

pub const JoystickDevice = struct {
    index: u32,

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !Joystick {
        var lengths: [2]u32 = undefined;
        if (!js.openJoystick(self.index, &lengths)) return error.Unexpected;
        const axes = try internal.allocator.alloc(u16, lengths[0]);
        errdefer internal.allocator.free(axes);
        const buttons = try internal.allocator.alloc(bool, lengths[1]);
        errdefer internal.allocator.free(buttons);
        return .{ .index = self.index, .axes = axes, .buttons = buttons };
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        const len = js.getJoystickIdLen(self.index);
        if (len == 0) return error.Unexpected;
        const name = try allocator.alloc(u8, len);
        js.getJoystickId(self.index, name.ptr);
        return name;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        return self.getId(allocator);
    }
};

pub const Joystick = struct {
    index: u32,
    axes: []u16,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        internal.allocator.free(self.axes);
        internal.allocator.free(self.buttons);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        if (!js.getJoystickState(self.index, self.axes.ptr, self.axes.len, self.buttons.ptr, self.buttons.len)) return null;
        return .{ .axes = self.axes, .hats = &.{}, .buttons = self.buttons };
    }
};

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

    pub fn openOutput(_: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        const buffer = try internal.allocator.alloc(f32, @as(usize, 128) * format.channels);
        const id = js.openAudioOutput(writeFn, buffer.ptr, format.sample_rate, format.channels);
        return .{ .id = id, .buffer = buffer };
    }

    pub fn openInput(_: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !AudioInput {
        const buffer = try internal.allocator.alloc(f32, @as(usize, 128) * format.channels);
        const id = js.openAudioInput(readFn, buffer.ptr, format.sample_rate, format.channels);
        return .{ .id = id, .buffer = buffer };
    }

    pub fn getId(_: AudioDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }

    pub fn getName(_: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, "WebAudio");
    }
};

pub const AudioOutput = struct {
    id: u32,
    buffer: []f32,

    pub fn close(self: *AudioOutput) void {
        js.closeAudioContext(self.id);
        internal.allocator.free(self.buffer);
    }
};

pub const AudioInput = struct {
    id: u32,
    buffer: []f32,

    pub fn close(self: *AudioInput) void {
        js.closeAudioContext(self.id);
        internal.allocator.free(self.buffer);
    }
};

export fn wioLoop() bool {
    return loop() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
}

export fn wioEvent(data: ?*anyopaque, event: u32, int0: u32, int1: u32, float0: f32) void {
    internal.eventFn(data, switch (@as(wio.EventType, @enumFromInt(event))) {
        .focused => .focused,
        .unfocused => .unfocused,
        .draw => .draw,
        .mode => .{ .mode = @enumFromInt(int0) },
        .size_logical => .{ .size_logical = .{ .width = @truncate(int0), .height = @truncate(int1) } },
        .size_physical => .{ .size_physical = .{ .width = @truncate(int0), .height = @truncate(int1) } },
        .scale => .{ .scale = float0 },
        .modifiers => .{ .modifiers = .{
            .control = (int0 & (1 << 0) != 0),
            .shift = (int0 & (1 << 1) != 0),
            .alt = (int0 & (1 << 2) != 0),
            .gui = (int0 & (1 << 3) != 0),
        } },
        .char => .{ .char = @intCast(int0) },
        .preview_reset => .preview_reset,
        .preview_char => .{ .preview_char = @intCast(int0) },
        .button_press => .{ .button_press = @enumFromInt(int0) },
        .button_repeat => .{ .button_repeat = @enumFromInt(int0) },
        .button_release => .{ .button_release = @enumFromInt(int0) },
        .mouse => .{ .mouse = .{ .x = @truncate(int0), .y = @truncate(int1) } },
        .mouse_relative => .{ .mouse_relative = .{ .x = @truncate(@as(i32, @bitCast(int0))), .y = @truncate(@as(i32, @bitCast(int1))) } },
        .mouse_leave => .mouse_leave,
        .scroll_vertical => .{ .scroll_vertical = float0 },
        .scroll_horizontal => .{ .scroll_horizontal = float0 },
        .drop_begin => .drop_begin,
        .drop_position => .{ .drop_position = .{ .x = @truncate(int0), .y = @truncate(int1) } },
        .drop_complete => .drop_complete,
        else => unreachable,
    });
}

export fn wioJoystick(index: u32) void {
    if (joystickConnectedFn) |callback| {
        callback(.{ .backend = .{ .index = index } });
    }
}

export fn wioAudioCallback(data: *const anyopaque, buffer: [*]f32, len: usize) void {
    const callback: *const fn ([]f32) void = @ptrCast(data);
    callback(buffer[0..len]);
}

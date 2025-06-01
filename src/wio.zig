const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const internal = @import("wio.internal.zig");
pub const backend = switch (builtin.os.tag) {
    .windows => @import("win32.zig"),
    .macos => @import("macos.zig"),
    .linux, .openbsd, .netbsd, .freebsd, .dragonfly => @import("unix.zig"),
    else => if (builtin.target.isWasm()) @import("wasm.zig") else @compileError("unsupported platform"),
};

pub const InitOptions = struct {
    /// Free with `JoystickDevice.release()`.
    joystickConnectedFn: ?*const fn (JoystickDevice) void = null,

    /// Free with `AudioDevice.release()`.
    audioDefaultOutputFn: ?*const fn (AudioDevice) void = null,
    /// Free with `AudioDevice.release()`.
    audioDefaultInputFn: ?*const fn (AudioDevice) void = null,
};

/// Unless otherwise noted, all calls to wio functions must be made on the same thread.
pub fn init(ally: std.mem.Allocator, options: InitOptions) !void {
    internal.allocator = ally;
    internal.init_options = options;
    try backend.init();
}

/// All windows and devices must be closed before deinit is called.
pub fn deinit() void {
    backend.deinit();
}

/// Begins the main loop, which continues as long as `func` returns true.
///
/// This must be the final call on its thread, and there must be no uses of `defer` in the same scope
/// (depending on the platform, it may return immediately, never, or when the main loop exits).
pub fn run(func: fn () anyerror!bool) !void {
    return backend.run(func);
}

/// Alternative to `run`, providing user control over the main loop.
///
/// Not available on all platforms.
pub fn update() void {
    backend.update();
}

/// Sleep until an event is received.
pub fn wait() void {
    backend.wait();
}

pub const MessageBoxStyle = enum { info, warn, err };

pub fn messageBox(style: MessageBoxStyle, title: []const u8, message: []const u8) void {
    backend.messageBox(style, title, message);
}

pub const Size = struct {
    width: u16,
    height: u16,

    pub fn multiply(self: Size, scale: f32) Size {
        const width: f32 = @floatFromInt(self.width);
        const height: f32 = @floatFromInt(self.height);
        return .{
            .width = @intFromFloat(width * scale),
            .height = @intFromFloat(height * scale),
        };
    }
};

pub const CreateWindowOptions = struct {
    title: []const u8 = "wio",
    mode: WindowMode = .normal,
    cursor: Cursor = .arrow,
    cursor_mode: CursorMode = .normal,

    size: Size = .{ .width = 640, .height = 480 },
    /// Base scale factor for `size`. If set, adjusts for high-DPI on relevant platforms.
    ///
    /// Recommended to set to 1 initially, or the last `Event.scale` when restoring dimensions.
    scale: ?f32 = null,

    /// Window handle, for embedding.
    parent: usize = 0,

    opengl: ?CreateContextOptions = null,
};

pub fn createWindow(options: CreateWindowOptions) !Window {
    return .{ .backend = try backend.createWindow(options) };
}

pub const Window = struct {
    backend: @typeInfo(@typeInfo(@TypeOf(backend.createWindow)).@"fn".return_type.?).error_union.payload,

    pub fn destroy(self: *Window) void {
        self.backend.destroy();
    }

    pub fn getEvent(self: *Window) ?Event {
        return self.backend.getEvent();
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        self.backend.setTitle(title);
    }

    pub fn setMode(self: *Window, mode: WindowMode) void {
        self.backend.setMode(mode);
    }

    pub fn setCursor(self: *Window, cursor: Cursor) void {
        self.backend.setCursor(cursor);
    }

    pub fn setCursorMode(self: *Window, mode: CursorMode) void {
        self.backend.setCursorMode(mode);
    }

    pub fn setSize(self: *Window, size: Size) void {
        self.backend.setSize(size);
    }

    pub fn setParent(self: *Window, parent: usize) void {
        self.backend.setParent(parent);
    }

    pub fn requestAttention(self: *Window) void {
        self.backend.requestAttention();
    }

    pub fn setClipboardText(self: *Window, text: []const u8) void {
        self.backend.setClipboardText(text);
    }

    pub fn getClipboardText(self: *Window, ally: std.mem.Allocator) ?[]u8 {
        return self.backend.getClipboardText(ally);
    }

    /// May be called on any thread.
    pub fn makeContextCurrent(self: *Window) void {
        self.backend.makeContextCurrent();
    }

    /// Must be called on the thread where the context is current.
    pub fn swapBuffers(self: *Window) void {
        self.backend.swapBuffers();
    }

    /// Must be called on the thread where the context is current.
    pub fn swapInterval(self: *Window, interval: i32) void {
        self.backend.swapInterval(interval);
    }

    /// Not available on all platforms.
    pub fn createSurface(self: *Window, instance: usize, vk_allocator: ?*const anyopaque, surface: *u64) i32 {
        assertFeature(.vulkan);
        return self.backend.createSurface(instance, vk_allocator, surface);
    }
};

/// Must be called on the thread where the context is current.
pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const fn () void {
    assertFeature(.opengl);
    return @alignCast(@ptrCast(backend.glGetProcAddress(name)));
}

/// Not available on all platforms.
pub fn vkGetInstanceProcAddr(instance: usize, name: [*:0]const u8) ?*const fn () void {
    assertFeature(.vulkan);
    return backend.vkGetInstanceProcAddr(instance, name);
}

/// Not available on all platforms.
pub fn getVulkanExtensions() []const [*:0]const u8 {
    return backend.getVulkanExtensions();
}

pub const JoystickDeviceIterator = struct {
    backend: backend.JoystickDeviceIterator,

    /// Invalidated on the next iteration of the main loop (or call to `update`).
    pub fn init() JoystickDeviceIterator {
        assertFeature(.joystick);
        return .{ .backend = backend.JoystickDeviceIterator.init() };
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        self.backend.deinit();
    }

    /// Free with `JoystickDevice.release()`.
    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        return .{ .backend = self.backend.next() orelse return null };
    }
};

pub const JoystickDevice = struct {
    backend: backend.JoystickDevice,

    pub fn release(self: JoystickDevice) void {
        self.backend.release();
    }

    pub fn open(self: JoystickDevice) ?Joystick {
        return .{ .backend = self.backend.open() catch return null };
    }

    /// May not be unique.
    pub fn getId(self: JoystickDevice, ally: std.mem.Allocator) ?[]u8 {
        return self.backend.getId(ally) catch null;
    }

    /// Returns "" on error.
    pub fn getName(self: JoystickDevice, ally: std.mem.Allocator) []u8 {
        return self.backend.getName(ally) catch "";
    }
};

pub const Joystick = struct {
    backend: @typeInfo(@typeInfo(@TypeOf(backend.JoystickDevice.open)).@"fn".return_type.?).error_union.payload,

    pub fn close(self: *Joystick) void {
        self.backend.close();
    }

    pub fn poll(self: *Joystick) ?JoystickState {
        return self.backend.poll();
    }
};

pub const JoystickState = struct {
    axes: []u16,
    hats: []Hat,
    buttons: []bool,
};

pub const Hat = packed struct {
    up: bool = false,
    right: bool = false,
    down: bool = false,
    left: bool = false,
};

pub const AudioDeviceType = enum { output, input };

pub const AudioDeviceIterator = struct {
    backend: backend.AudioDeviceIterator,

    /// Invalidated on the next iteration of the main loop (or call to `update`).
    pub fn init(mode: AudioDeviceType) AudioDeviceIterator {
        assertFeature(.audio);
        return .{ .backend = backend.AudioDeviceIterator.init(mode) };
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        self.backend.deinit();
    }

    // Free with `AudioDevice.release()`.
    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        return .{ .backend = self.backend.next() orelse return null };
    }
};

pub const AudioDevice = struct {
    backend: backend.AudioDevice,

    pub fn release(self: AudioDevice) void {
        return self.backend.release();
    }

    /// `writeFn` is called on a separate thread.
    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: AudioFormat) ?AudioOutput {
        return .{ .backend = self.backend.openOutput(writeFn, format) catch return null };
    }

    /// `readFn` is called on a separate thread.
    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: AudioFormat) ?AudioInput {
        return .{ .backend = self.backend.openInput(readFn, format) catch return null };
    }

    /// May not be unique.
    pub fn getId(self: AudioDevice, ally: std.mem.Allocator) ?[]u8 {
        return self.backend.getId(ally) catch null;
    }

    /// Returns "" on error.
    pub fn getName(self: AudioDevice, ally: std.mem.Allocator) []u8 {
        return self.backend.getName(ally) catch "";
    }
};

pub const AudioOutput = struct {
    backend: @typeInfo(@typeInfo(@TypeOf(backend.AudioDevice.openOutput)).@"fn".return_type.?).error_union.payload,

    pub fn close(self: *AudioOutput) void {
        self.backend.close();
    }
};

pub const AudioInput = struct {
    backend: @typeInfo(@typeInfo(@TypeOf(backend.AudioDevice.openInput)).@"fn".return_type.?).error_union.payload,

    pub fn close(self: *AudioInput) void {
        self.backend.close();
    }
};

pub const AudioFormat = struct {
    sample_rate: u32,
    channels: u8,
};

pub const Event = union(enum) {
    close: void,
    focused: void,
    unfocused: void,
    visible: void,
    hidden: void,
    draw: void,
    size: Size,
    framebuffer: Size,
    scale: f32,
    /// Sent before `size`.
    mode: WindowMode,
    char: u21,
    button_press: Button,
    button_repeat: Button,
    button_release: Button,
    mouse: struct { x: u16, y: u16 },
    mouse_relative: struct { x: i16, y: i16 },
    scroll_vertical: f32,
    scroll_horizontal: f32,
};

pub const EventType = @typeInfo(Event).@"union".tag_type.?;

pub const WindowMode = enum {
    normal,
    maximized,
    fullscreen,
};

pub const Cursor = enum {
    arrow,
    arrow_busy,
    busy,
    text,
    hand,
    crosshair,
    forbidden,
    move,
    size_ns,
    size_ew,
    size_nesw,
    size_nwse,
};

pub const CursorMode = enum {
    normal,
    hidden,
    relative,
};

pub const CreateContextOptions = struct {
    major_version: u8 = 1,
    minor_version: u8 = 0,
    profile: enum { core, compatibility } = .core,
    forward_compatible: bool = false,
    debug: bool = false,

    doublebuffer: bool = true,
    red_bits: u8 = 8,
    green_bits: u8 = 8,
    blue_bits: u8 = 8,
    alpha_bits: u8 = 8,
    depth_bits: u8 = 24,
    stencil_bits: u8 = 8,
    samples: u8 = 0,
};

pub const Button = enum {
    mouse_left,
    mouse_right,
    mouse_middle,
    mouse_back,
    mouse_forward,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    enter,
    escape,
    backspace,
    tab,
    space,
    minus,
    equals,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    grave,
    comma,
    dot,
    slash,
    caps_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    print_screen,
    scroll_lock,
    pause,
    insert,
    home,
    page_up,
    delete,
    end,
    page_down,
    right,
    left,
    down,
    up,
    num_lock,
    kp_slash,
    kp_star,
    kp_minus,
    kp_plus,
    kp_enter,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_0,
    kp_dot,
    iso_backslash,
    application,
    kp_equals,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    kp_comma,
    international1,
    international2,
    international3,
    international4,
    international5,
    lang1,
    lang2,
    left_control,
    left_shift,
    left_alt,
    left_gui,
    right_control,
    right_shift,
    right_alt,
    right_gui,
};

fn assertFeature(feature: anytype) void {
    if (!@field(build_options, @tagName(feature))) {
        @compileError("feature '" ++ @tagName(feature) ++ "' is disabled");
    }
}

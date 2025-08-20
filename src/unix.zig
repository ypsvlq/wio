const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const DynLib = @import("unix/DynLib.zig");
pub const x11 = if (build_options.x11) @import("unix/x11.zig") else @import("null.zig");
pub const wayland = if (build_options.wayland) @import("unix/wayland.zig") else @import("null.zig");
const joystick = switch (builtin.os.tag) {
    .linux => @import("unix/joystick/linux.zig"),
    else => @import("unix/joystick/null.zig"),
};
const audio = switch (builtin.os.tag) {
    .linux => @import("unix/audio/pulseaudio.zig"),
    .openbsd => @import("unix/audio/sndio.zig"),
    else => @import("unix/audio/null.zig"),
};
const log = std.log.scoped(.wio);

pub var active: enum {
    x11,
    wayland,
} = undefined;

pub var pollfds: std.ArrayList(std.c.pollfd) = undefined;

pub var libvulkan: DynLib = undefined;

pub fn init() !void {
    if (!build_options.system_integration and builtin.os.tag == .linux and builtin.output_mode == .Exe and builtin.link_mode == .static) @compileError("dynamic link required");

    pollfds = .empty;
    errdefer pollfds.deinit(internal.allocator);

    if (build_options.vulkan) {
        libvulkan = try .open("libvulkan.so.1");
        vkGetInstanceProcAddr = if (build_options.system_integration)
            @extern(@TypeOf(vkGetInstanceProcAddr), .{ .name = "vkGetInstanceProcAddr" })
        else
            libvulkan.lookup(@TypeOf(vkGetInstanceProcAddr), "vkGetInstanceProcAddr") orelse {
                log.err("could not load {s}", .{"vkGetInstanceProcAddr"});
                return error.Unexpected;
            };
    }
    errdefer if (build_options.vulkan) libvulkan.close();

    if (build_options.joystick) try joystick.init();
    errdefer if (build_options.joystick) joystick.deinit();
    if (build_options.audio) try audio.init();
    errdefer if (build_options.audio) audio.deinit();

    var try_x11 = true;
    var try_wayland = true;
    if (build_options.x11 and build_options.wayland) {
        if (std.c.getenv("XDG_SESSION_TYPE")) |value| {
            const session_type = std.mem.sliceTo(value, 0);
            if (std.mem.eql(u8, session_type, "wayland")) {
                if (try initBackend(.wayland)) return;
                try_wayland = false;
            } else if (std.mem.eql(u8, session_type, "x11")) {
                if (try initBackend(.x11)) return;
                try_x11 = false;
            }
        }
    }

    if (build_options.wayland and try_wayland) {
        if (try initBackend(.wayland)) return;
    }

    if (build_options.x11 and try_x11) {
        if (try initBackend(.x11)) return;
    }

    log.err("could not connect to window system", .{});
    return error.Unexpected;
}

fn initBackend(comptime backend: anytype) !bool {
    if (@field(@This(), @tagName(backend)).init()) {
        active = backend;
        return true;
    } else |err| return if (err == error.Unavailable) false else err;
}

pub fn deinit() void {
    if (build_options.audio) audio.deinit();
    if (build_options.joystick) joystick.deinit();
    if (build_options.vulkan) libvulkan.close();
    switch (active) {
        .x11 => x11.deinit(),
        .wayland => wayland.deinit(),
    }
    pollfds.deinit(internal.allocator);
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        update();
    }
}

pub fn update() void {
    switch (active) {
        .x11 => x11.update(),
        .wayland => wayland.update(),
    }
    if (build_options.joystick) joystick.update();
    if (build_options.audio) audio.update();
}

pub fn wait() void {
    var timeout: c_int = -1;
    if (build_options.wayland and active == .wayland) {
        if (wayland.focus) |focus| {
            if (focus.repeat_key != 0) {
                timeout = wayland.repeat_period;
            }
        }
    }
    _ = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), timeout);
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    if (build_options.wayland and active == .wayland) {
        if (wayland.focus) |focus| {
            focus.repeat_key = 0;
        }
    }

    var kdialog = std.process.Child.init(&.{
        "kdialog",
        "--title",
        title,
        switch (style) {
            .info => "--msgbox",
            .warn => "--sorry",
            .err => "--error",
        },
        message,
    }, internal.allocator);

    if (kdialog.spawnAndWait()) |_| {
        return;
    } else |_| {}

    var zenity = std.process.Child.init(&.{
        "zenity",
        switch (style) {
            .info => "--info",
            .warn => "--warning",
            .err => "--error",
        },
        "--title",
        title,
        "--text",
        message,
    }, internal.allocator);

    if (zenity.spawnAndWait()) |_| {
        return;
    } else |_| {}
}

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    switch (active) {
        .x11 => return .{ .x11 = try x11.createWindow(options) },
        .wayland => return .{ .wayland = try wayland.createWindow(options) },
    }
}

pub const Window = union {
    x11: *x11,
    wayland: *wayland,

    pub fn destroy(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.destroy(),
            .wayland => self.wayland.destroy(),
        }
    }

    pub fn getEvent(self: *@This()) ?wio.Event {
        switch (active) {
            .x11 => return self.x11.getEvent(),
            .wayland => return self.wayland.getEvent(),
        }
    }

    pub fn setTitle(self: *@This(), title: []const u8) void {
        switch (active) {
            .x11 => self.x11.setTitle(title),
            .wayland => self.wayland.setTitle(title),
        }
    }

    pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
        switch (active) {
            .x11 => self.x11.setMode(mode),
            .wayland => self.wayland.setMode(mode),
        }
    }

    pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
        switch (active) {
            .x11 => self.x11.setCursor(shape),
            .wayland => self.wayland.setCursor(shape),
        }
    }

    pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
        switch (active) {
            .x11 => self.x11.setCursorMode(mode),
            .wayland => self.wayland.setCursorMode(mode),
        }
    }

    pub fn setSize(self: *@This(), size: wio.Size) void {
        switch (active) {
            .x11 => self.x11.setSize(size),
            .wayland => self.wayland.setSize(size),
        }
    }

    pub fn setParent(self: *@This(), parent: usize) void {
        switch (active) {
            .x11 => self.x11.setParent(parent),
            .wayland => self.wayland.setParent(parent),
        }
    }

    pub fn requestAttention(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.requestAttention(),
            .wayland => self.wayland.requestAttention(),
        }
    }

    pub fn setClipboardText(self: *@This(), text: []const u8) void {
        switch (active) {
            .x11 => self.x11.setClipboardText(text),
            .wayland => self.wayland.setClipboardText(text),
        }
    }

    pub fn getClipboardText(self: *@This(), allocator: std.mem.Allocator) ?[]u8 {
        switch (active) {
            .x11 => return self.x11.getClipboardText(allocator),
            .wayland => return self.wayland.getClipboardText(allocator),
        }
    }

    pub fn makeContextCurrent(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.makeContextCurrent(),
            .wayland => self.wayland.makeContextCurrent(),
        }
    }

    pub fn swapBuffers(self: *@This()) void {
        switch (active) {
            .x11 => self.x11.swapBuffers(),
            .wayland => self.wayland.swapBuffers(),
        }
    }

    pub fn swapInterval(self: *@This(), interval: i32) void {
        switch (active) {
            .x11 => self.x11.swapInterval(interval),
            .wayland => self.wayland.swapInterval(interval),
        }
    }

    pub fn createSurface(self: @This(), instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
        switch (active) {
            .x11 => return self.x11.createSurface(instance, allocator, surface),
            .wayland => return self.wayland.createSurface(instance, allocator, surface),
        }
    }
};

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    switch (active) {
        .x11 => return x11.glGetProcAddress(name),
        .wayland => return wayland.glGetProcAddress(name),
    }
}

pub var vkGetInstanceProcAddr: *const fn (usize, [*:0]const u8) callconv(.c) ?*const fn () void = undefined;

pub fn getVulkanExtensions() []const [*:0]const u8 {
    switch (active) {
        .x11 => return x11.getVulkanExtensions(),
        .wayland => return wayland.getVulkanExtensions(),
    }
}

pub const JoystickDeviceIterator = joystick.JoystickDeviceIterator;
pub const JoystickDevice = joystick.JoystickDevice;
pub const Joystick = joystick.Joystick;

pub const AudioDeviceIterator = audio.AudioDeviceIterator;
pub const AudioDevice = audio.AudioDevice;
pub const AudioOutput = audio.AudioOutput;
pub const AudioInput = audio.AudioInput;

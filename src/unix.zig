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
var pipe: [2]std.c.fd_t = undefined;

pub var libvulkan: DynLib = undefined;

pub fn init() !void {
    if (!build_options.system_integration and builtin.os.tag == .linux and builtin.output_mode == .Exe and builtin.link_mode == .static) @compileError("dynamic link required");

    pollfds = .empty;
    errdefer pollfds.deinit(internal.allocator);

    if (std.c.pipe(&pipe) == -1) return error.Unexpected;
    errdefer {
        _ = std.c.close(pipe[0]);
        _ = std.c.close(pipe[1]);
    }
    if (std.c.fcntl(pipe[0], std.c.F.SETFL, @as(u32, @bitCast(std.c.O{ .NONBLOCK = true }))) == -1) return error.Unexpected;
    try pollfds.append(internal.allocator, .{ .fd = pipe[0], .events = std.c.POLL.IN, .revents = undefined });

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
                if (try wayland.init()) {
                    active = .wayland;
                    return;
                }
                try_wayland = false;
            } else if (std.mem.eql(u8, session_type, "x11")) {
                if (try x11.init()) {
                    active = .x11;
                    return;
                }
                try_x11 = false;
            }
        }
    }

    if (build_options.wayland and try_wayland) {
        if (try wayland.init()) {
            active = .wayland;
            return;
        }
    }

    if (build_options.x11 and try_x11) {
        if (try x11.init()) {
            active = .x11;
            return;
        }
    }

    log.err("could not connect to window system", .{});
    return error.Unexpected;
}

pub fn deinit() void {
    switch (active) {
        .x11 => x11.deinit(),
        .wayland => wayland.deinit(),
    }
    if (build_options.audio) audio.deinit();
    if (build_options.joystick) joystick.deinit();
    if (build_options.vulkan) libvulkan.close();
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

pub fn wait(options: wio.WaitOptions) void {
    var timeout: c_int = -1;
    if (options.timeout_ns) |timeout_ns| {
        timeout = std.math.lossyCast(c_int, timeout_ns / std.time.ns_per_ms);
    }
    if (build_options.wayland and active == .wayland and wayland.repeat_period > 0) {
        if (timeout == -1 or wayland.repeat_period < timeout) {
            if (wayland.keyboard_focus) |focus| {
                if (focus.repeat_key != 0) {
                    timeout = wayland.repeat_period;
                }
            }
        }
    }

    var buf: [16]u8 = undefined;
    while (std.c.read(pipe[0], &buf, buf.len) == buf.len) {}

    internal.wait = true;
    if (timeout == -1) {
        while (internal.wait) {
            _ = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), timeout);
            update();
        }
    } else {
        const start = std.Io.Clock.awake.now(internal.io).toMilliseconds();
        var now = start;
        while (internal.wait and now - start < timeout) {
            _ = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), timeout);
            update();
            now = std.Io.Clock.awake.now(internal.io).toMilliseconds();
            timeout -= @truncate(now - start);
        }
    }
}

pub fn cancelWait() void {
    internal.wait = false;
    _ = std.c.write(pipe[1], &.{0}, 1);
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    const kdialog = &.{
        "kdialog",
        "--title",
        title,
        switch (style) {
            .info => "--msgbox",
            .warn => "--sorry",
            .err => "--error",
        },
        message,
    };

    if (spawnAndPoll(kdialog)) return;

    const zenity = &.{
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
    };

    if (spawnAndPoll(zenity)) return;
}

fn spawnAndPoll(args: []const []const u8) bool {
    var process = std.process.spawn(internal.io, .{ .argv = args, .stdout = .pipe }) catch return false;
    defer _ = process.wait(internal.io) catch {};
    pollfds.append(internal.allocator, .{ .fd = process.stdout.?.handle, .events = std.c.POLL.HUP, .revents = 0 }) catch return false;
    const index = pollfds.items.len - 1;
    while (pollfds.items[index].revents == 0) {
        _ = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), -1);
        update();
    }
    _ = pollfds.swapRemove(index);
    return true;
}

pub fn openUri(uri: []const u8) void {
    var child = std.process.spawn(internal.io, .{ .argv = &.{ "xdg-open", uri } }) catch |err| {
        log.err("could not spawn xdg-open: {s}", .{@errorName(err)});
        return;
    };
    _ = child.wait(internal.io) catch {};
}

pub fn getModifiers() wio.Modifiers {
    return switch (active) {
        .x11 => x11.getModifiers(),
        .wayland => wayland.getModifiers(),
    };
}

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    switch (active) {
        .x11 => return .{ .x11 = try x11.createWindow(options) },
        .wayland => return .{ .wayland = try wayland.createWindow(options) },
    }
}

pub const Window = union {
    x11: *x11.Window,
    wayland: *wayland.Window,

    pub fn destroy(self: *Window) void {
        switch (active) {
            .x11 => self.x11.destroy(),
            .wayland => self.wayland.destroy(),
        }
    }

    pub fn getEvent(self: *Window) ?wio.Event {
        switch (active) {
            .x11 => return self.x11.getEvent(),
            .wayland => return self.wayland.getEvent(),
        }
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        switch (active) {
            .x11 => self.x11.enableTextInput(options),
            .wayland => self.wayland.enableTextInput(options),
        }
    }

    pub fn disableTextInput(self: *Window) void {
        switch (active) {
            .x11 => self.x11.disableTextInput(),
            .wayland => self.wayland.disableTextInput(),
        }
    }

    pub fn enableRelativeMouse(self: *Window) void {
        switch (active) {
            .x11 => self.x11.enableRelativeMouse(),
            .wayland => self.wayland.enableRelativeMouse(),
        }
    }

    pub fn disableRelativeMouse(self: *Window) void {
        switch (active) {
            .x11 => self.x11.disableRelativeMouse(),
            .wayland => self.wayland.disableRelativeMouse(),
        }
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        switch (active) {
            .x11 => self.x11.setTitle(title),
            .wayland => self.wayland.setTitle(title),
        }
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        switch (active) {
            .x11 => self.x11.setMode(mode),
            .wayland => self.wayland.setMode(mode),
        }
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        switch (active) {
            .x11 => self.x11.setSize(size),
            .wayland => self.wayland.setSize(size),
        }
    }

    pub fn setParent(self: *Window, parent: usize) void {
        switch (active) {
            .x11 => self.x11.setParent(parent),
            .wayland => self.wayland.setParent(parent),
        }
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        switch (active) {
            .x11 => self.x11.setCursor(shape),
            .wayland => self.wayland.setCursor(shape),
        }
    }

    pub fn requestAttention(self: *Window) void {
        switch (active) {
            .x11 => self.x11.requestAttention(),
            .wayland => self.wayland.requestAttention(),
        }
    }

    pub fn setClipboardText(self: *Window, text: []const u8) void {
        switch (active) {
            .x11 => self.x11.setClipboardText(text),
            .wayland => self.wayland.setClipboardText(text),
        }
    }

    pub fn getClipboardText(self: *Window, allocator: std.mem.Allocator) ?[]u8 {
        switch (active) {
            .x11 => return self.x11.getClipboardText(allocator),
            .wayland => return self.wayland.getClipboardText(allocator),
        }
    }

    pub fn getDropData(self: *Window, allocator: std.mem.Allocator) wio.DropData {
        switch (active) {
            .x11 => return self.x11.getDropData(allocator),
            .wayland => return self.wayland.getDropData(allocator),
        }
    }

    pub fn createFramebuffer(self: *Window, size: wio.Size) !Framebuffer {
        switch (active) {
            .x11 => return .{ .x11 = try self.x11.createFramebuffer(size) },
            .wayland => return .{ .wayland = try self.wayland.createFramebuffer(size) },
        }
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        switch (active) {
            .x11 => self.x11.presentFramebuffer(&framebuffer.x11),
            .wayland => self.wayland.presentFramebuffer(&framebuffer.wayland),
        }
    }

    pub fn glCreateContext(self: *Window, options: wio.GlCreateContextOptions) !GlContext {
        return switch (active) {
            .x11 => .{ .x11 = try self.x11.glCreateContext(options) },
            .wayland => .{ .wayland = try self.wayland.glCreateContext(options) },
        };
    }

    pub fn glMakeContextCurrent(self: *Window, context: GlContext) void {
        switch (active) {
            .x11 => self.x11.glMakeContextCurrent(context.x11),
            .wayland => self.wayland.glMakeContextCurrent(context.wayland),
        }
    }

    pub fn glSwapBuffers(self: *Window) void {
        switch (active) {
            .x11 => self.x11.glSwapBuffers(),
            .wayland => self.wayland.glSwapBuffers(),
        }
    }

    pub fn glSwapInterval(self: *Window, interval: i32) void {
        switch (active) {
            .x11 => self.x11.glSwapInterval(interval),
            .wayland => self.wayland.glSwapInterval(interval),
        }
    }

    pub fn vkCreateSurface(self: Window, instance: usize, allocation_callbacks: ?*const anyopaque, surface: *u64) i32 {
        switch (active) {
            .x11 => return self.x11.vkCreateSurface(instance, allocation_callbacks, surface),
            .wayland => return self.wayland.vkCreateSurface(instance, allocation_callbacks, surface),
        }
    }
};

pub const Framebuffer = union {
    x11: x11.Framebuffer,
    wayland: wayland.Framebuffer,

    pub fn destroy(self: *Framebuffer) void {
        switch (active) {
            .x11 => self.x11.destroy(),
            .wayland => self.wayland.destroy(),
        }
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        switch (active) {
            .x11 => self.x11.setPixel(x, y, rgb),
            .wayland => self.wayland.setPixel(x, y, rgb),
        }
    }
};

pub const GlContext = union {
    x11: x11.GlContext,
    wayland: wayland.GlContext,

    pub fn destroy(self: GlContext) void {
        switch (active) {
            .x11 => self.x11.destroy(),
            .wayland => self.wayland.destroy(),
        }
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    switch (active) {
        .x11 => return x11.glGetProcAddress(name),
        .wayland => return wayland.glGetProcAddress(name),
    }
}

pub var vkGetInstanceProcAddr: *const fn (usize, [*:0]const u8) callconv(.c) ?*const fn () void = undefined;

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
    switch (active) {
        .x11 => return x11.getRequiredVulkanInstanceExtensions(),
        .wayland => return wayland.getRequiredVulkanInstanceExtensions(),
    }
}

pub const JoystickDeviceIterator = joystick.JoystickDeviceIterator;
pub const JoystickDevice = joystick.JoystickDevice;
pub const Joystick = joystick.Joystick;

pub const AudioDeviceIterator = audio.AudioDeviceIterator;
pub const AudioDevice = audio.AudioDevice;
pub const AudioOutput = audio.AudioOutput;
pub const AudioInput = audio.AudioInput;

const std = @import("std");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

pub var allocator: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;
pub var init_options: wio.InitOptions = undefined;
pub var wait = false;

pub const EventQueue = struct {
    events: std.ArrayList(wio.Event) = .empty,
    head: usize = 0,

    pub fn init() EventQueue {
        return .{};
    }

    pub fn deinit(self: *EventQueue) void {
        self.events.deinit(allocator);
    }

    pub fn push(self: *EventQueue, event: wio.Event) void {
        if (self.head != 0) {
            self.events.replaceRangeAssumeCapacity(0, self.head, &.{});
            self.head = 0;
        }

        switch (std.meta.activeTag(event)) {
            .draw, .mode, .size_logical, .size_physical => |tag| {
                for (self.events.items, 0..) |item, i| {
                    if (item == tag) {
                        _ = self.events.orderedRemove(i);
                        break;
                    }
                }
            },
            else => {},
        }

        self.events.append(allocator, event) catch {};

        wait = false;
    }

    pub fn pop(self: *EventQueue) ?wio.Event {
        if (self.head == self.events.items.len) return null;
        defer self.head += 1;
        return self.events.items[self.head];
    }
};

pub fn logUnexpected(name: []const u8) error{Unexpected} {
    log.err("{s} failed", .{name});
    return error.Unexpected;
}

pub fn egl(c: anytype, h: anytype) type {
    return struct {
        pub var display: h.EGLDisplay = undefined;

        pub fn init(native: h.NativeDisplayType) !void {
            display = c.eglGetDisplay(native) orelse return logError("eglGetDisplay");
            if (c.eglInitialize(display, null, null) == h.EGL_FALSE) return logError("eglInitialize");
        }

        pub fn chooseConfig(options: wio.GlOptions) !h.EGLConfig {
            var config: h.EGLConfig = undefined;

            if (c.eglBindAPI(switch (options.api) {
                .gl => h.EGL_OPENGL_API,
                .gles1, .gles2 => h.EGL_OPENGL_ES_API,
            }) == h.EGL_FALSE) return logError("eglBindAPI");

            const renderable_type = switch (options.api) {
                .gl => h.EGL_OPENGL_BIT,
                .gles1 => h.EGL_OPENGL_ES_BIT,
                .gles2 => h.EGL_OPENGL_ES2_BIT,
            };

            var count: i32 = undefined;
            if (c.eglChooseConfig(display, &[_]i32{
                h.EGL_RENDERABLE_TYPE, renderable_type,
                h.EGL_RED_SIZE,        options.red_bits,
                h.EGL_GREEN_SIZE,      options.green_bits,
                h.EGL_BLUE_SIZE,       options.blue_bits,
                h.EGL_ALPHA_SIZE,      options.alpha_bits,
                h.EGL_DEPTH_SIZE,      options.depth_bits,
                h.EGL_STENCIL_SIZE,    options.stencil_bits,
                h.EGL_SAMPLE_BUFFERS,  if (options.samples != 0) 1 else 0,
                h.EGL_SAMPLES,         options.samples,
                h.EGL_NONE,
            }, &config, 1, &count) == h.EGL_FALSE) return logError("eglChooseConfig");

            return config;
        }

        pub fn createContext(config: h.EGLConfig, options: wio.GlOptions, share: h.EGLContext) !h.EGLContext {
            return c.eglCreateContext(
                display,
                config,
                share,
                switch (options.api) {
                    .gl => &[_]i32{
                        h.EGL_CONTEXT_MAJOR_VERSION,             options.major_version,
                        h.EGL_CONTEXT_MINOR_VERSION,             options.minor_version,
                        h.EGL_CONTEXT_OPENGL_PROFILE_MASK,       if (options.profile == .core) h.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT else h.EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT,
                        h.EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE, if (options.forward_compatible) h.EGL_TRUE else h.EGL_FALSE,
                        h.EGL_CONTEXT_OPENGL_DEBUG,              if (options.debug) h.EGL_TRUE else h.EGL_FALSE,
                        h.EGL_NONE,
                    },
                    .gles1, .gles2 => &[_]i32{
                        h.EGL_CONTEXT_MAJOR_VERSION, options.major_version,
                        h.EGL_CONTEXT_MINOR_VERSION, options.minor_version,
                        h.EGL_NONE,
                    },
                },
            ) orelse logError("eglCreateContext");
        }

        pub fn logError(name: []const u8) error{Unexpected} {
            log.err("{s} failed, error 0x{X}", .{ name, c.eglGetError() });
            return error.Unexpected;
        }
    };
}

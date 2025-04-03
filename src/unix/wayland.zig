const std = @import("std");
const wio = @import("../wio.zig");
const unix = @import("../unix.zig");
const dynlib = @import("dynlib.zig");
const log = std.log.scoped(.wio);
const h = @cImport({
    @cInclude("wio-wayland.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("viewporter-client-protocol.h");
    @cInclude("fractional-scale-v1-client-protocol.h");
    @cInclude("cursor-shape-v1-client-protocol.h");
    @cInclude("pointer-constraints-v1-client-protocol.h");
    @cInclude("relative-pointer-v1-client-protocol.h");
    @cInclude("xdg-activation-v1-client-protocol.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-compose.h");
    @cInclude("libdecor.h");
    @cInclude("wayland-egl.h");
    @cInclude("EGL/egl.h");
});

var c: extern struct {
    wl_display_connect: *const @TypeOf(h.wl_display_connect),
    wl_display_disconnect: *const @TypeOf(h.wl_display_disconnect),
    wl_display_roundtrip: *const @TypeOf(h.wl_display_roundtrip),
    wl_display_dispatch: *const @TypeOf(h.wl_display_dispatch),
    wl_proxy_get_version: *const @TypeOf(h.wl_proxy_get_version),
    wl_proxy_marshal_flags: *const @TypeOf(h.wl_proxy_marshal_flags),
    wl_proxy_add_listener: *const @TypeOf(h.wl_proxy_add_listener),
    wl_proxy_destroy: *const @TypeOf(h.wl_proxy_destroy),
    wl_proxy_set_user_data: *const @TypeOf(h.wl_proxy_set_user_data),
    wl_proxy_get_user_data: *const @TypeOf(h.wl_proxy_get_user_data),
    xkb_context_new: *const @TypeOf(h.xkb_context_new),
    xkb_context_unref: *const @TypeOf(h.xkb_context_unref),
    xkb_keymap_new_from_string: *const @TypeOf(h.xkb_keymap_new_from_string),
    xkb_keymap_unref: *const @TypeOf(h.xkb_keymap_unref),
    xkb_state_new: *const @TypeOf(h.xkb_state_new),
    xkb_state_unref: *const @TypeOf(h.xkb_state_unref),
    xkb_state_update_mask: *const @TypeOf(h.xkb_state_update_mask),
    xkb_state_key_get_one_sym: *const @TypeOf(h.xkb_state_key_get_one_sym),
    xkb_keysym_to_utf32: *const @TypeOf(h.xkb_keysym_to_utf32),
    xkb_compose_table_new_from_locale: *const @TypeOf(h.xkb_compose_table_new_from_locale),
    xkb_compose_table_unref: *const @TypeOf(h.xkb_compose_table_unref),
    xkb_compose_state_new: *const @TypeOf(h.xkb_compose_state_new),
    xkb_compose_state_unref: *const @TypeOf(h.xkb_compose_state_unref),
    xkb_compose_state_feed: *const @TypeOf(h.xkb_compose_state_feed),
    xkb_compose_state_get_status: *const @TypeOf(h.xkb_compose_state_get_status),
    xkb_compose_state_get_one_sym: *const @TypeOf(h.xkb_compose_state_get_one_sym),
    xkb_compose_state_reset: *const @TypeOf(h.xkb_compose_state_reset),
    libdecor_new: *const @TypeOf(h.libdecor_new),
    libdecor_unref: *const @TypeOf(h.libdecor_unref),
    libdecor_decorate: *const @TypeOf(h.libdecor_decorate),
    libdecor_frame_unref: *const @TypeOf(h.libdecor_frame_unref),
    libdecor_configuration_get_window_state: *const @TypeOf(h.libdecor_configuration_get_window_state),
    libdecor_configuration_get_content_size: *const @TypeOf(h.libdecor_configuration_get_content_size),
    libdecor_state_new: *const @TypeOf(h.libdecor_state_new),
    libdecor_state_free: *const @TypeOf(h.libdecor_state_free),
    libdecor_frame_commit: *const @TypeOf(h.libdecor_frame_commit),
    libdecor_frame_set_title: *const @TypeOf(h.libdecor_frame_set_title),
    libdecor_frame_set_maximized: *const @TypeOf(h.libdecor_frame_set_maximized),
    libdecor_frame_unset_maximized: *const @TypeOf(h.libdecor_frame_unset_maximized),
    libdecor_frame_set_fullscreen: *const @TypeOf(h.libdecor_frame_set_fullscreen),
    libdecor_frame_unset_fullscreen: *const @TypeOf(h.libdecor_frame_unset_fullscreen),
    wl_egl_window_create: *const @TypeOf(h.wl_egl_window_create),
    wl_egl_window_destroy: *const @TypeOf(h.wl_egl_window_destroy),
    wl_egl_window_resize: *const @TypeOf(h.wl_egl_window_resize),
    eglGetDisplay: *const @TypeOf(h.eglGetDisplay),
    eglInitialize: *const @TypeOf(h.eglInitialize),
    eglTerminate: *const @TypeOf(h.eglTerminate),
    eglChooseConfig: *const @TypeOf(h.eglChooseConfig),
    eglCreateWindowSurface: *const @TypeOf(h.eglCreateWindowSurface),
    eglDestroySurface: *const @TypeOf(h.eglDestroySurface),
    eglCreateContext: *const @TypeOf(h.eglCreateContext),
    eglDestroyContext: *const @TypeOf(h.eglDestroyContext),
    eglMakeCurrent: *const @TypeOf(h.eglMakeCurrent),
    eglSwapBuffers: *const @TypeOf(h.eglSwapBuffers),
    eglSwapInterval: *const @TypeOf(h.eglSwapInterval),
    eglGetProcAddress: *const @TypeOf(h.eglGetProcAddress),
} = undefined;

var libwayland_client: std.DynLib = undefined;
var libxkbcommon: std.DynLib = undefined;
var libdecor: std.DynLib = undefined;
var libwayland_egl: std.DynLib = undefined;
var libEGL: std.DynLib = undefined;

pub var display: *h.wl_display = undefined;
var registry: *h.wl_registry = undefined;
var compositor: ?*h.wl_compositor = null;
var seat: ?*h.wl_seat = null;
var keyboard: ?*h.wl_keyboard = null;
var pointer: ?*h.wl_pointer = null;
var viewporter: ?*h.wp_viewporter = null;
var fractional_scale_manager: ?*h.wp_fractional_scale_manager_v1 = null;
var cursor_shape_manager: ?*h.wp_cursor_shape_manager_v1 = null;
var pointer_constraints: ?*h.zwp_pointer_constraints_v1 = null;
var relative_pointer_manager: ?*h.zwp_relative_pointer_manager_v1 = null;
var data_device_manager: ?*h.wl_data_device_manager = null;
var activation: ?*h.xdg_activation_v1 = null;

var cursor_shape_device: ?*h.wp_cursor_shape_device_v1 = null;
var relative_pointer: ?*h.zwp_relative_pointer_v1 = null;
var data_device: ?*h.wl_data_device = null;
var data_offer: ?*h.wl_data_offer = null;
var data_source: ?*h.wl_data_source = null;

var xkb: *h.xkb_context = undefined;
var keymap: ?*h.xkb_keymap = null;
var xkb_state: ?*h.xkb_state = null;
var compose_state: ?*h.xkb_compose_state = null;

var libdecor_context: *h.libdecor = undefined;

var focus: ?*@This() = null;
var last_serial: u32 = 0;
var pointer_enter_serial: u32 = 0;
var repeat_period: i32 = undefined;
var repeat_delay: i32 = undefined;
var clipboard_text: []const u8 = "";

var egl_display: h.EGLDisplay = undefined;

export var wio_wl_proxy_get_version: *const @TypeOf(h.wl_proxy_get_version) = undefined;
export var wio_wl_proxy_marshal_flags: *const @TypeOf(h.wl_proxy_marshal_flags) = undefined;
export var wio_wl_proxy_add_listener: *const @TypeOf(h.wl_proxy_add_listener) = undefined;
export var wio_wl_proxy_destroy: *const @TypeOf(h.wl_proxy_destroy) = undefined;
export var wio_wl_proxy_set_user_data: *const @TypeOf(h.wl_proxy_set_user_data) = undefined;
export var wio_wl_proxy_get_user_data: *const @TypeOf(h.wl_proxy_get_user_data) = undefined;

pub fn init(options: wio.InitOptions) !void {
    dynlib.load(&c, &.{
        .{ .handle = &libxkbcommon, .name = "libxkbcommon.so.0", .prefix = "xkb" },
        .{ .handle = &libdecor, .name = "libdecor-0.so.0", .prefix = "libdecor" },
        .{ .handle = &libwayland_egl, .name = "libwayland-egl.so.1", .prefix = "wl_egl", .predicate = options.opengl },
        .{ .handle = &libEGL, .name = "libEGL.so.1", .prefix = "egl", .predicate = options.opengl },
        .{ .handle = &libwayland_client, .name = "libwayland-client.so.0" },
    }) catch return error.Unavailable;
    errdefer libwayland_client.close();
    errdefer libxkbcommon.close();
    errdefer if (options.opengl) libwayland_egl.close();
    errdefer if (options.opengl) libEGL.close();

    wio_wl_proxy_get_version = c.wl_proxy_get_version;
    wio_wl_proxy_marshal_flags = c.wl_proxy_marshal_flags;
    wio_wl_proxy_add_listener = c.wl_proxy_add_listener;
    wio_wl_proxy_destroy = c.wl_proxy_destroy;
    wio_wl_proxy_set_user_data = c.wl_proxy_set_user_data;
    wio_wl_proxy_get_user_data = c.wl_proxy_get_user_data;

    display = c.wl_display_connect(null) orelse return error.Unavailable;
    errdefer c.wl_display_disconnect(display);

    xkb = c.xkb_context_new(h.XKB_CONTEXT_NO_FLAGS) orelse return error.Unexpected;
    errdefer c.xkb_context_unref(xkb);

    const locale = std.c.getenv("LC_ALL") orelse std.c.getenv("LC_CTYPE") orelse std.c.getenv("LANG") orelse "C";
    const compose_table = c.xkb_compose_table_new_from_locale(xkb, locale, h.XKB_COMPOSE_COMPILE_NO_FLAGS);
    defer c.xkb_compose_table_unref(compose_table);
    if (compose_table) |_| compose_state = c.xkb_compose_state_new(compose_table, h.XKB_COMPOSE_STATE_NO_FLAGS);

    registry = h.wl_display_get_registry(display) orelse return error.Unexpected;
    errdefer h.wl_registry_destroy(registry);
    _ = h.wl_registry_add_listener(registry, &registry_listener, null);

    _ = c.wl_display_roundtrip(display);
    errdefer destroyProxies();
    if (compositor == null or seat == null or viewporter == null or data_device_manager == null) return error.Unexpected;

    data_device = h.wl_data_device_manager_get_data_device(data_device_manager, seat) orelse return error.Unexpected;
    _ = h.wl_data_device_add_listener(data_device, &data_device_listener, null);

    libdecor_context = c.libdecor_new(display, &libdecor_interface) orelse return error.Unexpected;
    errdefer c.libdecor_unref(libdecor_context);

    if (options.opengl) {
        egl_display = c.eglGetDisplay(display) orelse {
            log.err("{s} failed", .{"eglGetDisplay"});
            return error.Unexpected;
        };
        if (c.eglInitialize(egl_display, null, null) == h.EGL_FALSE) {
            log.err("{s} failed", .{"eglInitialize"});
            return error.Unexpected;
        }
    }
}

pub fn deinit() void {
    if (wio.init_options.opengl) {
        _ = c.eglTerminate(egl_display);
        libEGL.close();
        libwayland_egl.close();
    }

    wio.allocator.free(clipboard_text);

    c.libdecor_unref(libdecor_context);
    libdecor.close();

    c.xkb_compose_state_unref(compose_state);
    c.xkb_state_unref(xkb_state);
    c.xkb_keymap_unref(keymap);
    c.xkb_context_unref(xkb);
    libxkbcommon.close();

    destroyProxies();
    c.wl_display_disconnect(display);
    libwayland_client.close();
}

fn destroyProxies() void {
    if (data_source) |_| h.wl_data_source_destroy(data_source);
    if (data_offer) |_| h.wl_data_offer_destroy(data_offer);
    if (data_device) |_| h.wl_data_device_destroy(data_device);
    if (relative_pointer) |_| h.zwp_relative_pointer_v1_destroy(relative_pointer);
    if (cursor_shape_device) |_| h.wp_cursor_shape_device_v1_destroy(cursor_shape_device);
    if (activation) |_| h.xdg_activation_v1_destroy(activation);
    if (data_device_manager) |_| h.wl_data_device_manager_destroy(data_device_manager);
    if (relative_pointer_manager) |_| h.zwp_relative_pointer_manager_v1_destroy(relative_pointer_manager);
    if (pointer_constraints) |_| h.zwp_pointer_constraints_v1_destroy(pointer_constraints);
    if (cursor_shape_manager) |_| h.wp_cursor_shape_manager_v1_destroy(cursor_shape_manager);
    if (fractional_scale_manager) |_| h.wp_fractional_scale_manager_v1_destroy(fractional_scale_manager);
    if (viewporter) |_| h.wp_viewporter_destroy(viewporter);
    if (pointer) |_| h.wl_pointer_destroy(pointer);
    if (keyboard) |_| h.wl_keyboard_destroy(keyboard);
    if (seat) |_| h.wl_seat_destroy(seat);
    if (compositor) |_| h.wl_compositor_destroy(compositor);
    h.wl_registry_destroy(registry);
}

pub fn update() void {
    _ = c.wl_display_dispatch(display);
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = style;
    _ = title;
    _ = message;
}

events: std.fifo.LinearFifo(wio.Event, .Dynamic),
surface: *h.wl_surface,
viewport: *h.wp_viewport,
frame: *h.libdecor_frame,
configured: bool = false,
fractional_scale: ?*h.wp_fractional_scale_v1 = null,
locked_pointer: ?*h.zwp_locked_pointer_v1 = null,
egl_window: ?*h.wl_egl_window = null,
egl_surface: h.EGLSurface = null,
egl_context: h.EGLContext = null,
repeat_key: u32 = 0,
repeat_timestamp: i64 = undefined,
repeat_ignore: bool = false,
size: wio.Size,
scale: f32,
cursor: u32 = undefined,
cursor_mode: wio.CursorMode,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());

    const surface = h.wl_compositor_create_surface(compositor) orelse return error.Unexpected;
    errdefer h.wl_surface_destroy(surface);
    h.wl_surface_set_user_data(surface, self);

    const viewport = h.wp_viewporter_get_viewport(viewporter, surface) orelse return error.Unexpected;
    errdefer h.wp_viewport_destroy(viewport);

    const frame = c.libdecor_decorate(libdecor_context, surface, &libdecor_frame_interface, self) orelse return error.Unexpected;

    self.* = .{
        .events = .init(wio.allocator),
        .surface = surface,
        .viewport = viewport,
        .frame = frame,
        .size = options.size,
        .scale = options.scale,
        .cursor_mode = options.cursor_mode,
    };

    if (fractional_scale_manager) |_| {
        if (h.wp_fractional_scale_manager_v1_get_fractional_scale(fractional_scale_manager, surface)) |fractional_scale| {
            self.fractional_scale = fractional_scale;
            _ = h.wp_fractional_scale_v1_add_listener(fractional_scale, &fractional_scale_listener, self);
        }
    }

    try self.events.write(&.{
        .visible,
        .{ .scale = options.scale },
    });

    self.setTitle(options.title);
    self.setMode(options.mode);
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);

    h.wl_surface_commit(surface);
    while (!self.configured) {
        if (c.wl_display_dispatch(display) == -1) return error.Unexpected;
    }

    return self;
}

pub fn destroy(self: *@This()) void {
    if (focus == self) focus = null;
    if (self.egl_context) |_| _ = c.eglDestroyContext(egl_display, self.egl_context);
    if (self.egl_surface) |_| _ = c.eglDestroySurface(egl_display, self.egl_surface);
    if (self.egl_window) |_| c.wl_egl_window_destroy(self.egl_window);
    if (self.fractional_scale) |_| h.wp_fractional_scale_v1_destroy(self.fractional_scale);
    self.events.deinit();
    c.libdecor_frame_unref(self.frame);
    h.wp_viewport_destroy(self.viewport);
    h.wl_surface_destroy(self.surface);
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    const maybe_event = self.events.readItem();

    if (!self.repeat_ignore) {
        const now = std.time.milliTimestamp();
        if (self.repeat_key != 0 and now > self.repeat_timestamp) {
            self.pushKeyEvent(self.repeat_key, .button_repeat);
            self.repeat_timestamp = now + repeat_period;
            self.repeat_ignore = true;
        }
    } else {
        if (maybe_event) |event| {
            switch (event) {
                .button_repeat, .char => {},
                else => self.repeat_ignore = false,
            }
        } else {
            self.repeat_ignore = false;
        }
    }

    return maybe_event;
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_z = wio.allocator.dupeZ(u8, title) catch return;
    defer wio.allocator.free(title_z);
    c.libdecor_frame_set_title(self.frame, title_z);
}

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    if (mode != .fullscreen) c.libdecor_frame_unset_fullscreen(self.frame);
    switch (mode) {
        .normal => c.libdecor_frame_unset_maximized(self.frame),
        .maximized => c.libdecor_frame_set_maximized(self.frame),
        .fullscreen => c.libdecor_frame_set_fullscreen(self.frame, null),
    }
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    self.cursor = switch (shape) {
        .arrow => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT,
        .arrow_busy => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_PROGRESS,
        .busy => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_WAIT,
        .text => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT,
        .hand => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER,
        .crosshair => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR,
        .forbidden => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NOT_ALLOWED,
        .move => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE,
        .size_ns => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NS_RESIZE,
        .size_ew => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_EW_RESIZE,
        .size_nesw => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NESW_RESIZE,
        .size_nwse => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NWSE_RESIZE,
    };
    if (focus == self) self.applyCursor();
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    self.cursor_mode = mode;
    if (focus == self) self.applyCursor();

    if (mode == .relative) {
        if (self.locked_pointer == null) {
            self.locked_pointer = h.zwp_pointer_constraints_v1_lock_pointer(pointer_constraints, self.surface, pointer, null, h.ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
        }
    } else {
        if (self.locked_pointer != null) {
            h.zwp_locked_pointer_v1_destroy(self.locked_pointer);
            self.locked_pointer = null;
        }
    }
}

pub fn requestAttention(self: *@This()) void {
    if (activation == null) return;
    const token = h.xdg_activation_v1_get_activation_token(activation);
    _ = h.xdg_activation_token_v1_add_listener(token, &activation_token_listener, self.surface);
    h.xdg_activation_token_v1_commit(token);
}

pub fn setClipboardText(_: *@This(), text: []const u8) void {
    wio.allocator.free(clipboard_text);
    clipboard_text = wio.allocator.dupe(u8, text) catch "";

    if (data_source) |_| h.wl_data_source_destroy(data_source);
    data_source = h.wl_data_device_manager_create_data_source(data_device_manager);
    _ = h.wl_data_source_add_listener(data_source, &data_source_listener, null);
    h.wl_data_source_offer(data_source, "text/plain;charset=utf-8");
    h.wl_data_device_set_selection(data_device, data_source, last_serial);
}

pub fn getClipboardText(_: *@This(), allocator: std.mem.Allocator) ?[]u8 {
    if (data_offer == null) return null;
    var pipe: [2]i32 = undefined;
    if (std.c.pipe(&pipe) == -1) return null;
    defer _ = std.c.close(pipe[0]);
    h.wl_data_offer_receive(data_offer, "text/plain;charset=utf-8", pipe[1]);
    _ = c.wl_display_roundtrip(display);
    _ = std.c.close(pipe[1]);
    const file = std.fs.File{ .handle = pipe[0] };
    return file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch null;
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    var config: h.EGLConfig = undefined;
    var count: i32 = undefined;
    _ = c.eglChooseConfig(egl_display, &[_]i32{
        h.EGL_RENDERABLE_TYPE, h.EGL_OPENGL_BIT,
        h.EGL_RED_SIZE,        options.red_bits,
        h.EGL_GREEN_SIZE,      options.green_bits,
        h.EGL_BLUE_SIZE,       options.blue_bits,
        h.EGL_ALPHA_SIZE,      options.alpha_bits,
        h.EGL_DEPTH_SIZE,      options.depth_bits,
        h.EGL_STENCIL_SIZE,    options.stencil_bits,
        h.EGL_SAMPLE_BUFFERS,  if (options.samples != 0) 1 else 0,
        h.EGL_SAMPLES,         options.samples,
        h.EGL_NONE,
    }, &config, 1, &count);

    self.egl_window = c.wl_egl_window_create(self.surface, 640, 480);
    self.egl_surface = c.eglCreateWindowSurface(egl_display, config, self.egl_window, null);
    self.egl_context = c.eglCreateContext(egl_display, config, h.EGL_NO_CONTEXT, &[_]i32{
        h.EGL_CONTEXT_MAJOR_VERSION, 2,
        h.EGL_NONE,
    });
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = c.eglMakeCurrent(egl_display, self.egl_surface, self.egl_surface, self.egl_context);
}

pub fn swapBuffers(self: *@This()) void {
    _ = c.eglSwapBuffers(egl_display, self.egl_surface);
}

pub fn swapInterval(_: *@This(), interval: i32) void {
    _ = c.eglSwapInterval(egl_display, interval);
}

pub fn createSurface(self: @This(), instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
    const VkWaylandSurfaceCreateInfoKHR = extern struct {
        sType: i32 = 1000006000,
        pNext: ?*const anyopaque = null,
        flags: u32 = 0,
        display: *h.wl_display,
        surface: *h.wl_surface,
    };

    const vkCreateWaylandSurfaceKHR: *const fn (usize, *const VkWaylandSurfaceCreateInfoKHR, ?*const anyopaque, *u64) callconv(.c) i32 =
        @ptrCast(unix.vkGetInstanceProcAddr(instance, "vkCreateWaylandSurfaceKHR"));

    return vkCreateWaylandSurfaceKHR(
        instance,
        &.{
            .display = display,
            .surface = self.surface,
        },
        allocator,
        surface,
    );
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

pub fn getVulkanExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_wayland_surface" };
}

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch return;
}

fn pushKeyEvent(self: *@This(), key: u32, comptime event: wio.EventType) void {
    if (keyToButton(key)) |button| {
        self.pushEvent(@unionInit(wio.Event, @tagName(event), button));
    }

    var sym = c.xkb_state_key_get_one_sym(xkb_state, key + 8);
    if (compose_state) |_| {
        if (c.xkb_compose_state_feed(compose_state, sym) == h.XKB_COMPOSE_FEED_ACCEPTED) {
            switch (c.xkb_compose_state_get_status(compose_state)) {
                h.XKB_COMPOSE_COMPOSED => sym = c.xkb_compose_state_get_one_sym(compose_state),
                h.XKB_COMPOSE_COMPOSING, h.XKB_COMPOSE_CANCELLED => return,
                else => {},
            }
        }
    }
    const char: u21 = @intCast(c.xkb_keysym_to_utf32(sym));
    if (char >= ' ' and char != 0x7F) self.pushEvent(.{ .char = char });
}

fn applyCursor(self: *@This()) void {
    if (self.cursor_mode == .normal) {
        if (cursor_shape_device) |_| {
            h.wp_cursor_shape_device_v1_set_shape(cursor_shape_device, pointer_enter_serial, self.cursor);
        }
    } else {
        h.wl_pointer_set_cursor(pointer, pointer_enter_serial, null, 0, 0);
    }
}

const registry_listener = h.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn registryGlobal(_: ?*anyopaque, _: ?*h.wl_registry, name: u32, interface_ptr: [*c]const u8, _: u32) callconv(.c) void {
    const interface = std.mem.sliceTo(interface_ptr, 0);
    if (std.mem.eql(u8, interface, "wl_compositor")) {
        compositor = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_compositor_interface, 3));
    } else if (std.mem.eql(u8, interface, "wl_seat")) {
        seat = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_seat_interface, 4));
        _ = h.wl_seat_add_listener(seat, &seat_listener, null);
    } else if (std.mem.eql(u8, interface, "wp_viewporter")) {
        viewporter = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_viewporter_interface, 1));
    } else if (std.mem.eql(u8, interface, "wp_fractional_scale_manager_v1")) {
        fractional_scale_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_fractional_scale_manager_v1_interface, 1));
    } else if (std.mem.eql(u8, interface, "wp_cursor_shape_manager_v1")) {
        cursor_shape_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_cursor_shape_manager_v1_interface, 1));
    } else if (std.mem.eql(u8, interface, "zwp_pointer_constraints_v1")) {
        pointer_constraints = @ptrCast(h.wl_registry_bind(registry, name, &h.zwp_pointer_constraints_v1_interface, 1));
    } else if (std.mem.eql(u8, interface, "zwp_relative_pointer_manager_v1")) {
        relative_pointer_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.zwp_relative_pointer_manager_v1_interface, 1));
    } else if (std.mem.eql(u8, interface, "wl_data_device_manager")) {
        data_device_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_data_device_manager_interface, 1));
    } else if (std.mem.eql(u8, interface, "xdg_activation_v1")) {
        activation = @ptrCast(h.wl_registry_bind(registry, name, &h.xdg_activation_v1_interface, 1));
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*h.wl_registry, _: u32) callconv(.c) void {}

const seat_listener = h.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn seatCapabilities(_: ?*anyopaque, _: ?*h.wl_seat, capabilities: u32) callconv(.c) void {
    if (relative_pointer) |_| {
        h.zwp_relative_pointer_v1_destroy(relative_pointer);
        relative_pointer = null;
    }
    if (cursor_shape_device) |_| {
        h.wp_cursor_shape_device_v1_destroy(cursor_shape_device);
        cursor_shape_device = null;
    }
    if (pointer) |_| {
        h.wl_pointer_release(pointer);
        pointer = null;
    }
    if (keyboard) |_| {
        h.wl_keyboard_release(keyboard);
        keyboard = null;
    }

    if (capabilities & h.WL_SEAT_CAPABILITY_KEYBOARD != 0) {
        keyboard = h.wl_seat_get_keyboard(seat);
        _ = h.wl_keyboard_add_listener(keyboard, &keyboard_listener, null);
    }
    if (capabilities & h.WL_SEAT_CAPABILITY_POINTER != 0) {
        pointer = h.wl_seat_get_pointer(seat);
        _ = h.wl_pointer_add_listener(pointer, &pointer_listener, null);
        if (cursor_shape_manager) |_| {
            cursor_shape_device = h.wp_cursor_shape_manager_v1_get_pointer(cursor_shape_manager, pointer);
        }
        if (relative_pointer_manager) |_| {
            relative_pointer = h.zwp_relative_pointer_manager_v1_get_relative_pointer(relative_pointer_manager, pointer);
            _ = h.zwp_relative_pointer_v1_add_listener(relative_pointer, &relative_pointer_listener, null);
        }
    }
}

fn seatName(_: ?*anyopaque, _: ?*h.wl_seat, _: [*c]const u8) callconv(.c) void {}

const keyboard_listener = h.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

fn keyboardKeymap(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, fd: i32, size: u32) callconv(.c) void {
    defer _ = std.c.close(fd);
    c.xkb_keymap_unref(keymap);
    c.xkb_state_unref(xkb_state);

    const string = std.c.mmap(null, size, std.c.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
    defer _ = std.c.munmap(@alignCast(string), size);

    keymap = c.xkb_keymap_new_from_string(xkb, @ptrCast(string), h.XKB_KEYMAP_FORMAT_TEXT_V1, h.XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_state = c.xkb_state_new(keymap);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface, _: ?*h.wl_array) callconv(.c) void {
    focus = @alignCast(@ptrCast(h.wl_surface_get_user_data(surface)));
}

fn keyboardLeave(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface) callconv(.c) void {
    if (focus) |window| {
        if (window.surface == surface) {
            focus = null;
            window.repeat_key = 0;
        }
    }
    if (compose_state) |_| c.xkb_compose_state_reset(compose_state);
}

fn keyboardKey(_: ?*anyopaque, _: ?*h.wl_keyboard, serial: u32, _: u32, key: u32, state: u32) callconv(.c) void {
    last_serial = serial;
    if (focus) |window| {
        if (state == h.WL_KEYBOARD_KEY_STATE_PRESSED) {
            window.pushKeyEvent(key, .button_press);
            window.repeat_key = key;
            window.repeat_timestamp = std.time.milliTimestamp() + repeat_delay;
        } else {
            if (keyToButton(key)) |button| {
                window.pushEvent(.{ .button_release = button });
            }
            if (key == window.repeat_key) {
                window.repeat_key = 0;
            }
        }
    }
}

fn keyboardModifiers(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, _: u32) callconv(.c) void {
    _ = c.xkb_state_update_mask(xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, 0);
}

fn keyboardRepeatInfo(_: ?*anyopaque, _: ?*h.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    repeat_period = @divTrunc(1000, rate);
    repeat_delay = delay;
}

const pointer_listener = h.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
};

fn pointerEnter(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, surface: ?*h.wl_surface, _: i32, _: i32) callconv(.c) void {
    pointer_enter_serial = serial;
    if (@as(?*@This(), @alignCast(@ptrCast(h.wl_surface_get_user_data(surface))))) |window| {
        window.applyCursor();
    }
}

fn pointerLeave(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, _: ?*h.wl_surface) callconv(.c) void {}

fn pointerMotion(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, surface_x: i32, surface_y: i32) callconv(.c) void {
    if (focus) |window| window.pushEvent(.{ .mouse = .{ .x = @intCast(surface_x >> 8), .y = @intCast(surface_y >> 8) } });
}

fn pointerButton(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, _: u32, button: u32, state: u32) callconv(.c) void {
    last_serial = serial;
    if (focus) |window| {
        const wio_button: wio.Button = switch (button) {
            0x110 => .mouse_left,
            0x111 => .mouse_right,
            0x112 => .mouse_middle,
            0x113 => .mouse_back,
            0x114 => .mouse_forward,
            else => return,
        };
        window.pushEvent(if (state == h.WL_POINTER_BUTTON_STATE_PRESSED) .{ .button_press = wio_button } else .{ .button_release = wio_button });
    }
}

fn pointerAxis(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, axis: u32, value: i32) callconv(.c) void {
    if (focus) |window| {
        const float = @as(f32, @floatFromInt(value)) / 2560;
        switch (axis) {
            h.WL_POINTER_AXIS_VERTICAL_SCROLL => window.pushEvent(.{ .scroll_vertical = float }),
            h.WL_POINTER_AXIS_HORIZONTAL_SCROLL => window.pushEvent(.{ .scroll_horizontal = float }),
            else => {},
        }
    }
}

const relative_pointer_listener = h.zwp_relative_pointer_v1_listener{
    .relative_motion = relativePointerMotion,
};

fn relativePointerMotion(_: ?*anyopaque, _: ?*h.zwp_relative_pointer_v1, _: u32, _: u32, _: i32, _: i32, dx_unaccel: i32, dy_unaccel: i32) callconv(.c) void {
    if (focus) |window| {
        if (window.cursor_mode == .relative) {
            window.pushEvent(.{ .mouse_relative = .{ .x = @intCast(dx_unaccel >> 8), .y = @intCast(dy_unaccel >> 8) } });
        }
    }
}

const fractional_scale_listener = h.wp_fractional_scale_v1_listener{
    .preferred_scale = fractionalScalePreferredScale,
};

fn fractionalScalePreferredScale(data: ?*anyopaque, _: ?*h.wp_fractional_scale_v1, scale: u32) callconv(.c) void {
    const self: *@This() = @alignCast(@ptrCast(data orelse return));
    self.scale = @floatFromInt(scale);
    self.scale /= 120;
    self.pushEvent(.{ .scale = self.scale });
}

const data_device_listener = h.wl_data_device_listener{
    .data_offer = dataDeviceDataOffer,
    .enter = dataDeviceEnter,
    .leave = dataDeviceLeave,
    .motion = dataDeviceMotion,
    .drop = dataDeviceDrop,
    .selection = dataDeviceSelection,
};

fn dataDeviceDataOffer(_: ?*anyopaque, _: ?*h.wl_data_device, _: ?*h.wl_data_offer) callconv(.c) void {}
fn dataDeviceEnter(_: ?*anyopaque, _: ?*h.wl_data_device, _: u32, _: ?*h.wl_surface, _: i32, _: i32, _: ?*h.wl_data_offer) callconv(.c) void {}
fn dataDeviceLeave(_: ?*anyopaque, _: ?*h.wl_data_device) callconv(.c) void {}
fn dataDeviceMotion(_: ?*anyopaque, _: ?*h.wl_data_device, _: u32, _: i32, _: i32) callconv(.c) void {}
fn dataDeviceDrop(_: ?*anyopaque, _: ?*h.wl_data_device) callconv(.c) void {}

fn dataDeviceSelection(_: ?*anyopaque, _: ?*h.wl_data_device, offer: ?*h.wl_data_offer) callconv(.c) void {
    if (data_offer) |_| h.wl_data_offer_destroy(data_offer);
    data_offer = offer;
}

const data_source_listener = h.wl_data_source_listener{
    .target = dataSourceTarget,
    .send = dataSourceSend,
    .cancelled = dataSourceCancelled,
};

fn dataSourceTarget(_: ?*anyopaque, _: ?*h.wl_data_source, _: [*c]const u8) callconv(.c) void {}

fn dataSourceSend(_: ?*anyopaque, _: ?*h.wl_data_source, _: [*c]const u8, fd: i32) callconv(.c) void {
    defer _ = std.c.close(fd);
    const file = std.fs.File{ .handle = fd };
    file.writeAll(clipboard_text) catch {};
}

fn dataSourceCancelled(_: ?*anyopaque, _: ?*h.wl_data_source) callconv(.c) void {}

const activation_token_listener = h.xdg_activation_token_v1_listener{
    .done = activationTokenDone,
};

fn activationTokenDone(surface: ?*anyopaque, token: ?*h.xdg_activation_token_v1, string: [*c]const u8) callconv(.c) void {
    h.xdg_activation_v1_activate(activation, string, @ptrCast(surface));
    h.xdg_activation_token_v1_destroy(token);
}

var libdecor_interface = h.libdecor_interface{
    .@"error" = libdecorError,
};

fn libdecorError(_: ?*h.libdecor, _: h.libdecor_error, message: [*c]const u8) callconv(.c) void {
    log.err("{s}", .{message});
}

var libdecor_frame_interface = h.libdecor_frame_interface{
    .configure = frameConfigure,
    .close = frameClose,
    .commit = frameCommit,
    .dismiss_popup = frameDismissPopup,
};

fn frameConfigure(frame: ?*h.libdecor_frame, configuration: ?*h.libdecor_configuration, data: ?*anyopaque) callconv(.c) void {
    const self: *@This() = @alignCast(@ptrCast(data));
    self.configured = true;

    var mode = wio.WindowMode.normal;
    var focused = false;

    var window_state: h.libdecor_window_state = 0;
    if (c.libdecor_configuration_get_window_state(configuration, &window_state)) {
        if (window_state & h.LIBDECOR_WINDOW_STATE_ACTIVE != 0) focused = true;
        if (window_state & h.LIBDECOR_WINDOW_STATE_MAXIMIZED != 0) mode = .maximized;
        if (window_state & h.LIBDECOR_WINDOW_STATE_FULLSCREEN != 0) mode = .fullscreen;
    }

    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!c.libdecor_configuration_get_content_size(configuration, frame, &width, &height)) {
        width = self.size.width;
        height = self.size.height;
    }
    const size = wio.Size{ .width = @intCast(width), .height = @intCast(height) };
    const framebuffer = size.multiply(self.scale);

    h.wp_viewport_set_source(self.viewport, 0, 0, @as(i32, framebuffer.width) << 8, @as(i32, framebuffer.height) << 8);
    h.wp_viewport_set_destination(self.viewport, size.width, size.height);
    if (self.egl_window != null) c.wl_egl_window_resize(self.egl_window, framebuffer.width, framebuffer.height, 0, 0);

    const state = c.libdecor_state_new(width, height);
    defer c.libdecor_state_free(state);
    c.libdecor_frame_commit(frame, state, configuration);

    self.pushEvent(if (focused) .focused else .unfocused);
    self.pushEvent(.{ .mode = mode });
    self.pushEvent(.{ .size = size });
    self.pushEvent(.{ .framebuffer = framebuffer });
}

fn frameClose(_: ?*h.libdecor_frame, data: ?*anyopaque) callconv(.c) void {
    const self: *@This() = @alignCast(@ptrCast(data));
    self.pushEvent(.close);
}

fn frameCommit(_: ?*h.libdecor_frame, _: ?*anyopaque) callconv(.c) void {}
fn frameDismissPopup(_: ?*h.libdecor_frame, _: [*c]const u8, _: ?*anyopaque) callconv(.c) void {}

fn keyToButton(key: u32) ?wio.Button {
    comptime var table: [127]wio.Button = undefined;
    comptime for (&table, 1..) |*ptr, i| {
        ptr.* = switch (i) {
            1 => .escape,
            2 => .@"1",
            3 => .@"2",
            4 => .@"3",
            5 => .@"4",
            6 => .@"5",
            7 => .@"6",
            8 => .@"7",
            9 => .@"8",
            10 => .@"9",
            11 => .@"0",
            12 => .minus,
            13 => .equals,
            14 => .backspace,
            15 => .tab,
            16 => .q,
            17 => .w,
            18 => .e,
            19 => .r,
            20 => .t,
            21 => .y,
            22 => .u,
            23 => .i,
            24 => .o,
            25 => .p,
            26 => .left_bracket,
            27 => .right_bracket,
            28 => .enter,
            29 => .left_control,
            30 => .a,
            31 => .s,
            32 => .d,
            33 => .f,
            34 => .g,
            35 => .h,
            36 => .j,
            37 => .k,
            38 => .l,
            39 => .semicolon,
            40 => .apostrophe,
            41 => .grave,
            42 => .left_shift,
            43 => .backslash,
            44 => .z,
            45 => .x,
            46 => .c,
            47 => .v,
            48 => .b,
            49 => .n,
            50 => .m,
            51 => .comma,
            52 => .dot,
            53 => .slash,
            54 => .right_shift,
            55 => .kp_star,
            56 => .left_alt,
            57 => .space,
            58 => .caps_lock,
            59 => .f1,
            60 => .f2,
            61 => .f3,
            62 => .f4,
            63 => .f5,
            64 => .f6,
            65 => .f7,
            66 => .f8,
            67 => .f9,
            68 => .f10,
            69 => .num_lock,
            70 => .scroll_lock,
            71 => .kp_7,
            72 => .kp_8,
            73 => .kp_9,
            74 => .kp_minus,
            75 => .kp_4,
            76 => .kp_5,
            77 => .kp_6,
            78 => .kp_plus,
            79 => .kp_1,
            80 => .kp_2,
            81 => .kp_3,
            82 => .kp_0,
            83 => .kp_dot,
            86 => .iso_backslash,
            87 => .f11,
            88 => .f12,
            89 => .international1,
            92 => .international4,
            93 => .international2,
            94 => .international5,
            96 => .kp_enter,
            97 => .right_control,
            98 => .kp_slash,
            99 => .print_screen,
            100 => .right_alt,
            102 => .home,
            103 => .up,
            104 => .page_up,
            105 => .left,
            106 => .right,
            107 => .end,
            108 => .down,
            109 => .page_down,
            110 => .insert,
            111 => .delete,
            117 => .kp_equals,
            119 => .pause,
            121 => .kp_comma,
            122 => .lang1,
            123 => .lang2,
            124 => .international3,
            125 => .left_gui,
            126 => .right_gui,
            127 => .application,
            else => .mouse_left,
        };
    };
    return if (key > 0 and key <= table.len and table[key - 1] != .mouse_left) table[key - 1] else null;
}

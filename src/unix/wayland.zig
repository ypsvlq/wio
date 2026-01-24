const std = @import("std");
const build_options = @import("build_options");
const wio = @import("../wio.zig");
const internal = @import("../wio.internal.zig");
const unix = @import("../unix.zig");
const DynLib = @import("DynLib.zig");
const log = std.log.scoped(.wio);
const h = @cImport({
    if (build_options.system_integration) {} else @cInclude("wio-wayland.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("viewporter-client-protocol.h");
    @cInclude("fractional-scale-v1-client-protocol.h");
    @cInclude("text-input-v3-client-protocol.h");
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

var imports: extern struct {
    wl_display_connect: *const @TypeOf(h.wl_display_connect),
    wl_display_disconnect: *const @TypeOf(h.wl_display_disconnect),
    wl_display_get_fd: *const @TypeOf(h.wl_display_get_fd),
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
    eglGetError: *const @TypeOf(h.eglGetError),
    eglInitialize: *const @TypeOf(h.eglInitialize),
    eglTerminate: *const @TypeOf(h.eglTerminate),
    eglBindAPI: *const @TypeOf(h.eglBindAPI),
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
const c = if (build_options.system_integration) h else &imports;

var libwayland_client: DynLib = undefined;
var libxkbcommon: DynLib = undefined;
var libdecor: DynLib = undefined;
var libwayland_egl: DynLib = undefined;
var libEGL: DynLib = undefined;

pub var display: *h.wl_display = undefined;
var registry: *h.wl_registry = undefined;
var compositor: ?*h.wl_compositor = null;
var seat: ?*h.wl_seat = null;
var keyboard: ?*h.wl_keyboard = null;
var pointer: ?*h.wl_pointer = null;
var touch: ?*h.wl_touch = null;
var viewporter: ?*h.wp_viewporter = null;
var fractional_scale_manager: ?*h.wp_fractional_scale_manager_v1 = null;
var text_input_manager: ?*h.zwp_text_input_manager_v3 = null;
var cursor_shape_manager: ?*h.wp_cursor_shape_manager_v1 = null;
var pointer_constraints: ?*h.zwp_pointer_constraints_v1 = null;
var relative_pointer_manager: ?*h.zwp_relative_pointer_manager_v1 = null;
var data_device_manager: ?*h.wl_data_device_manager = null;
var activation: ?*h.xdg_activation_v1 = null;

var text_input: ?*h.zwp_text_input_v3 = null;
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

var windows: std.AutoHashMapUnmanaged(*Window, void) = .empty;
pub var focus: ?*Window = null;
var last_serial: u32 = 0;
var pointer_enter_serial: u32 = 0;
var pointer_surface: ?*h.wl_surface = null;
pub var repeat_period: i32 = 0;
var repeat_delay: i32 = undefined;
var preedit_string: std.ArrayList(u8) = .empty;
var preedit_cursors: [2]i32 = .{ 0, 0 };
var preedit_active = false;
var commit_string: std.ArrayList(u8) = .empty;
var touch_ids: std.StaticBitSet(256) = .initEmpty();
var touch_info: std.AutoHashMapUnmanaged(i32, struct { public_id: u8, window: *Window }) = .empty;
var clipboard_text: []const u8 = "";

var egl_display: h.EGLDisplay = undefined;

const exports = if (!build_options.system_integration) struct {
    export var wio_wl_proxy_get_version: *const @TypeOf(h.wl_proxy_get_version) = undefined;
    export var wio_wl_proxy_marshal_flags: *const @TypeOf(h.wl_proxy_marshal_flags) = undefined;
    export var wio_wl_proxy_add_listener: *const @TypeOf(h.wl_proxy_add_listener) = undefined;
    export var wio_wl_proxy_destroy: *const @TypeOf(h.wl_proxy_destroy) = undefined;
    export var wio_wl_proxy_set_user_data: *const @TypeOf(h.wl_proxy_set_user_data) = undefined;
    export var wio_wl_proxy_get_user_data: *const @TypeOf(h.wl_proxy_get_user_data) = undefined;
} else void;

pub fn init() !bool {
    DynLib.load(&imports, &.{
        .{ .handle = &libwayland_client, .name = "libwayland-client.so.0", .prefix = "wl", .exclude = "wl_egl" },
        .{ .handle = &libxkbcommon, .name = "libxkbcommon.so.0", .prefix = "xkb" },
        .{ .handle = &libdecor, .name = "libdecor-0.so.0", .prefix = "libdecor" },
    }) catch return false;
    errdefer libwayland_client.close();
    errdefer libxkbcommon.close();
    errdefer libdecor.close();

    if (build_options.opengl) {
        DynLib.load(&imports, &.{
            .{ .handle = &libwayland_egl, .name = "libwayland-egl.so.1", .prefix = "wl_egl" },
            .{ .handle = &libEGL, .name = "libEGL.so.1", .prefix = "egl" },
        }) catch return false;
    }
    errdefer if (build_options.opengl) libwayland_egl.close();
    errdefer if (build_options.opengl) libEGL.close();

    if (!build_options.system_integration) {
        exports.wio_wl_proxy_get_version = c.wl_proxy_get_version;
        exports.wio_wl_proxy_marshal_flags = c.wl_proxy_marshal_flags;
        exports.wio_wl_proxy_add_listener = c.wl_proxy_add_listener;
        exports.wio_wl_proxy_destroy = c.wl_proxy_destroy;
        exports.wio_wl_proxy_set_user_data = c.wl_proxy_set_user_data;
        exports.wio_wl_proxy_get_user_data = c.wl_proxy_get_user_data;
    }

    display = c.wl_display_connect(null) orelse return false;
    errdefer c.wl_display_disconnect(display);
    try unix.pollfds.append(internal.allocator, .{ .fd = c.wl_display_get_fd(display), .events = std.c.POLL.IN, .revents = undefined });

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
    if (compositor == null or seat == null) return error.Unexpected;

    libdecor_context = c.libdecor_new(display, &libdecor_interface) orelse return error.Unexpected;
    errdefer c.libdecor_unref(libdecor_context);

    if (text_input_manager) |_| {
        text_input = h.zwp_text_input_manager_v3_get_text_input(text_input_manager, seat);
        if (text_input) |_| {
            _ = h.zwp_text_input_v3_add_listener(text_input, &text_input_listener, null);
        }
    }

    if (data_device_manager) |_| {
        data_device = h.wl_data_device_manager_get_data_device(data_device_manager, seat);
        if (data_device) |_| {
            _ = h.wl_data_device_add_listener(data_device, &data_device_listener, null);
        }
    }

    if (build_options.opengl) {
        egl_display = c.eglGetDisplay(display) orelse return logEglError("eglGetDisplay");
        if (c.eglInitialize(egl_display, null, null) == h.EGL_FALSE) return logEglError("eglInitialize");
    }

    return true;
}

pub fn deinit() void {
    if (build_options.opengl) {
        _ = c.eglTerminate(egl_display);
        libEGL.close();
        libwayland_egl.close();
    }

    internal.allocator.free(clipboard_text);
    touch_info.deinit(internal.allocator);
    commit_string.deinit(internal.allocator);
    preedit_string.deinit(internal.allocator);
    windows.deinit(internal.allocator);

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
    if (text_input) |_| h.zwp_text_input_v3_destroy(text_input);
    if (activation) |_| h.xdg_activation_v1_destroy(activation);
    if (data_device_manager) |_| h.wl_data_device_manager_destroy(data_device_manager);
    if (relative_pointer_manager) |_| h.zwp_relative_pointer_manager_v1_destroy(relative_pointer_manager);
    if (pointer_constraints) |_| h.zwp_pointer_constraints_v1_destroy(pointer_constraints);
    if (cursor_shape_manager) |_| h.wp_cursor_shape_manager_v1_destroy(cursor_shape_manager);
    if (text_input_manager) |_| h.zwp_text_input_manager_v3_destroy(text_input_manager);
    if (fractional_scale_manager) |_| h.wp_fractional_scale_manager_v1_destroy(fractional_scale_manager);
    if (viewporter) |_| h.wp_viewporter_destroy(viewporter);
    if (pointer) |_| h.wl_pointer_destroy(pointer);
    if (keyboard) |_| h.wl_keyboard_destroy(keyboard);
    if (seat) |_| h.wl_seat_destroy(seat);
    if (compositor) |_| h.wl_compositor_destroy(compositor);
    h.wl_registry_destroy(registry);
}

pub fn update() void {
    _ = c.wl_display_roundtrip(display);
}

pub fn createWindow(options: wio.CreateWindowOptions) !*Window {
    const self = try internal.allocator.create(Window);

    const surface = h.wl_compositor_create_surface(compositor) orelse return error.Unexpected;
    errdefer h.wl_surface_destroy(surface);
    h.wl_surface_set_user_data(surface, self);

    const frame = c.libdecor_decorate(libdecor_context, surface, &libdecor_frame_interface, self) orelse return error.Unexpected;
    errdefer c.libdecor_frame_unref(frame);

    self.* = .{
        .events = .init(),
        .surface = surface,
        .frame = frame,
        .size = options.size,
        .cursor_mode = options.cursor_mode,
    };

    if (viewporter) |_| {
        self.viewport = h.wp_viewporter_get_viewport(viewporter, surface);
    }
    errdefer if (self.viewport) |_| h.wp_viewport_destroy(self.viewport);

    if (self.viewport) |_| {
        if (fractional_scale_manager) |_| {
            if (h.wp_fractional_scale_manager_v1_get_fractional_scale(fractional_scale_manager, surface)) |fractional_scale| {
                self.fractional_scale = fractional_scale;
                _ = h.wp_fractional_scale_v1_add_listener(fractional_scale, &fractional_scale_listener, self);
            }
        }
    }
    errdefer if (self.fractional_scale) |_| h.wp_fractional_scale_v1_destroy(self.fractional_scale);

    self.events.push(.visible);
    if (self.fractional_scale == null) self.events.push(.{ .scale = 1 });

    self.setTitle(options.title);
    self.setMode(options.mode);
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);

    h.wl_surface_commit(surface);
    while (!self.configured) {
        if (c.wl_display_dispatch(display) == -1) return error.Unexpected;
    }

    if (build_options.opengl) {
        if (options.opengl) |opengl| {
            if (c.eglBindAPI(h.EGL_OPENGL_API) == h.EGL_FALSE) return logEglError("eglBindAPI");

            var config: h.EGLConfig = undefined;
            var count: i32 = undefined;
            if (c.eglChooseConfig(egl_display, &[_]i32{
                h.EGL_RENDERABLE_TYPE, h.EGL_OPENGL_BIT,
                h.EGL_RED_SIZE,        opengl.red_bits,
                h.EGL_GREEN_SIZE,      opengl.green_bits,
                h.EGL_BLUE_SIZE,       opengl.blue_bits,
                h.EGL_ALPHA_SIZE,      opengl.alpha_bits,
                h.EGL_DEPTH_SIZE,      opengl.depth_bits,
                h.EGL_STENCIL_SIZE,    opengl.stencil_bits,
                h.EGL_SAMPLE_BUFFERS,  if (opengl.samples != 0) 1 else 0,
                h.EGL_SAMPLES,         opengl.samples,
                h.EGL_NONE,
            }, &config, 1, &count) == h.EGL_FALSE) return logEglError("eglChooseConfig");

            self.egl.window = c.wl_egl_window_create(self.surface, options.size.width, options.size.height);
            self.egl.surface = c.eglCreateWindowSurface(egl_display, config, self.egl.window, null) orelse return logEglError("eglCreateWindowSurface");
            self.egl.context = c.eglCreateContext(egl_display, config, h.EGL_NO_CONTEXT, &[_]i32{
                h.EGL_CONTEXT_MAJOR_VERSION,             opengl.major_version,
                h.EGL_CONTEXT_MINOR_VERSION,             opengl.minor_version,
                h.EGL_CONTEXT_OPENGL_PROFILE_MASK,       if (opengl.profile == .core) h.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT else h.EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT,
                h.EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE, if (opengl.forward_compatible) h.EGL_TRUE else h.EGL_FALSE,
                h.EGL_CONTEXT_OPENGL_DEBUG,              if (opengl.debug) h.EGL_TRUE else h.EGL_FALSE,
                h.EGL_NONE,
            }) orelse return logEglError("eglCreateContext");
        }
    }

    try windows.put(internal.allocator, self, {});
    return self;
}

pub const Window = struct {
    events: internal.EventQueue,
    surface: *h.wl_surface,
    frame: *h.libdecor_frame,
    configured: bool = false,
    viewport: ?*h.wp_viewport = null,
    fractional_scale: ?*h.wp_fractional_scale_v1 = null,
    locked_pointer: ?*h.zwp_locked_pointer_v1 = null,
    repeat_key: u32 = 0,
    repeat_timestamp: i64 = undefined,
    repeat_ignore: bool = false,
    text_options: ?wio.TextInputOptions = null,
    size: wio.Size,
    scale: f32 = 1,
    cursor: u32 = undefined,
    cursor_mode: wio.CursorMode,
    egl: if (build_options.opengl) struct {
        window: ?*h.wl_egl_window = null,
        surface: h.EGLSurface = null,
        context: h.EGLContext = null,
    } else struct {} = .{},

    pub fn destroy(self: *Window) void {
        if (focus == self) focus = null;
        _ = windows.remove(self);

        while (true) {
            var iter = touch_info.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.window == self) {
                    _ = touch_info.remove(entry.key_ptr.*);
                    continue;
                }
            }
            break;
        }

        if (build_options.opengl) {
            if (self.egl.context) |_| _ = c.eglDestroyContext(egl_display, self.egl.context);
            if (self.egl.surface) |_| _ = c.eglDestroySurface(egl_display, self.egl.surface);
            if (self.egl.window) |_| c.wl_egl_window_destroy(self.egl.window);
        }
        if (self.fractional_scale) |_| h.wp_fractional_scale_v1_destroy(self.fractional_scale);
        if (self.viewport) |_| h.wp_viewport_destroy(self.viewport);
        c.libdecor_frame_unref(self.frame);
        h.wl_surface_destroy(self.surface);
        _ = c.wl_display_dispatch(display);

        self.events.deinit();
        internal.allocator.destroy(self);
    }

    pub fn getEvent(self: *Window) ?wio.Event {
        const maybe_event = self.events.pop();

        if (repeat_period > 0) {
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
        }

        return maybe_event;
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        self.text_options = options;
        if (focus == self) {
            if (text_input) |_| {
                h.zwp_text_input_v3_enable(text_input);
                if (options.cursor) |cursor| {
                    h.zwp_text_input_v3_set_cursor_rectangle(text_input, cursor.x, cursor.y, 0, 0);
                }
                h.zwp_text_input_v3_commit(text_input);
            }
        }
    }

    pub fn disableTextInput(self: *Window) void {
        self.text_options = null;
        if (focus == self) {
            if (text_input) |_| {
                h.zwp_text_input_v3_disable(text_input);
                h.zwp_text_input_v3_commit(text_input);
            }
        }
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        const title_z = internal.allocator.dupeZ(u8, title) catch return;
        defer internal.allocator.free(title_z);
        c.libdecor_frame_set_title(self.frame, title_z);
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        if (mode != .fullscreen) c.libdecor_frame_unset_fullscreen(self.frame);
        switch (mode) {
            .normal => c.libdecor_frame_unset_maximized(self.frame),
            .maximized => c.libdecor_frame_set_maximized(self.frame),
            .fullscreen => c.libdecor_frame_set_fullscreen(self.frame, null),
        }
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
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
        if (pointer_surface == self.surface) self.applyCursor();
    }

    pub fn setCursorMode(self: *Window, mode: wio.CursorMode) void {
        self.cursor_mode = mode;
        if (pointer_surface == self.surface) self.applyCursor();
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        self.resize(size, null);
    }

    pub fn setParent(self: *Window, parent: usize) void {
        _ = self;
        _ = parent;
    }

    pub fn requestAttention(self: *Window) void {
        if (activation == null) return;
        const token = h.xdg_activation_v1_get_activation_token(activation);
        _ = h.xdg_activation_token_v1_add_listener(token, &activation_token_listener, self.surface);
        h.xdg_activation_token_v1_commit(token);
    }

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        if (data_device_manager == null or data_device == null) return;

        internal.allocator.free(clipboard_text);
        clipboard_text = internal.allocator.dupe(u8, text) catch "";

        if (data_source) |_| h.wl_data_source_destroy(data_source);
        data_source = h.wl_data_device_manager_create_data_source(data_device_manager);
        _ = h.wl_data_source_add_listener(data_source, &data_source_listener, null);
        h.wl_data_source_offer(data_source, "text/plain;charset=utf-8");
        h.wl_data_device_set_selection(data_device, data_source, last_serial);
    }

    pub fn getClipboardText(_: *Window, allocator: std.mem.Allocator) ?[]u8 {
        if (data_offer == null) return null;
        var pipe: [2]i32 = undefined;
        if (std.c.pipe(&pipe) == -1) return null;
        defer _ = std.c.close(pipe[0]);
        h.wl_data_offer_receive(data_offer, "text/plain;charset=utf-8", pipe[1]);
        _ = c.wl_display_roundtrip(display);
        _ = std.c.close(pipe[1]);
        return readClipboardText(allocator, .{ .handle = pipe[0] }) catch null;
    }

    fn readClipboardText(allocator: std.mem.Allocator, file: std.fs.File) ![]u8 {
        var buffer: [1024]u8 = undefined;
        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(allocator);
        while (true) {
            const count = try file.read(&buffer);
            if (count > 0) {
                try text.appendSlice(allocator, buffer[0..count]);
            } else {
                return text.toOwnedSlice(allocator);
            }
        }
    }

    pub fn makeContextCurrent(self: *Window) void {
        _ = c.eglMakeCurrent(egl_display, self.egl.surface, self.egl.surface, self.egl.context);
    }

    pub fn swapBuffers(self: *Window) void {
        _ = c.eglSwapBuffers(egl_display, self.egl.surface);
    }

    pub fn swapInterval(_: *Window, interval: i32) void {
        _ = c.eglSwapInterval(egl_display, interval);
    }

    pub fn createSurface(self: Window, instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
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

    fn resize(self: *Window, size: wio.Size, configuration: ?*h.libdecor_configuration) void {
        const framebuffer = size.multiply(self.scale);

        if (self.viewport) |_| {
            h.wp_viewport_set_destination(self.viewport, size.width, size.height);
        }

        if (build_options.opengl) if (self.egl.window != null) c.wl_egl_window_resize(self.egl.window, framebuffer.width, framebuffer.height, 0, 0);

        const state = c.libdecor_state_new(size.width, size.height);
        defer c.libdecor_state_free(state);
        c.libdecor_frame_commit(self.frame, state, configuration);

        self.events.push(.{ .size = size });
        self.events.push(.{ .framebuffer = framebuffer });
        self.events.push(.draw);
    }

    fn pushKeyEvent(self: *Window, key: u32, comptime event: wio.EventType) void {
        if (keyToButton(key)) |button| {
            self.events.push(@unionInit(wio.Event, @tagName(event), button));
        }

        if (self.text_options) |_| {
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
            const char = std.math.cast(u21, c.xkb_keysym_to_utf32(sym)) orelse return;
            if (char >= ' ' and char != 0x7F) self.events.push(.{ .char = char });
        }
    }

    fn applyCursor(self: *Window) void {
        if (self.cursor_mode == .normal) {
            if (cursor_shape_device) |_| {
                h.wp_cursor_shape_device_v1_set_shape(cursor_shape_device, pointer_enter_serial, self.cursor);
            }
        } else {
            h.wl_pointer_set_cursor(pointer, pointer_enter_serial, null, 0, 0);
        }

        if (self.locked_pointer) |_| {
            h.zwp_locked_pointer_v1_destroy(self.locked_pointer);
            self.locked_pointer = null;
        }

        if (self.cursor_mode == .relative) {
            if (pointer_constraints) |_| {
                self.locked_pointer = h.zwp_pointer_constraints_v1_lock_pointer(pointer_constraints, self.surface, pointer, null, h.ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
            }
        }
    }
};

pub fn glGetProcAddress(name: [:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

pub fn getVulkanExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_wayland_surface" };
}

fn logEglError(name: []const u8) error{Unexpected} {
    log.err("{s} failed, error 0x{X}", .{ name, c.eglGetError() });
    return error.Unexpected;
}

fn getWindow(surface: ?*h.wl_surface) ?*Window {
    const window: *Window = @ptrCast(@alignCast(h.wl_surface_get_user_data(surface orelse return null) orelse return null));
    return if (windows.contains(window)) window else null;
}

const registry_listener = h.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn registryGlobal(_: ?*anyopaque, _: ?*h.wl_registry, name: u32, interface_ptr: [*c]const u8, version: u32) callconv(.c) void {
    const interface = std.mem.sliceTo(interface_ptr, 0);
    if (std.mem.eql(u8, interface, "wl_compositor")) {
        compositor = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_compositor_interface, @min(version, 3)));
    } else if (std.mem.eql(u8, interface, "wl_seat")) {
        seat = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_seat_interface, @min(version, 4)));
        _ = h.wl_seat_add_listener(seat, &seat_listener, null);
    } else if (std.mem.eql(u8, interface, "wp_viewporter")) {
        viewporter = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_viewporter_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wp_fractional_scale_manager_v1")) {
        fractional_scale_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_fractional_scale_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_text_input_manager_v3")) {
        text_input_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.zwp_text_input_manager_v3_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wp_cursor_shape_manager_v1")) {
        cursor_shape_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_cursor_shape_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_pointer_constraints_v1")) {
        pointer_constraints = @ptrCast(h.wl_registry_bind(registry, name, &h.zwp_pointer_constraints_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_relative_pointer_manager_v1")) {
        relative_pointer_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.zwp_relative_pointer_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wl_data_device_manager")) {
        data_device_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_data_device_manager_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "xdg_activation_v1")) {
        activation = @ptrCast(h.wl_registry_bind(registry, name, &h.xdg_activation_v1_interface, @min(version, 1)));
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*h.wl_registry, _: u32) callconv(.c) void {}

const seat_listener = h.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn seatCapabilities(_: ?*anyopaque, _: ?*h.wl_seat, capabilities: h.wl_seat_capability) callconv(.c) void {
    if (touch) |_| {
        h.wl_touch_destroy(touch);
        touch = null;
        touch_ids = .initEmpty();
        touch_info.clearRetainingCapacity();
    }
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
    if (capabilities & h.WL_SEAT_CAPABILITY_TOUCH != 0) {
        touch = h.wl_seat_get_touch(seat);
        _ = h.wl_touch_add_listener(touch, &touch_listener, null);
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

fn keyboardKeymap(_: ?*anyopaque, _: ?*h.wl_keyboard, _: h.wl_keyboard_keymap_format, fd: i32, size: u32) callconv(.c) void {
    defer _ = std.c.close(fd);
    c.xkb_keymap_unref(keymap);
    c.xkb_state_unref(xkb_state);

    const string = std.c.mmap(null, size, std.c.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
    defer _ = std.c.munmap(@alignCast(string), size);

    keymap = c.xkb_keymap_new_from_string(xkb, @ptrCast(string), h.XKB_KEYMAP_FORMAT_TEXT_V1, h.XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_state = c.xkb_state_new(keymap);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface, _: ?*h.wl_array) callconv(.c) void {
    focus = getWindow(surface);
    if (focus) |window| window.events.push(.focused);
}

fn keyboardLeave(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface) callconv(.c) void {
    if (focus) |window| {
        if (window.surface == surface) {
            focus = null;
            window.repeat_key = 0;
            window.events.push(.unfocused);
        }
    }
    if (compose_state) |_| c.xkb_compose_state_reset(compose_state);
}

fn keyboardKey(_: ?*anyopaque, _: ?*h.wl_keyboard, serial: u32, _: u32, key: u32, state: h.wl_keyboard_key_state) callconv(.c) void {
    last_serial = serial;
    if (focus) |window| {
        if (state == h.WL_KEYBOARD_KEY_STATE_PRESSED) {
            window.pushKeyEvent(key, .button_press);
            if (repeat_period > 0) {
                window.repeat_key = key;
                window.repeat_timestamp = std.time.milliTimestamp() + repeat_delay;
            }
        } else {
            if (keyToButton(key)) |button| {
                window.events.push(.{ .button_release = button });
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
    if (rate > 0) {
        repeat_period = @divTrunc(1000, rate);
        repeat_delay = delay;
    }
}

const pointer_listener = h.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
};

fn pointerEnter(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, surface: ?*h.wl_surface, _: h.wl_fixed_t, _: h.wl_fixed_t) callconv(.c) void {
    pointer_enter_serial = serial;
    pointer_surface = surface;
    if (getWindow(surface)) |window| {
        window.applyCursor();
    }
}

fn pointerLeave(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, _: ?*h.wl_surface) callconv(.c) void {
    pointer_surface = null;
}

fn pointerMotion(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, surface_x: h.wl_fixed_t, surface_y: h.wl_fixed_t) callconv(.c) void {
    if (focus) |window| window.events.push(.{ .mouse = .{ .x = std.math.cast(u16, surface_x >> 8) orelse return, .y = std.math.cast(u16, surface_y >> 8) orelse return } });
}

fn pointerButton(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, _: u32, button: u32, state: h.wl_pointer_button_state) callconv(.c) void {
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
        window.events.push(if (state == h.WL_POINTER_BUTTON_STATE_PRESSED) .{ .button_press = wio_button } else .{ .button_release = wio_button });
    }
}

fn pointerAxis(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, axis: h.wl_pointer_axis, value: h.wl_fixed_t) callconv(.c) void {
    if (focus) |window| {
        const float = @as(f32, @floatFromInt(value)) / 2560;
        switch (axis) {
            h.WL_POINTER_AXIS_VERTICAL_SCROLL => window.events.push(.{ .scroll_vertical = float }),
            h.WL_POINTER_AXIS_HORIZONTAL_SCROLL => window.events.push(.{ .scroll_horizontal = float }),
            else => {},
        }
    }
}

const relative_pointer_listener = h.zwp_relative_pointer_v1_listener{
    .relative_motion = relativePointerMotion,
};

fn relativePointerMotion(_: ?*anyopaque, _: ?*h.zwp_relative_pointer_v1, _: u32, _: u32, _: h.wl_fixed_t, _: h.wl_fixed_t, dx_unaccel: h.wl_fixed_t, dy_unaccel: h.wl_fixed_t) callconv(.c) void {
    if (focus) |window| {
        if (window.cursor_mode == .relative) {
            window.events.push(.{ .mouse_relative = .{ .x = std.math.cast(i16, dx_unaccel >> 8) orelse return, .y = std.math.cast(i16, dy_unaccel >> 8) orelse return } });
        }
    }
}

const touch_listener = h.wl_touch_listener{
    .down = touchDown,
    .up = touchUp,
    .motion = touchMotion,
    .frame = touchFrame,
    .cancel = touchCancel,
};

fn touchDown(_: ?*anyopaque, _: ?*h.wl_touch, serial: u32, _: u32, surface: ?*h.wl_surface, id: i32, x: h.wl_fixed_t, y: h.wl_fixed_t) callconv(.c) void {
    last_serial = serial;
    if (getWindow(surface)) |window| {
        var iter = touch_ids.iterator(.{ .kind = .unset });
        const public_id: u8 = @intCast(iter.next() orelse return);
        touch_info.put(internal.allocator, id, .{ .public_id = public_id, .window = window }) catch return;
        touch_ids.set(public_id);
        window.events.push(.{ .touch = .{ .id = public_id, .x = std.math.cast(u16, x >> 8) orelse return, .y = std.math.cast(u16, y >> 8) orelse return } });
    }
}

fn touchUp(_: ?*anyopaque, _: ?*h.wl_touch, serial: u32, _: u32, id: i32) callconv(.c) void {
    last_serial = serial;
    if (touch_info.get(id)) |info| {
        info.window.events.push(.{ .touch_end = .{ .id = info.public_id, .ignore = false } });
        touch_ids.unset(info.public_id);
    }
}

fn touchMotion(_: ?*anyopaque, _: ?*h.wl_touch, _: u32, id: i32, x: h.wl_fixed_t, y: h.wl_fixed_t) callconv(.c) void {
    if (touch_info.get(id)) |info| {
        info.window.events.push(.{ .touch = .{ .id = info.public_id, .x = std.math.cast(u16, x >> 8) orelse return, .y = std.math.cast(u16, y >> 8) orelse return } });
    }
}

fn touchFrame(_: ?*anyopaque, _: ?*h.wl_touch) callconv(.c) void {}

fn touchCancel(_: ?*anyopaque, _: ?*h.wl_touch) callconv(.c) void {
    var iter = touch_info.valueIterator();
    while (iter.next()) |info| {
        info.window.events.push(.{ .touch_end = .{ .id = info.public_id, .ignore = true } });
    }
    touch_ids = .initEmpty();
    touch_info.clearRetainingCapacity();
}

const fractional_scale_listener = h.wp_fractional_scale_v1_listener{
    .preferred_scale = fractionalScalePreferredScale,
};

fn fractionalScalePreferredScale(data: ?*anyopaque, _: ?*h.wp_fractional_scale_v1, scale: u32) callconv(.c) void {
    const self: *Window = @ptrCast(@alignCast(data orelse return));
    self.scale = @floatFromInt(scale);
    self.scale /= 120;
    self.events.push(.{ .scale = self.scale });
}

const text_input_listener = h.zwp_text_input_v3_listener{
    .enter = textInputEnter,
    .leave = textInputLeave,
    .preedit_string = textInputPreeditString,
    .commit_string = textInputCommitString,
    .delete_surrounding_text = textInputDeleteSurroundingText,
    .done = textInputDone,
};

fn textInputEnter(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, surface: ?*h.wl_surface) callconv(.c) void {
    if (getWindow(surface)) |window| {
        if (window.text_options) |options| {
            h.zwp_text_input_v3_enable(text_input);
            if (options.cursor) |cursor| {
                h.zwp_text_input_v3_set_cursor_rectangle(text_input, cursor.x, cursor.y, 0, 0);
            }
            h.zwp_text_input_v3_commit(text_input);
        }
    }
}

fn textInputLeave(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, surface: ?*h.wl_surface) callconv(.c) void {
    if (getWindow(surface)) |window| {
        if (window.text_options) |_| {
            h.zwp_text_input_v3_disable(text_input);
            h.zwp_text_input_v3_commit(text_input);
        }
    }
}

fn textInputPreeditString(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, text: [*c]const u8, cursor_begin: i32, cursor_end: i32) callconv(.c) void {
    if (focus) |window| {
        window.repeat_key = 0;
    }
    if (text == null) {
        preedit_string.clearRetainingCapacity();
        preedit_cursors = .{ 0, 0 };
        return;
    }
    preedit_active = true;
    preedit_string.replaceRange(internal.allocator, 0, preedit_string.items.len, std.mem.sliceTo(text, 0)) catch {};
    preedit_cursors = .{ cursor_begin, cursor_end };
}

fn textInputCommitString(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, text: [*c]const u8) callconv(.c) void {
    commit_string.replaceRange(internal.allocator, 0, commit_string.items.len, std.mem.sliceTo(text, 0)) catch {};
}

fn textInputDeleteSurroundingText(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, _: u32, _: u32) callconv(.c) void {}

fn textInputDone(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, _: u32) callconv(.c) void {
    defer {
        commit_string.clearRetainingCapacity();
        preedit_string.clearRetainingCapacity();
    }

    if (focus) |window| {
        if (preedit_active) {
            window.events.push(.preview_reset);
            if (preedit_string.items.len == 0) {
                preedit_active = false;
            }
        }
        if (commit_string.items.len > 0) {
            const view = std.unicode.Utf8View.init(commit_string.items) catch return;
            var iter = view.iterator();
            while (iter.nextCodepoint()) |char| {
                window.events.push(.{ .char = char });
            }
        }
        if (preedit_string.items.len > 0) {
            const view = std.unicode.Utf8View.init(preedit_string.items) catch return;
            var iter = view.iterator();
            var count: usize = 1;
            while (iter.nextCodepoint()) |char| : (count += 1) {
                window.events.push(.{ .preview_char = char });
                // convert byte offset to codepoint offset
                for (&preedit_cursors) |*cursor| {
                    if (cursor.* == iter.i) {
                        cursor.* = std.math.cast(i32, count) orelse -1;
                    }
                }
            }
            if (preedit_cursors[0] != -1 and preedit_cursors[1] != -1) {
                window.events.push(.{ .preview_cursor = .{ std.math.cast(u16, preedit_cursors[0]) orelse return, std.math.cast(u16, preedit_cursors[1]) orelse return } });
            }
        }
    }
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
fn dataDeviceEnter(_: ?*anyopaque, _: ?*h.wl_data_device, _: u32, _: ?*h.wl_surface, _: h.wl_fixed_t, _: h.wl_fixed_t, _: ?*h.wl_data_offer) callconv(.c) void {}
fn dataDeviceLeave(_: ?*anyopaque, _: ?*h.wl_data_device) callconv(.c) void {}
fn dataDeviceMotion(_: ?*anyopaque, _: ?*h.wl_data_device, _: u32, _: h.wl_fixed_t, _: h.wl_fixed_t) callconv(.c) void {}
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
    var writer = file.writer(&.{});
    writer.interface.writeAll(clipboard_text) catch {};
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
    const self: *Window = @ptrCast(@alignCast(data));
    self.configured = true;

    var mode = wio.WindowMode.normal;
    var window_state: h.libdecor_window_state = 0;
    if (c.libdecor_configuration_get_window_state(configuration, &window_state)) {
        if (window_state & h.LIBDECOR_WINDOW_STATE_MAXIMIZED != 0) mode = .maximized;
        if (window_state & h.LIBDECOR_WINDOW_STATE_FULLSCREEN != 0) mode = .fullscreen;
    }
    self.events.push(.{ .mode = mode });

    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!c.libdecor_configuration_get_content_size(configuration, frame, &width, &height)) {
        width = self.size.width;
        height = self.size.height;
    }
    self.resize(.{ .width = std.math.lossyCast(u16, width), .height = std.math.lossyCast(u16, height) }, configuration);
}

fn frameClose(_: ?*h.libdecor_frame, data: ?*anyopaque) callconv(.c) void {
    const self: *Window = @ptrCast(@alignCast(data));
    self.events.push(.close);
}

fn frameCommit(_: ?*h.libdecor_frame, data: ?*anyopaque) callconv(.c) void {
    const self: *Window = @ptrCast(@alignCast(data));
    self.events.push(.draw);
}

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

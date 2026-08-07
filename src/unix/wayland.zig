const std = @import("std");
const build_options = @import("build_options");
const h = @import("c");
const wio = @import("../wio.zig");
const internal = @import("../wio.internal.zig");
const unix = @import("../unix.zig");
const DynLib = @import("DynLib.zig");
const log = std.log.scoped(.wio);

var imports: extern struct {
    wl_display_connect: *const fn (name: [*c]const u8) callconv(.c) ?*h.struct_wl_display,
    wl_display_disconnect: *const fn (display: ?*h.struct_wl_display) callconv(.c) void,
    wl_display_get_fd: *const fn (display: ?*h.struct_wl_display) callconv(.c) c_int,
    wl_display_roundtrip: *const fn (display: ?*h.struct_wl_display) callconv(.c) c_int,
    wl_display_dispatch: *const fn (display: ?*h.struct_wl_display) callconv(.c) c_int,
    wl_proxy_get_version: *const fn (proxy: ?*h.struct_wl_proxy) callconv(.c) u32,
    wl_proxy_marshal_flags: *const fn (proxy: ?*h.struct_wl_proxy, opcode: u32, interface: [*c]const h.struct_wl_interface, version: u32, flags: u32, ...) callconv(.c) ?*h.struct_wl_proxy,
    wl_proxy_add_listener: *const fn (proxy: ?*h.struct_wl_proxy, implementation: [*c]?*const fn () callconv(.c) void, data: ?*anyopaque) callconv(.c) c_int,
    wl_proxy_destroy: *const fn (proxy: ?*h.struct_wl_proxy) callconv(.c) void,
    wl_proxy_set_user_data: *const fn (proxy: ?*h.struct_wl_proxy, user_data: ?*anyopaque) callconv(.c) void,
    wl_proxy_get_user_data: *const fn (proxy: ?*h.struct_wl_proxy) callconv(.c) ?*anyopaque,
    xkb_context_new: *const fn (flags: h.enum_xkb_context_flags) callconv(.c) ?*h.struct_xkb_context,
    xkb_context_unref: *const fn (context: ?*h.struct_xkb_context) callconv(.c) void,
    xkb_keymap_new_from_string: *const fn (context: ?*h.struct_xkb_context, string: [*c]const u8, format: h.enum_xkb_keymap_format, flags: h.enum_xkb_keymap_compile_flags) callconv(.c) ?*h.struct_xkb_keymap,
    xkb_keymap_unref: *const fn (keymap: ?*h.struct_xkb_keymap) callconv(.c) void,
    xkb_state_new: *const fn (keymap: ?*h.struct_xkb_keymap) callconv(.c) ?*h.struct_xkb_state,
    xkb_state_unref: *const fn (state: ?*h.struct_xkb_state) callconv(.c) void,
    xkb_state_update_mask: *const fn (state: ?*h.struct_xkb_state, depressed_mods: h.xkb_mod_mask_t, latched_mods: h.xkb_mod_mask_t, locked_mods: h.xkb_mod_mask_t, depressed_layout: h.xkb_layout_index_t, latched_layout: h.xkb_layout_index_t, locked_layout: h.xkb_layout_index_t) callconv(.c) h.enum_xkb_state_component,
    xkb_state_key_get_one_sym: *const fn (state: ?*h.struct_xkb_state, key: h.xkb_keycode_t) callconv(.c) h.xkb_keysym_t,
    xkb_keysym_to_utf32: *const fn (keysym: h.xkb_keysym_t) callconv(.c) u32,
    xkb_compose_table_new_from_locale: *const fn (context: ?*h.struct_xkb_context, locale: [*c]const u8, flags: h.enum_xkb_compose_compile_flags) callconv(.c) ?*h.struct_xkb_compose_table,
    xkb_compose_table_unref: *const fn (table: ?*h.struct_xkb_compose_table) callconv(.c) void,
    xkb_compose_state_new: *const fn (table: ?*h.struct_xkb_compose_table, flags: h.enum_xkb_compose_state_flags) callconv(.c) ?*h.struct_xkb_compose_state,
    xkb_compose_state_unref: *const fn (state: ?*h.struct_xkb_compose_state) callconv(.c) void,
    xkb_compose_state_feed: *const fn (state: ?*h.struct_xkb_compose_state, keysym: h.xkb_keysym_t) callconv(.c) h.enum_xkb_compose_feed_result,
    xkb_compose_state_get_status: *const fn (state: ?*h.struct_xkb_compose_state) callconv(.c) h.enum_xkb_compose_status,
    xkb_compose_state_get_one_sym: *const fn (state: ?*h.struct_xkb_compose_state) callconv(.c) h.xkb_keysym_t,
    xkb_compose_state_reset: *const fn (state: ?*h.struct_xkb_compose_state) callconv(.c) void,
    libdecor_new: *const fn (display: ?*h.struct_wl_display, iface: [*c]h.struct_libdecor_interface) callconv(.c) ?*h.struct_libdecor,
    libdecor_unref: *const fn (context: ?*h.struct_libdecor) callconv(.c) void,
    libdecor_decorate: *const fn (context: ?*h.struct_libdecor, surface: ?*h.struct_wl_surface, iface: [*c]h.struct_libdecor_frame_interface, user_data: ?*anyopaque) callconv(.c) ?*h.struct_libdecor_frame,
    libdecor_frame_unref: *const fn (frame: ?*h.struct_libdecor_frame) callconv(.c) void,
    libdecor_frame_map: *const fn (frame: ?*h.struct_libdecor_frame) callconv(.c) void,
    libdecor_configuration_get_window_state: *const fn (configuration: ?*h.struct_libdecor_configuration, window_state: [*c]h.enum_libdecor_window_state) callconv(.c) bool,
    libdecor_configuration_get_content_size: *const fn (configuration: ?*h.struct_libdecor_configuration, frame: ?*h.struct_libdecor_frame, width: [*c]c_int, height: [*c]c_int) callconv(.c) bool,
    libdecor_state_new: *const fn (width: c_int, height: c_int) callconv(.c) ?*h.struct_libdecor_state,
    libdecor_state_free: *const fn (state: ?*h.struct_libdecor_state) callconv(.c) void,
    libdecor_frame_commit: *const fn (frame: ?*h.struct_libdecor_frame, state: ?*h.struct_libdecor_state, configuration: ?*h.struct_libdecor_configuration) callconv(.c) void,
    libdecor_frame_set_title: *const fn (frame: ?*h.struct_libdecor_frame, title: [*c]const u8) callconv(.c) void,
    libdecor_frame_set_app_id: *const fn (frame: ?*h.struct_libdecor_frame, app_id: [*c]const u8) callconv(.c) void,
    libdecor_frame_set_maximized: *const fn (frame: ?*h.struct_libdecor_frame) callconv(.c) void,
    libdecor_frame_unset_maximized: *const fn (frame: ?*h.struct_libdecor_frame) callconv(.c) void,
    libdecor_frame_set_fullscreen: *const fn (frame: ?*h.struct_libdecor_frame, output: ?*h.struct_wl_output) callconv(.c) void,
    libdecor_frame_unset_fullscreen: *const fn (frame: ?*h.struct_libdecor_frame) callconv(.c) void,
    wl_egl_window_create: *const fn (surface: ?*h.struct_wl_surface, width: c_int, height: c_int) callconv(.c) ?*h.struct_wl_egl_window,
    wl_egl_window_destroy: *const fn (egl_window: ?*h.struct_wl_egl_window) callconv(.c) void,
    wl_egl_window_resize: *const fn (egl_window: ?*h.struct_wl_egl_window, width: c_int, height: c_int, dx: c_int, dy: c_int) callconv(.c) void,
    eglGetDisplay: *const fn (display_id: h.EGLNativeDisplayType) callconv(.c) h.EGLDisplay,
    eglGetError: *const fn () callconv(.c) h.EGLint,
    eglInitialize: *const fn (dpy: h.EGLDisplay, major: [*c]h.EGLint, minor: [*c]h.EGLint) callconv(.c) h.EGLBoolean,
    eglTerminate: *const fn (dpy: h.EGLDisplay) callconv(.c) h.EGLBoolean,
    eglBindAPI: *const fn (api: h.EGLenum) callconv(.c) h.EGLBoolean,
    eglChooseConfig: *const fn (dpy: h.EGLDisplay, attrib_list: [*c]const h.EGLint, configs: [*c]h.EGLConfig, config_size: h.EGLint, num_config: [*c]h.EGLint) callconv(.c) h.EGLBoolean,
    eglCreateWindowSurface: *const fn (dpy: h.EGLDisplay, config: h.EGLConfig, win: h.EGLNativeWindowType, attrib_list: [*c]const h.EGLint) callconv(.c) h.EGLSurface,
    eglDestroySurface: *const fn (dpy: h.EGLDisplay, surface: h.EGLSurface) callconv(.c) h.EGLBoolean,
    eglCreateContext: *const fn (dpy: h.EGLDisplay, config: h.EGLConfig, share_context: h.EGLContext, attrib_list: [*c]const h.EGLint) callconv(.c) h.EGLContext,
    eglDestroyContext: *const fn (dpy: h.EGLDisplay, ctx: h.EGLContext) callconv(.c) h.EGLBoolean,
    eglMakeCurrent: *const fn (dpy: h.EGLDisplay, draw: h.EGLSurface, read: h.EGLSurface, ctx: h.EGLContext) callconv(.c) h.EGLBoolean,
    eglSwapBuffers: *const fn (dpy: h.EGLDisplay, surface: h.EGLSurface) callconv(.c) h.EGLBoolean,
    eglSwapInterval: *const fn (dpy: h.EGLDisplay, interval: h.EGLint) callconv(.c) h.EGLBoolean,
    eglGetProcAddress: *const fn (procname: [*c]const u8) callconv(.c) h.__eglMustCastToProperFunctionPointerType,
} = undefined;
const c = if (build_options.system_integration) h else &imports;

const egl = internal.egl(c, h);

pub var globals: struct {
    libwayland_client: DynLib = undefined,
    libxkbcommon: DynLib = undefined,
    libdecor: DynLib = undefined,
    libwayland_egl: if (build_options.opengl) DynLib else void = undefined,
    libEGL: if (build_options.opengl) DynLib else void = undefined,

    display: *h.wl_display = undefined,
    registry: *h.wl_registry = undefined,
    compositor: ?*h.wl_compositor = null,
    shm: ?*h.wl_shm = null,
    seat: ?*h.wl_seat = null,
    keyboard: ?*h.wl_keyboard = null,
    pointer: ?*h.wl_pointer = null,
    touch: ?*h.wl_touch = null,
    viewporter: ?*h.wp_viewporter = null,
    fractional_scale_manager: ?*h.wp_fractional_scale_manager_v1 = null,
    text_input_manager: ?*h.zwp_text_input_manager_v3 = null,
    cursor_shape_manager: ?*h.wp_cursor_shape_manager_v1 = null,
    pointer_constraints: ?*h.zwp_pointer_constraints_v1 = null,
    relative_pointer_manager: ?*h.zwp_relative_pointer_manager_v1 = null,
    pointer_gestures: ?*h.zwp_pointer_gestures_v1 = null,
    data_device_manager: ?*h.wl_data_device_manager = null,
    activation: ?*h.xdg_activation_v1 = null,

    text_input: ?*h.zwp_text_input_v3 = null,
    cursor_shape_device: ?*h.wp_cursor_shape_device_v1 = null,
    relative_pointer: ?*h.zwp_relative_pointer_v1 = null,
    gesture_pinch: ?*h.zwp_pointer_gesture_pinch_v1 = null,
    data_device: ?*h.wl_data_device = null,
    data_offer: ?*h.wl_data_offer = null,
    data_source: ?*h.wl_data_source = null,

    xkb: *h.xkb_context = undefined,
    keymap: ?*h.xkb_keymap = null,
    xkb_state: ?*h.xkb_state = null,
    compose_state: ?*h.xkb_compose_state = null,

    libdecor_context: *h.libdecor = undefined,

    windows: std.AutoHashMapUnmanaged(*Window, void) = .empty,
    keyboard_focus: ?*Window = null,
    pointer_focus: ?*Window = null,
    gesture_focus: ?*Window = null,
    modifiers: wio.Modifiers = .{},
    last_serial: u32 = 0,
    pointer_enter_serial: u32 = 0,
    repeat_period: i32 = 0,
    repeat_delay: i32 = undefined,
    repeat_key: u32 = 0,
    repeat_timestamp: i64 = undefined,
    preedit_string: std.ArrayList(u8) = .empty,
    preedit_cursors: [2]i32 = .{ 0, 0 },
    preedit_active: bool = false,
    commit_string: std.ArrayList(u8) = .empty,
    touch_ids: std.StaticBitSet(256) = .empty,
    touch_info: std.AutoHashMapUnmanaged(i32, struct { public_id: u8, window: *Window }) = .empty,
    clipboard_text: []const u8 = "",

    drop: if (build_options.drop) struct {
        pending_drag_has_uri: bool = false,
        pending_drag_has_text: bool = false,
        drag_offer: ?*h.wl_data_offer = null,
        drag_has_uri: bool = false,
        drag_has_text: bool = false,
        drag_serial: u32 = 0,
        drag_window: ?*Window = null,
        drag_dropped: bool = false,
    } else struct {} = .{},
} = .{};

const exports = if (!build_options.system_integration) struct {
    export var wio_wl_proxy_get_version: @TypeOf(imports.wl_proxy_get_version) = undefined;
    export var wio_wl_proxy_marshal_flags: @TypeOf(imports.wl_proxy_marshal_flags) = undefined;
    export var wio_wl_proxy_add_listener: @TypeOf(imports.wl_proxy_add_listener) = undefined;
    export var wio_wl_proxy_destroy: @TypeOf(imports.wl_proxy_destroy) = undefined;
    export var wio_wl_proxy_set_user_data: @TypeOf(imports.wl_proxy_set_user_data) = undefined;
    export var wio_wl_proxy_get_user_data: @TypeOf(imports.wl_proxy_get_user_data) = undefined;
} else void;

pub fn init() !bool {
    DynLib.load(&imports, &.{
        .{ .handle = &globals.libwayland_client, .name = "libwayland-client.so.0", .prefix = "wl", .exclude = "wl_egl" },
        .{ .handle = &globals.libxkbcommon, .name = "libxkbcommon.so.0", .prefix = "xkb" },
        .{ .handle = &globals.libdecor, .name = "libdecor-0.so.0", .prefix = "libdecor" },
    }) catch return false;
    errdefer globals.libwayland_client.close();
    errdefer globals.libxkbcommon.close();
    errdefer globals.libdecor.close();

    if (build_options.opengl) {
        DynLib.load(&imports, &.{
            .{ .handle = &globals.libwayland_egl, .name = "libwayland-egl.so.1", .prefix = "wl_egl" },
            .{ .handle = &globals.libEGL, .name = "libEGL.so.1", .prefix = "egl" },
        }) catch return false;
    }
    errdefer if (build_options.opengl) globals.libwayland_egl.close();
    errdefer if (build_options.opengl) globals.libEGL.close();

    if (!build_options.system_integration) {
        exports.wio_wl_proxy_get_version = c.wl_proxy_get_version;
        exports.wio_wl_proxy_marshal_flags = c.wl_proxy_marshal_flags;
        exports.wio_wl_proxy_add_listener = c.wl_proxy_add_listener;
        exports.wio_wl_proxy_destroy = c.wl_proxy_destroy;
        exports.wio_wl_proxy_set_user_data = c.wl_proxy_set_user_data;
        exports.wio_wl_proxy_get_user_data = c.wl_proxy_get_user_data;
    }

    globals.display = c.wl_display_connect(null) orelse return false;
    errdefer c.wl_display_disconnect(globals.display);
    try unix.pollfds.append(internal.allocator, .{ .fd = c.wl_display_get_fd(globals.display), .events = std.c.POLL.IN, .revents = undefined });

    globals.xkb = c.xkb_context_new(h.XKB_CONTEXT_NO_FLAGS) orelse return error.Unexpected;
    errdefer c.xkb_context_unref(globals.xkb);

    const locale = std.c.getenv("LC_ALL") orelse std.c.getenv("LC_CTYPE") orelse std.c.getenv("LANG") orelse "C";
    const compose_table = c.xkb_compose_table_new_from_locale(globals.xkb, locale, h.XKB_COMPOSE_COMPILE_NO_FLAGS);
    defer c.xkb_compose_table_unref(compose_table);
    if (compose_table) |_| globals.compose_state = c.xkb_compose_state_new(compose_table, h.XKB_COMPOSE_STATE_NO_FLAGS);

    globals.registry = h.wl_display_get_registry(globals.display) orelse return error.Unexpected;
    errdefer destroyProxies();
    _ = h.wl_registry_add_listener(globals.registry, &registry_listener, null);
    _ = c.wl_display_roundtrip(globals.display);
    if (globals.compositor == null) return error.Unexpected;

    globals.libdecor_context = c.libdecor_new(globals.display, &libdecor_interface) orelse return error.Unexpected;
    errdefer c.libdecor_unref(globals.libdecor_context);

    if (globals.seat) |_| {
        if (globals.text_input_manager) |_| {
            globals.text_input = h.zwp_text_input_manager_v3_get_text_input(globals.text_input_manager, globals.seat);
            if (globals.text_input) |_| {
                _ = h.zwp_text_input_v3_add_listener(globals.text_input, &text_input_listener, null);
            }
        }

        if (globals.data_device_manager) |_| {
            globals.data_device = h.wl_data_device_manager_get_data_device(globals.data_device_manager, globals.seat);
            if (globals.data_device) |_| {
                _ = h.wl_data_device_add_listener(globals.data_device, &data_device_listener, null);
            }
        }
    }

    if (build_options.opengl) {
        try egl.init(globals.display);
    }

    return true;
}

pub fn deinit() void {
    if (build_options.opengl) {
        _ = c.eglTerminate(egl.display);
        globals.libEGL.close();
        globals.libwayland_egl.close();
    }

    internal.allocator.free(globals.clipboard_text);
    globals.touch_info.deinit(internal.allocator);
    globals.commit_string.deinit(internal.allocator);
    globals.preedit_string.deinit(internal.allocator);
    globals.windows.deinit(internal.allocator);

    c.libdecor_unref(globals.libdecor_context);
    globals.libdecor.close();

    c.xkb_compose_state_unref(globals.compose_state);
    c.xkb_state_unref(globals.xkb_state);
    c.xkb_keymap_unref(globals.keymap);
    c.xkb_context_unref(globals.xkb);
    globals.libxkbcommon.close();

    destroyProxies();
    c.wl_display_disconnect(globals.display);
    globals.libwayland_client.close();

    globals = .{};
}

fn destroyProxies() void {
    if (build_options.framebuffer) if (globals.shm) |_| h.wl_shm_destroy(globals.shm);
    if (globals.data_source) |_| h.wl_data_source_destroy(globals.data_source);
    if (globals.data_offer) |_| h.wl_data_offer_destroy(globals.data_offer);
    if (globals.data_device) |_| h.wl_data_device_destroy(globals.data_device);
    if (globals.gesture_pinch) |_| h.zwp_pointer_gesture_pinch_v1_destroy(globals.gesture_pinch);
    if (globals.relative_pointer) |_| h.zwp_relative_pointer_v1_destroy(globals.relative_pointer);
    if (globals.cursor_shape_device) |_| h.wp_cursor_shape_device_v1_destroy(globals.cursor_shape_device);
    if (globals.text_input) |_| h.zwp_text_input_v3_destroy(globals.text_input);
    if (globals.activation) |_| h.xdg_activation_v1_destroy(globals.activation);
    if (globals.data_device_manager) |_| h.wl_data_device_manager_destroy(globals.data_device_manager);
    if (globals.pointer_gestures) |_| h.zwp_pointer_gestures_v1_destroy(globals.pointer_gestures);
    if (globals.relative_pointer_manager) |_| h.zwp_relative_pointer_manager_v1_destroy(globals.relative_pointer_manager);
    if (globals.pointer_constraints) |_| h.zwp_pointer_constraints_v1_destroy(globals.pointer_constraints);
    if (globals.cursor_shape_manager) |_| h.wp_cursor_shape_manager_v1_destroy(globals.cursor_shape_manager);
    if (globals.text_input_manager) |_| h.zwp_text_input_manager_v3_destroy(globals.text_input_manager);
    if (globals.fractional_scale_manager) |_| h.wp_fractional_scale_manager_v1_destroy(globals.fractional_scale_manager);
    if (globals.viewporter) |_| h.wp_viewporter_destroy(globals.viewporter);
    if (globals.pointer) |_| h.wl_pointer_destroy(globals.pointer);
    if (globals.keyboard) |_| h.wl_keyboard_destroy(globals.keyboard);
    if (globals.seat) |_| h.wl_seat_destroy(globals.seat);
    if (globals.compositor) |_| h.wl_compositor_destroy(globals.compositor);
    h.wl_registry_destroy(globals.registry);
}

pub fn update() void {
    _ = c.wl_display_roundtrip(globals.display);

    if (globals.repeat_key != 0 and globals.repeat_period > 0) {
        if (globals.keyboard_focus) |focus| {
            const now = std.Io.Clock.awake.now(internal.io).toMilliseconds();
            if (now > globals.repeat_timestamp) {
                focus.pushKeyEvent(globals.repeat_key, .button_repeat);
                globals.repeat_timestamp = now + globals.repeat_period;
            }
        }
    }
}

pub const Window = struct {
    event_fn_data: ?*anyopaque,
    surface: *h.wl_surface,
    frame: *h.libdecor_frame,
    configured: bool = false,
    viewport: ?*h.wp_viewport = null,
    fractional_scale: ?*h.wp_fractional_scale_v1 = null,
    locked_pointer: ?*h.zwp_locked_pointer_v1 = null,
    text_options: ?wio.TextInputOptions = null,
    frame_callback: ?*h.wl_callback = null,
    draw_available_events: bool = false,
    inhibit_draw: bool = false,
    size: wio.Size,
    scale: f32 = 1,
    cursor: u32 = h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT,
    relative_mouse: ?wio.RelativeMouseOptions = null,
    drop: if (build_options.drop) struct {
        files: std.ArrayList([]const u8) = .empty,
        text: ?[]const u8 = null,
    } else struct {} = .{},
    egl: if (build_options.opengl) struct {
        config: h.EGLConfig = null,
        window: ?*h.wl_egl_window = null,
        surface: h.EGLSurface = null,
    } else struct {} = .{},

    pub fn create(options: wio.CreateWindowOptions) !*Window {
        const self = try internal.allocator.create(Window);

        const surface = h.wl_compositor_create_surface(globals.compositor) orelse return error.Unexpected;
        errdefer h.wl_surface_destroy(surface);
        h.wl_surface_set_user_data(surface, self);

        const frame = c.libdecor_decorate(globals.libdecor_context, surface, &libdecor_frame_interface, self) orelse return error.Unexpected;
        errdefer c.libdecor_frame_unref(frame);

        self.* = .{
            .event_fn_data = options.event_fn_data,
            .surface = surface,
            .frame = frame,
            .size = options.size,
        };

        if (globals.viewporter) |_| {
            self.viewport = h.wp_viewporter_get_viewport(globals.viewporter, surface);
        }
        errdefer if (self.viewport) |_| h.wp_viewport_destroy(self.viewport);

        if (self.viewport) |_| {
            if (globals.fractional_scale_manager) |_| {
                if (h.wp_fractional_scale_manager_v1_get_fractional_scale(globals.fractional_scale_manager, surface)) |fractional_scale| {
                    self.fractional_scale = fractional_scale;
                    _ = h.wp_fractional_scale_v1_add_listener(fractional_scale, &fractional_scale_listener, self);
                }
            }
        }
        errdefer if (self.fractional_scale) |_| h.wp_fractional_scale_v1_destroy(self.fractional_scale);

        internal.eventFn(self.event_fn_data, .{ .position = .{ .x = 0, .y = 0 } });
        internal.eventFn(self.event_fn_data, .visible);
        if (self.fractional_scale == null) internal.eventFn(self.event_fn_data, .{ .scale = 1 });

        h.wl_surface_commit(surface);
        c.libdecor_frame_map(frame);
        while (!self.configured) {
            if (c.wl_display_dispatch(globals.display) == -1) return error.Unexpected;
        }

        self.setTitle(options.title);
        self.setMode(options.mode);

        if (options.app_id) |app_id| {
            const id = try internal.allocator.dupeSentinel(u8, app_id, 0);
            defer internal.allocator.free(id);
            c.libdecor_frame_set_app_id(self.frame, id);
        }

        if (build_options.opengl) {
            if (options.gl_options) |gl| {
                self.egl.config = try egl.chooseConfig(gl);
                self.egl.window = c.wl_egl_window_create(self.surface, options.size.width, options.size.height);
                self.egl.surface = c.eglCreateWindowSurface(egl.display, self.egl.config, self.egl.window, null) orelse return egl.logError("eglCreateWindowSurface");
            }
        }

        try globals.windows.put(internal.allocator, self, {});
        return self;
    }

    pub fn destroy(self: *Window) void {
        if (globals.gesture_focus == self) globals.gesture_focus = null;
        if (globals.pointer_focus == self) globals.pointer_focus = null;
        if (globals.keyboard_focus == self) {
            globals.keyboard_focus = null;
            globals.repeat_key = 0;
        }
        _ = globals.windows.remove(self);

        while (true) {
            var iter = globals.touch_info.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.window == self) {
                    _ = globals.touch_info.remove(entry.key_ptr.*);
                    continue;
                }
            }
            break;
        }

        if (build_options.opengl) {
            if (self.egl.surface) |_| _ = c.eglDestroySurface(egl.display, self.egl.surface);
            if (self.egl.window) |_| c.wl_egl_window_destroy(self.egl.window);
        }

        if (build_options.drop) {
            for (self.drop.files.items) |file| internal.allocator.free(file);
            self.drop.files.deinit(internal.allocator);
            if (self.drop.text) |text| internal.allocator.free(text);
        }

        if (self.frame_callback) |_| h.wl_callback_destroy(self.frame_callback);
        if (self.fractional_scale) |_| h.wp_fractional_scale_v1_destroy(self.fractional_scale);
        if (self.viewport) |_| h.wp_viewport_destroy(self.viewport);
        c.libdecor_frame_unref(self.frame);
        h.wl_surface_destroy(self.surface);
        _ = c.wl_display_roundtrip(globals.display);

        internal.allocator.destroy(self);
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        self.text_options = options;
        if (globals.keyboard_focus == self) {
            if (globals.text_input) |_| {
                h.zwp_text_input_v3_enable(globals.text_input);
                if (options.cursor) |cursor| {
                    h.zwp_text_input_v3_set_cursor_rectangle(globals.text_input, cursor.x, cursor.y, 0, 0);
                }
                h.zwp_text_input_v3_commit(globals.text_input);
            }
        }
    }

    pub fn disableTextInput(self: *Window) void {
        self.text_options = null;
        if (globals.keyboard_focus == self) {
            if (globals.text_input) |_| {
                h.zwp_text_input_v3_disable(globals.text_input);
                h.zwp_text_input_v3_commit(globals.text_input);
            }
        }
    }

    pub fn enableRelativeMouse(self: *Window, options: wio.RelativeMouseOptions) void {
        self.relative_mouse = options;
        if (globals.pointer_focus == self) self.applyCursor();
    }

    pub fn disableRelativeMouse(self: *Window) void {
        self.relative_mouse = null;
        if (globals.pointer_focus == self) self.applyCursor();
    }

    pub fn enableDrawAvailableEvents(self: *Window) void {
        self.draw_available_events = true;
        if (self.frame_callback == null) {
            self.frame_callback = h.wl_surface_frame(self.surface);
            _ = h.wl_callback_add_listener(self.frame_callback, &frame_callback_listener, self);
        }
    }

    pub fn disableDrawAvailableEvents(self: *Window) void {
        self.draw_available_events = false;
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        const title_z = internal.allocator.dupeSentinel(u8, title, 0) catch return;
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

    pub fn setPosition(self: *Window, position: wio.Position) void {
        _ = self;
        _ = position;
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        self.resize(size, null);
    }

    pub fn setParent(self: *Window, parent: usize) void {
        _ = self;
        _ = parent;
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        self.cursor = switch (shape) {
            .default => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT,
            .none => 0,
            .context_menu => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CONTEXT_MENU,
            .help => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_HELP,
            .pointer => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER,
            .progress => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_PROGRESS,
            .wait => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_WAIT,
            .cell => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CELL,
            .crosshair => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR,
            .text => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT,
            .vertical_text => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_VERTICAL_TEXT,
            .alias => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALIAS,
            .copy => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_COPY,
            .move => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE,
            .no_drop => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NO_DROP,
            .not_allowed => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NOT_ALLOWED,
            .grab => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRAB,
            .grabbing => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRABBING,
            .e_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_E_RESIZE,
            .n_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_N_RESIZE,
            .ne_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NE_RESIZE,
            .nw_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NW_RESIZE,
            .s_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_S_RESIZE,
            .se_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SE_RESIZE,
            .sw_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SW_RESIZE,
            .w_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_W_RESIZE,
            .ew_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_EW_RESIZE,
            .ns_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NS_RESIZE,
            .nesw_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NESW_RESIZE,
            .nwse_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NWSE_RESIZE,
            .col_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_COL_RESIZE,
            .row_resize => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ROW_RESIZE,
            .all_scroll => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALL_SCROLL,
            .zoom_in => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ZOOM_IN,
            .zoom_out => h.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ZOOM_OUT,
        };
        if (globals.pointer_focus == self) self.applyCursor();
    }

    pub fn requestAttention(self: *Window) void {
        if (globals.activation == null) return;
        const token = h.xdg_activation_v1_get_activation_token(globals.activation);
        _ = h.xdg_activation_token_v1_add_listener(token, &activation_token_listener, self.surface);
        h.xdg_activation_token_v1_commit(token);
    }

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        if (globals.data_device_manager == null or globals.data_device == null) return;

        internal.allocator.free(globals.clipboard_text);
        globals.clipboard_text = internal.allocator.dupe(u8, text) catch "";

        if (globals.data_source) |_| h.wl_data_source_destroy(globals.data_source);
        globals.data_source = h.wl_data_device_manager_create_data_source(globals.data_device_manager);
        _ = h.wl_data_source_add_listener(globals.data_source, &data_source_listener, null);
        h.wl_data_source_offer(globals.data_source, "text/plain;charset=utf-8");
        h.wl_data_device_set_selection(globals.data_device, globals.data_source, globals.last_serial);
    }

    pub fn getClipboardText(_: *Window, clipboardTextFn: *const fn (?*anyopaque, []const u8) void, clipboard_text_fn_data: ?*anyopaque) void {
        if (globals.data_offer == null) return;
        var pipe: [2]i32 = undefined;
        if (std.c.pipe(&pipe) == -1) return;
        defer _ = std.c.close(pipe[0]);
        h.wl_data_offer_receive(globals.data_offer, "text/plain;charset=utf-8", pipe[1]);
        _ = c.wl_display_roundtrip(globals.display);
        _ = std.c.close(pipe[1]);

        var buffer: [1024]u8 = undefined;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(internal.allocator);
        while (true) {
            const count = std.c.read(pipe[0], &buffer, buffer.len);
            if (std.c.errno(count) != .SUCCESS) {
                return;
            } else if (count == 0) {
                clipboardTextFn(clipboard_text_fn_data, text.items);
                break;
            } else {
                text.appendSlice(internal.allocator, buffer[0..@intCast(count)]) catch return;
            }
        }
    }

    pub fn getDropData(self: *Window, allocator: std.mem.Allocator) wio.DropData {
        return wio.DropData.dupe(allocator, self.drop.files.items, self.drop.text) catch .{ .files = &.{}, .text = null };
    }

    pub fn createFramebuffer(_: *Window, size: wio.Size) !Framebuffer {
        if (globals.shm == null) return error.Unexpected;

        const fd = blk: {
            var attempt: u8 = 0;
            while (attempt < 10) : (attempt += 1) {
                const now = std.Io.Clock.awake.now(internal.io).nanoseconds;
                const name = try std.fmt.allocPrintSentinel(internal.allocator, "/wio-{x}", .{now}, 0);
                defer internal.allocator.free(name);

                const fd = std.c.shm_open(name, @bitCast(std.c.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true }), 0o600);
                if (fd >= 0) {
                    _ = std.c.shm_unlink(name);
                    break :blk fd;
                }
            }
            return error.Unexpected;
        };
        errdefer _ = std.c.close(fd);

        const byte_size = @sizeOf(u32) * @as(usize, size.width) * size.height;

        if (std.c.errno(std.c.ftruncate(fd, std.math.cast(std.c.off_t, byte_size) orelse return error.Unexpected)) != .SUCCESS) return error.Unexpected;

        const mapped = try std.posix.mmap(
            null,
            byte_size,
            .{ .READ = true, .WRITE = true },
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        errdefer std.posix.munmap(mapped);

        const pool = h.wl_shm_create_pool(
            globals.shm,
            fd,
            std.math.cast(i32, byte_size) orelse return error.Unexpected,
        ) orelse return error.Unexpected;
        defer h.wl_shm_pool_destroy(pool);

        const buffer = h.wl_shm_pool_create_buffer(
            pool,
            0,
            size.width,
            size.height,
            @as(i32, size.width) * @sizeOf(u32),
            h.WL_SHM_FORMAT_XRGB8888,
        ) orelse return error.Unexpected;

        return .{
            .fd = fd,
            .mapped = mapped,
            .buffer = buffer,
            .width = size.width,
        };
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        h.wl_surface_attach(self.surface, framebuffer.buffer, 0, 0);
        h.wl_surface_damage(self.surface, 0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
        h.wl_surface_commit(self.surface);
        _ = c.wl_display_roundtrip(globals.display);
    }

    pub fn glCreateContext(self: *Window, options: wio.GlCreateContextOptions) !GlContext {
        return .{
            .context = try egl.createContext(
                self.egl.config,
                options.options,
                if (options.share) |share| share.backend.wayland.context else null,
            ),
        };
    }

    pub fn glMakeContextCurrent(self: *Window, context: GlContext) void {
        _ = c.eglMakeCurrent(egl.display, self.egl.surface, self.egl.surface, context.context);
    }

    pub fn glSwapBuffers(self: *Window) void {
        _ = c.eglSwapBuffers(egl.display, self.egl.surface);
    }

    pub fn glSwapInterval(_: *Window, interval: i32) void {
        _ = c.eglSwapInterval(egl.display, interval);
    }

    pub fn vkCreateSurface(self: Window, instance: usize, allocation_callbacks: ?*const anyopaque, surface: *u64) i32 {
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
                .display = globals.display,
                .surface = self.surface,
            },
            allocation_callbacks,
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

        internal.eventFn(self.event_fn_data, .{ .size_logical = size });
        internal.eventFn(self.event_fn_data, .{ .size_physical = framebuffer });

        if (!self.draw_available_events) {
            if (!self.inhibit_draw) {
                internal.eventFn(self.event_fn_data, .draw);
                self.inhibit_draw = true;
            }

            if (self.frame_callback == null) {
                self.frame_callback = h.wl_surface_frame(self.surface);
                _ = h.wl_callback_add_listener(self.frame_callback, &frame_callback_listener, self);
            }
        }
    }

    fn pushKeyEvent(self: *Window, key: u32, comptime event: wio.EventType) void {
        if (keyToButton(key)) |button| {
            internal.eventFn(self.event_fn_data, @unionInit(wio.Event, @tagName(event), button));
        }

        if (self.text_options) |_| {
            if (!globals.modifiers.control and !globals.modifiers.alt) {
                var sym = c.xkb_state_key_get_one_sym(globals.xkb_state, key + 8);
                if (globals.compose_state) |_| {
                    if (c.xkb_compose_state_feed(globals.compose_state, sym) == h.XKB_COMPOSE_FEED_ACCEPTED) {
                        switch (c.xkb_compose_state_get_status(globals.compose_state)) {
                            h.XKB_COMPOSE_COMPOSED => sym = c.xkb_compose_state_get_one_sym(globals.compose_state),
                            h.XKB_COMPOSE_COMPOSING, h.XKB_COMPOSE_CANCELLED => return,
                            else => {},
                        }
                    }
                }
                if (std.math.cast(u21, c.xkb_keysym_to_utf32(sym))) |char| {
                    if (char >= ' ' and char != 0x7F) {
                        internal.eventFn(self.event_fn_data, .{ .char = char });
                    }
                }
            }
        }
    }

    fn applyCursor(self: *Window) void {
        if (self.cursor != 0 and self.relative_mouse == null) {
            if (globals.cursor_shape_device) |_| {
                h.wp_cursor_shape_device_v1_set_shape(globals.cursor_shape_device, globals.pointer_enter_serial, self.cursor);
            }
        } else {
            h.wl_pointer_set_cursor(globals.pointer, globals.pointer_enter_serial, null, 0, 0);
        }

        if (self.locked_pointer) |_| {
            h.zwp_locked_pointer_v1_destroy(self.locked_pointer);
            self.locked_pointer = null;
        }

        if (self.relative_mouse != null) {
            if (globals.pointer_constraints) |_| {
                self.locked_pointer = h.zwp_pointer_constraints_v1_lock_pointer(globals.pointer_constraints, self.surface, globals.pointer, null, h.ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
            }
        }
    }
};

pub const Framebuffer = struct {
    fd: std.c.fd_t,
    mapped: []align(std.heap.page_size_min) u8,
    buffer: *h.wl_buffer,
    width: u16,

    pub fn destroy(self: *Framebuffer) void {
        h.wl_buffer_destroy(self.buffer);
        std.posix.munmap(self.mapped);
        _ = std.c.close(self.fd);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        std.mem.writeInt(u32, std.mem.asBytes(&std.mem.bytesAsSlice(u32, self.mapped)[y * self.width + x]), rgb, .little);
    }
};

pub const GlContext = struct {
    context: h.EGLContext,

    pub fn destroy(self: GlContext) void {
        _ = c.eglDestroyContext(egl.display, self.context);
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

pub fn glReleaseCurrentContext() void {
    _ = c.eglMakeCurrent(egl.display, h.EGL_NO_SURFACE, h.EGL_NO_SURFACE, h.EGL_NO_CONTEXT);
}

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_wayland_surface" };
}

fn getWindow(surface: ?*h.wl_surface) ?*Window {
    const window: *Window = @ptrCast(@alignCast(h.wl_surface_get_user_data(surface orelse return null) orelse return null));
    return if (globals.windows.contains(window)) window else null;
}

fn fixedToFloat(value: h.wl_fixed_t) f32 {
    return @as(f32, @floatFromInt(value)) / 256;
}

const frame_callback_listener: h.wl_callback_listener = .{
    .done = frameCallback,
};

fn frameCallback(data: ?*anyopaque, callback: ?*h.wl_callback, _: u32) callconv(.c) void {
    h.wl_callback_destroy(callback);

    const self: *Window = @ptrCast(@alignCast(data));
    if (self.draw_available_events) {
        self.frame_callback = h.wl_surface_frame(self.surface);
        _ = h.wl_callback_add_listener(self.frame_callback, &frame_callback_listener, self);
    } else {
        self.frame_callback = null;
        self.inhibit_draw = false;
    }
    internal.eventFn(self.event_fn_data, .draw);
}

const registry_listener: h.wl_registry_listener = .{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn registryGlobal(_: ?*anyopaque, _: ?*h.wl_registry, name: u32, interface_ptr: [*c]const u8, version: u32) callconv(.c) void {
    const interface = std.mem.sliceTo(interface_ptr, 0);
    if (std.mem.eql(u8, interface, "wl_compositor")) {
        globals.compositor = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wl_compositor_interface, @min(version, 3)));
    } else if (build_options.framebuffer and std.mem.eql(u8, interface, "wl_shm")) {
        globals.shm = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wl_shm_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wl_seat")) {
        globals.seat = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wl_seat_interface, @min(version, 4)));
        _ = h.wl_seat_add_listener(globals.seat, &seat_listener, null);
    } else if (std.mem.eql(u8, interface, "wp_viewporter")) {
        globals.viewporter = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wp_viewporter_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wp_fractional_scale_manager_v1")) {
        globals.fractional_scale_manager = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wp_fractional_scale_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_text_input_manager_v3")) {
        globals.text_input_manager = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.zwp_text_input_manager_v3_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "wp_cursor_shape_manager_v1")) {
        globals.cursor_shape_manager = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wp_cursor_shape_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_pointer_constraints_v1")) {
        globals.pointer_constraints = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.zwp_pointer_constraints_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_relative_pointer_manager_v1")) {
        globals.relative_pointer_manager = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.zwp_relative_pointer_manager_v1_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "zwp_pointer_gestures_v1")) {
        globals.pointer_gestures = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.zwp_pointer_gestures_v1_interface, @min(version, 3)));
    } else if (std.mem.eql(u8, interface, "wl_data_device_manager")) {
        globals.data_device_manager = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.wl_data_device_manager_interface, @min(version, 1)));
    } else if (std.mem.eql(u8, interface, "xdg_activation_v1")) {
        globals.activation = @ptrCast(h.wl_registry_bind(globals.registry, name, &h.xdg_activation_v1_interface, @min(version, 1)));
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*h.wl_registry, _: u32) callconv(.c) void {}

const seat_listener: h.wl_seat_listener = .{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn seatCapabilities(_: ?*anyopaque, _: ?*h.wl_seat, capabilities: h.wl_seat_capability) callconv(.c) void {
    if (globals.touch) |_| {
        h.wl_touch_destroy(globals.touch);
        globals.touch = null;
        globals.touch_ids = .empty;
        globals.touch_info.clearRetainingCapacity();
    }
    if (globals.gesture_pinch) |_| {
        h.zwp_pointer_gesture_pinch_v1_destroy(globals.gesture_pinch);
        globals.gesture_pinch = null;
    }
    if (globals.relative_pointer) |_| {
        h.zwp_relative_pointer_v1_destroy(globals.relative_pointer);
        globals.relative_pointer = null;
    }
    if (globals.cursor_shape_device) |_| {
        h.wp_cursor_shape_device_v1_destroy(globals.cursor_shape_device);
        globals.cursor_shape_device = null;
    }
    if (globals.pointer) |_| {
        h.wl_pointer_release(globals.pointer);
        globals.pointer = null;
    }
    if (globals.keyboard) |_| {
        h.wl_keyboard_release(globals.keyboard);
        globals.keyboard = null;
    }

    if (capabilities & h.WL_SEAT_CAPABILITY_KEYBOARD != 0) {
        globals.keyboard = h.wl_seat_get_keyboard(globals.seat);
        _ = h.wl_keyboard_add_listener(globals.keyboard, &keyboard_listener, null);
    }
    if (capabilities & h.WL_SEAT_CAPABILITY_POINTER != 0) {
        globals.pointer = h.wl_seat_get_pointer(globals.seat);
        _ = h.wl_pointer_add_listener(globals.pointer, &pointer_listener, null);
        if (globals.cursor_shape_manager) |_| {
            globals.cursor_shape_device = h.wp_cursor_shape_manager_v1_get_pointer(globals.cursor_shape_manager, globals.pointer);
        }
        if (globals.relative_pointer_manager) |_| {
            globals.relative_pointer = h.zwp_relative_pointer_manager_v1_get_relative_pointer(globals.relative_pointer_manager, globals.pointer);
            _ = h.zwp_relative_pointer_v1_add_listener(globals.relative_pointer, &relative_pointer_listener, null);
        }
        if (globals.pointer_gestures) |_| {
            globals.gesture_pinch = h.zwp_pointer_gestures_v1_get_pinch_gesture(globals.pointer_gestures, globals.pointer);
            _ = h.zwp_pointer_gesture_pinch_v1_add_listener(globals.gesture_pinch, &gesture_pinch_listener, null);
        }
    }
    if (capabilities & h.WL_SEAT_CAPABILITY_TOUCH != 0) {
        globals.touch = h.wl_seat_get_touch(globals.seat);
        _ = h.wl_touch_add_listener(globals.touch, &touch_listener, null);
    }
}

fn seatName(_: ?*anyopaque, _: ?*h.wl_seat, _: [*c]const u8) callconv(.c) void {}

const keyboard_listener: h.wl_keyboard_listener = .{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

fn keyboardKeymap(_: ?*anyopaque, _: ?*h.wl_keyboard, _: h.wl_keyboard_keymap_format, fd: i32, size: u32) callconv(.c) void {
    defer _ = std.c.close(fd);
    c.xkb_keymap_unref(globals.keymap);
    c.xkb_state_unref(globals.xkb_state);

    const string = std.c.mmap(null, size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, fd, 0);
    defer _ = std.c.munmap(@alignCast(string), size);

    globals.keymap = c.xkb_keymap_new_from_string(globals.xkb, @ptrCast(string), h.XKB_KEYMAP_FORMAT_TEXT_V1, h.XKB_KEYMAP_COMPILE_NO_FLAGS);
    globals.xkb_state = c.xkb_state_new(globals.keymap);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface, _: ?*h.wl_array) callconv(.c) void {
    globals.keyboard_focus = getWindow(surface);
    if (globals.keyboard_focus) |window| internal.eventFn(window.event_fn_data, .focused);
}

fn keyboardLeave(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface) callconv(.c) void {
    if (globals.keyboard_focus) |window| {
        if (window.surface == surface) {
            globals.keyboard_focus = null;
            globals.repeat_key = 0;
            internal.eventFn(window.event_fn_data, .unfocused);
        }
    }
    if (globals.compose_state) |_| c.xkb_compose_state_reset(globals.compose_state);
}

fn keyboardKey(_: ?*anyopaque, _: ?*h.wl_keyboard, serial: u32, _: u32, key: u32, state: h.wl_keyboard_key_state) callconv(.c) void {
    globals.last_serial = serial;
    if (globals.keyboard_focus) |window| {
        if (state == h.WL_KEYBOARD_KEY_STATE_PRESSED) {
            window.pushKeyEvent(key, .button_press);
            if (globals.repeat_period > 0) {
                globals.repeat_key = key;
                globals.repeat_timestamp = std.Io.Clock.awake.now(internal.io).toMilliseconds() + globals.repeat_delay;
            }
        } else {
            if (keyToButton(key)) |button| {
                internal.eventFn(window.event_fn_data, .{ .button_release = button });
            }
            if (key == globals.repeat_key) {
                globals.repeat_key = 0;
            }
        }
    }
}

fn keyboardModifiers(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, _: u32) callconv(.c) void {
    if (globals.keyboard_focus) |window| {
        const mods = mods_depressed | mods_latched | mods_locked;
        globals.modifiers = .{
            .control = (mods & (1 << 2) != 0),
            .shift = (mods & (1 << 0) != 0),
            .alt = (mods & (1 << 3) != 0),
            .gui = (mods & (1 << 6) != 0),
        };
        internal.eventFn(window.event_fn_data, .{ .modifiers = globals.modifiers });
    }

    _ = c.xkb_state_update_mask(globals.xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, 0);
}

fn keyboardRepeatInfo(_: ?*anyopaque, _: ?*h.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    if (rate > 0) {
        globals.repeat_period = @divTrunc(1000, rate);
        globals.repeat_delay = delay;
    }
}

const pointer_listener: h.wl_pointer_listener = .{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
};

fn pointerEnter(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, surface: ?*h.wl_surface, _: h.wl_fixed_t, _: h.wl_fixed_t) callconv(.c) void {
    globals.pointer_enter_serial = serial;
    globals.pointer_focus = getWindow(surface);
    if (globals.pointer_focus) |window| {
        window.applyCursor();
    }
}

fn pointerLeave(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, _: ?*h.wl_surface) callconv(.c) void {
    if (globals.pointer_focus) |window| {
        internal.eventFn(window.event_fn_data, .mouse_leave);
    }
    globals.pointer_focus = null;
}

fn pointerMotion(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, surface_x: h.wl_fixed_t, surface_y: h.wl_fixed_t) callconv(.c) void {
    if (globals.pointer_focus) |window| {
        internal.eventFn(window.event_fn_data, .{
            .mouse = .{
                .x = std.math.cast(i16, surface_x >> 8) orelse return,
                .y = std.math.cast(i16, surface_y >> 8) orelse return,
            },
        });
    }
}

fn pointerButton(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, _: u32, button: u32, state: h.wl_pointer_button_state) callconv(.c) void {
    globals.last_serial = serial;
    if (globals.pointer_focus) |window| {
        const wio_button: wio.Button = switch (button) {
            0x110 => .mouse_left,
            0x111 => .mouse_right,
            0x112 => .mouse_middle,
            0x113 => .mouse_back,
            0x114 => .mouse_forward,
            else => return,
        };
        internal.eventFn(window.event_fn_data, if (state == h.WL_POINTER_BUTTON_STATE_PRESSED) .{ .button_press = wio_button } else .{ .button_release = wio_button });
    }
}

fn pointerAxis(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, axis: h.wl_pointer_axis, value: h.wl_fixed_t) callconv(.c) void {
    if (globals.pointer_focus) |window| {
        const float = fixedToFloat(value);
        switch (axis) {
            h.WL_POINTER_AXIS_VERTICAL_SCROLL => internal.eventFn(window.event_fn_data, .{ .scroll_vertical = float }),
            h.WL_POINTER_AXIS_HORIZONTAL_SCROLL => internal.eventFn(window.event_fn_data, .{ .scroll_horizontal = float }),
            else => {},
        }
    }
}

const relative_pointer_listener: h.zwp_relative_pointer_v1_listener = .{
    .relative_motion = relativePointerMotion,
};

fn relativePointerMotion(_: ?*anyopaque, _: ?*h.zwp_relative_pointer_v1, _: u32, _: u32, dx: h.wl_fixed_t, dy: h.wl_fixed_t, dx_unaccel: h.wl_fixed_t, dy_unaccel: h.wl_fixed_t) callconv(.c) void {
    if (globals.pointer_focus) |window| {
        if (window.relative_mouse) |options| {
            internal.eventFn(window.event_fn_data, .{
                .mouse_relative = .{
                    .x = std.math.cast(i16, (if (options.unaccelerated) dx_unaccel else dx) >> 8) orelse return,
                    .y = std.math.cast(i16, (if (options.unaccelerated) dy_unaccel else dy) >> 8) orelse return,
                },
            });
        }
    }
}

const gesture_pinch_listener: h.zwp_pointer_gesture_pinch_v1_listener = .{
    .begin = gesturePinchBegin,
    .update = gesturePinchUpdate,
    .end = gesturePinchEnd,
};

fn gesturePinchBegin(_: ?*anyopaque, _: ?*h.zwp_pointer_gesture_pinch_v1, _: u32, _: u32, surface: ?*h.wl_surface, fingers: u32) callconv(.c) void {
    if (fingers == 2) {
        if (getWindow(surface)) |window| {
            globals.gesture_focus = window;
        }
    }
}

fn gesturePinchUpdate(_: ?*anyopaque, _: ?*h.zwp_pointer_gesture_pinch_v1, _: u32, dx: h.wl_fixed_t, dy: h.wl_fixed_t, scale: h.wl_fixed_t, rotation: h.wl_fixed_t) callconv(.c) void {
    if (globals.gesture_focus) |window| {
        if (dx != 0) {
            internal.eventFn(window.event_fn_data, .{ .scroll_horizontal = -fixedToFloat(dx) });
        }
        if (dy != 0) {
            internal.eventFn(window.event_fn_data, .{ .scroll_vertical = -fixedToFloat(dy) });
        }
        if (scale != 0) {
            internal.eventFn(window.event_fn_data, .{ .gesture_zoom = fixedToFloat(scale) });
        }
        if (rotation != 0) {
            internal.eventFn(window.event_fn_data, .{ .gesture_rotate = fixedToFloat(rotation) });
        }
    }
}

fn gesturePinchEnd(_: ?*anyopaque, _: ?*h.zwp_pointer_gesture_pinch_v1, _: u32, _: u32, cancelled: i32) callconv(.c) void {
    if (globals.gesture_focus) |window| {
        internal.eventFn(window.event_fn_data, .{ .gesture_ignore = (cancelled == 1) });
    }
}

const touch_listener: h.wl_touch_listener = .{
    .down = touchDown,
    .up = touchUp,
    .motion = touchMotion,
    .frame = touchFrame,
    .cancel = touchCancel,
};

fn touchDown(_: ?*anyopaque, _: ?*h.wl_touch, serial: u32, _: u32, surface: ?*h.wl_surface, id: i32, x: h.wl_fixed_t, y: h.wl_fixed_t) callconv(.c) void {
    globals.last_serial = serial;
    if (getWindow(surface)) |window| {
        var iter = globals.touch_ids.iterator(.{ .kind = .unset });
        const public_id: u8 = @intCast(iter.next() orelse return);
        globals.touch_info.put(internal.allocator, id, .{ .public_id = public_id, .window = window }) catch return;
        globals.touch_ids.set(public_id);
        internal.eventFn(window.event_fn_data, .{
            .touch = .{
                .id = public_id,
                .x = std.math.cast(i16, x >> 8) orelse return,
                .y = std.math.cast(i16, y >> 8) orelse return,
            },
        });
    }
}

fn touchUp(_: ?*anyopaque, _: ?*h.wl_touch, serial: u32, _: u32, id: i32) callconv(.c) void {
    globals.last_serial = serial;
    if (globals.touch_info.get(id)) |info| {
        internal.eventFn(info.window.event_fn_data, .{ .touch_end = .{ .id = info.public_id, .ignore = false } });
        globals.touch_ids.unset(info.public_id);
    }
}

fn touchMotion(_: ?*anyopaque, _: ?*h.wl_touch, _: u32, id: i32, x: h.wl_fixed_t, y: h.wl_fixed_t) callconv(.c) void {
    if (globals.touch_info.get(id)) |info| {
        internal.eventFn(info.window.event_fn_data, .{
            .touch = .{
                .id = info.public_id,
                .x = std.math.cast(i16, x >> 8) orelse return,
                .y = std.math.cast(i16, y >> 8) orelse return,
            },
        });
    }
}

fn touchFrame(_: ?*anyopaque, _: ?*h.wl_touch) callconv(.c) void {}

fn touchCancel(_: ?*anyopaque, _: ?*h.wl_touch) callconv(.c) void {
    var iter = globals.touch_info.valueIterator();
    while (iter.next()) |info| {
        internal.eventFn(info.window.event_fn_data, .{ .touch_end = .{ .id = info.public_id, .ignore = true } });
    }
    globals.touch_ids = .empty;
    globals.touch_info.clearRetainingCapacity();
}

const fractional_scale_listener: h.wp_fractional_scale_v1_listener = .{
    .preferred_scale = fractionalScalePreferredScale,
};

fn fractionalScalePreferredScale(data: ?*anyopaque, _: ?*h.wp_fractional_scale_v1, scale: u32) callconv(.c) void {
    const self: *Window = @ptrCast(@alignCast(data orelse return));
    self.scale = @floatFromInt(scale);
    self.scale /= 120;
    internal.eventFn(self.event_fn_data, .{ .scale = self.scale });
}

const text_input_listener: h.zwp_text_input_v3_listener = .{
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
            h.zwp_text_input_v3_enable(globals.text_input);
            if (options.cursor) |cursor| {
                h.zwp_text_input_v3_set_cursor_rectangle(globals.text_input, cursor.x, cursor.y, 0, 0);
            }
            h.zwp_text_input_v3_commit(globals.text_input);
        }
    }
}

fn textInputLeave(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, surface: ?*h.wl_surface) callconv(.c) void {
    if (getWindow(surface)) |window| {
        if (window.text_options) |_| {
            h.zwp_text_input_v3_disable(globals.text_input);
            h.zwp_text_input_v3_commit(globals.text_input);
        }
    }
}

fn textInputPreeditString(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, text: [*c]const u8, cursor_begin: i32, cursor_end: i32) callconv(.c) void {
    if (globals.keyboard_focus != null) {
        globals.repeat_key = 0;
    }
    if (text == null) {
        globals.preedit_string.clearRetainingCapacity();
        globals.preedit_cursors = .{ 0, 0 };
        return;
    }
    globals.preedit_active = true;
    globals.preedit_string.replaceRange(internal.allocator, 0, globals.preedit_string.items.len, std.mem.sliceTo(text, 0)) catch {};
    globals.preedit_cursors = .{ cursor_begin, cursor_end };
}

fn textInputCommitString(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, text: [*c]const u8) callconv(.c) void {
    globals.commit_string.replaceRange(internal.allocator, 0, globals.commit_string.items.len, std.mem.sliceTo(text, 0)) catch {};
}

fn textInputDeleteSurroundingText(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, _: u32, _: u32) callconv(.c) void {}

fn textInputDone(_: ?*anyopaque, _: ?*h.zwp_text_input_v3, _: u32) callconv(.c) void {
    defer {
        globals.commit_string.clearRetainingCapacity();
        globals.preedit_string.clearRetainingCapacity();
    }

    if (globals.keyboard_focus) |window| {
        if (globals.preedit_active) {
            internal.eventFn(window.event_fn_data, .preview_reset);
            if (globals.preedit_string.items.len == 0) {
                globals.preedit_active = false;
            }
        }
        if (globals.commit_string.items.len > 0) {
            const view = std.unicode.Utf8View.init(globals.commit_string.items) catch return;
            var iter = view.iterator();
            while (iter.nextCodepoint()) |char| {
                internal.eventFn(window.event_fn_data, .{ .char = char });
            }
        }
        if (globals.preedit_string.items.len > 0) {
            const view = std.unicode.Utf8View.init(globals.preedit_string.items) catch return;
            var iter = view.iterator();
            var count: usize = 1;
            while (iter.nextCodepoint()) |char| : (count += 1) {
                internal.eventFn(window.event_fn_data, .{ .preview_char = char });
                // convert byte offset to codepoint offset
                for (&globals.preedit_cursors) |*cursor| {
                    if (cursor.* == iter.i) {
                        cursor.* = std.math.cast(i32, count) orelse -1;
                    }
                }
            }
            if (globals.preedit_cursors[0] != -1 and globals.preedit_cursors[1] != -1) {
                internal.eventFn(window.event_fn_data, .{ .preview_cursor = .{ std.math.cast(u16, globals.preedit_cursors[0]) orelse return, std.math.cast(u16, globals.preedit_cursors[1]) orelse return } });
            }
        }
    }
}

const data_device_listener: h.wl_data_device_listener = .{
    .data_offer = dataDeviceDataOffer,
    .enter = dataDeviceEnter,
    .leave = dataDeviceLeave,
    .motion = dataDeviceMotion,
    .drop = dataDeviceDrop,
    .selection = dataDeviceSelection,
};

fn dataDeviceDataOffer(_: ?*anyopaque, _: ?*h.wl_data_device, offer: ?*h.wl_data_offer) callconv(.c) void {
    if (build_options.drop) {
        globals.drop.pending_drag_has_uri = false;
        globals.drop.pending_drag_has_text = false;
        if (offer) |_| _ = h.wl_data_offer_add_listener(offer, &data_offer_listener, null);
    }
}

fn dataDeviceEnter(_: ?*anyopaque, _: ?*h.wl_data_device, serial: u32, surface: ?*h.wl_surface, _: h.wl_fixed_t, _: h.wl_fixed_t, offer: ?*h.wl_data_offer) callconv(.c) void {
    if (build_options.drop) {
        globals.drop.drag_serial = serial;
        globals.drop.drag_window = getWindow(surface);
        globals.drop.drag_offer = offer;
        globals.drop.drag_has_uri = globals.drop.pending_drag_has_uri;
        globals.drop.drag_has_text = globals.drop.pending_drag_has_text and !globals.drop.pending_drag_has_uri;
        globals.drop.drag_dropped = false;

        if (offer) |o| {
            if (globals.drop.drag_has_uri) {
                h.wl_data_offer_accept(o, serial, "text/uri-list");
            } else if (globals.drop.drag_has_text) {
                h.wl_data_offer_accept(o, serial, "text/plain;charset=utf-8");
            } else {
                h.wl_data_offer_accept(o, serial, null);
            }
        }

        if (globals.drop.drag_window) |window| {
            for (window.drop.files.items) |f| internal.allocator.free(f);
            window.drop.files.clearRetainingCapacity();
            if (window.drop.text) |t| internal.allocator.free(t);
            window.drop.text = null;
            internal.eventFn(window.event_fn_data, .drop_begin);
        }
    }
}

fn dataDeviceLeave(_: ?*anyopaque, _: ?*h.wl_data_device) callconv(.c) void {
    if (build_options.drop) {
        if (!globals.drop.drag_dropped) {
            if (globals.drop.drag_window) |window| internal.eventFn(window.event_fn_data, .drop_complete);
        }
        if (globals.drop.drag_offer) |o| {
            h.wl_data_offer_destroy(o);
            globals.drop.drag_offer = null;
        }
        globals.drop.drag_window = null;
    }
}

fn dataDeviceMotion(_: ?*anyopaque, _: ?*h.wl_data_device, _: u32, x: h.wl_fixed_t, y: h.wl_fixed_t) callconv(.c) void {
    if (build_options.drop) {
        if (globals.drop.drag_window) |window| {
            internal.eventFn(window.event_fn_data, .{
                .drop_position = .{
                    .x = std.math.cast(i16, x >> 8) orelse return,
                    .y = std.math.cast(i16, y >> 8) orelse return,
                },
            });
        }
    }
}

fn dataDeviceDrop(_: ?*anyopaque, _: ?*h.wl_data_device) callconv(.c) void {
    if (build_options.drop) {
        const window = globals.drop.drag_window orelse return;
        const offer = globals.drop.drag_offer orelse return;
        if (!globals.drop.drag_has_uri and !globals.drop.drag_has_text) return;

        const mime = if (globals.drop.drag_has_uri) "text/uri-list" else "text/plain;charset=utf-8";

        var pipe: [2]i32 = undefined;
        if (std.c.pipe(&pipe) == -1) {
            internal.eventFn(window.event_fn_data, .drop_complete);
            globals.drop.drag_dropped = true;
            return;
        }
        defer _ = std.c.close(pipe[0]);
        h.wl_data_offer_receive(offer, mime, pipe[1]);
        globals.drop.drag_dropped = true; // set before roundtrip so dataDeviceLeave doesn't double-emit
        _ = c.wl_display_roundtrip(globals.display);
        _ = std.c.close(pipe[1]);

        var buf: [4096]u8 = undefined;
        var total: usize = 0;
        while (total < buf.len) {
            const n = std.c.read(pipe[0], buf[total..].ptr, buf.len - total);
            if (std.c.errno(n) != .SUCCESS or n == 0) break;
            total += @intCast(n);
        }

        if (globals.drop.drag_has_uri) {
            var iter = std.mem.splitAny(u8, buf[0..total], "\r\n");
            while (iter.next()) |line| {
                if (line.len == 0 or line[0] == '#') continue;
                const prefix = "file://";
                if (!std.mem.startsWith(u8, line, prefix)) continue;
                const path = internal.allocator.dupe(u8, line[prefix.len..]) catch continue;
                window.drop.files.append(internal.allocator, std.Uri.percentDecodeInPlace(path)) catch {};
            }
        } else {
            if (internal.allocator.dupe(u8, buf[0..total])) |copy| {
                window.drop.text = copy;
            } else |_| {}
        }
        internal.eventFn(window.event_fn_data, .drop_complete);
    }
}

fn dataDeviceSelection(_: ?*anyopaque, _: ?*h.wl_data_device, offer: ?*h.wl_data_offer) callconv(.c) void {
    if (globals.data_offer) |_| h.wl_data_offer_destroy(globals.data_offer);
    globals.data_offer = offer;
}

const data_offer_listener: h.wl_data_offer_listener = .{
    .offer = dataOfferMime,
    .source_actions = dataOfferSourceActions,
    .action = dataOfferAction,
};

fn dataOfferMime(_: ?*anyopaque, _: ?*h.wl_data_offer, mime: [*c]const u8) callconv(.c) void {
    const s = std.mem.sliceTo(mime, 0);
    if (std.mem.eql(u8, s, "text/uri-list")) {
        globals.drop.pending_drag_has_uri = true;
    } else if (std.mem.eql(u8, s, "text/plain;charset=utf-8")) {
        globals.drop.pending_drag_has_text = true;
    }
}

fn dataOfferAction(_: ?*anyopaque, _: ?*h.wl_data_offer, _: u32) callconv(.c) void {}
fn dataOfferSourceActions(_: ?*anyopaque, _: ?*h.wl_data_offer, _: u32) callconv(.c) void {}

const data_source_listener: h.wl_data_source_listener = .{
    .target = dataSourceTarget,
    .send = dataSourceSend,
    .cancelled = dataSourceCancelled,
};

fn dataSourceTarget(_: ?*anyopaque, _: ?*h.wl_data_source, _: [*c]const u8) callconv(.c) void {}

fn dataSourceSend(_: ?*anyopaque, _: ?*h.wl_data_source, _: [*c]const u8, fd: i32) callconv(.c) void {
    defer _ = std.c.close(fd);
    _ = std.c.write(fd, globals.clipboard_text.ptr, globals.clipboard_text.len);
}

fn dataSourceCancelled(_: ?*anyopaque, _: ?*h.wl_data_source) callconv(.c) void {}

const activation_token_listener: h.xdg_activation_token_v1_listener = .{
    .done = activationTokenDone,
};

fn activationTokenDone(surface: ?*anyopaque, token: ?*h.xdg_activation_token_v1, string: [*c]const u8) callconv(.c) void {
    h.xdg_activation_v1_activate(globals.activation, string, @ptrCast(surface));
    h.xdg_activation_token_v1_destroy(token);
}

var libdecor_interface: h.libdecor_interface = .{
    .@"error" = libdecorError,
};

fn libdecorError(_: ?*h.libdecor, _: h.libdecor_error, message: [*c]const u8) callconv(.c) void {
    log.err("{s}", .{message});
}

var libdecor_frame_interface: h.libdecor_frame_interface = .{
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
    internal.eventFn(self.event_fn_data, .{ .mode = mode });

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
    internal.eventFn(self.event_fn_data, .close);
}

fn frameCommit(_: ?*h.libdecor_frame, data: ?*anyopaque) callconv(.c) void {
    const self: *Window = @ptrCast(@alignCast(data));
    internal.eventFn(self.event_fn_data, .draw);
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

const std = @import("std");
const wio = @import("../wio.zig");
const common = @import("common.zig");
const log = std.log.scoped(.wio);
const h = @cImport({
    @cInclude("wio-wayland.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-client-protocol.h");
    @cInclude("cursor-shape-v1-client-protocol.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-compose.h");
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
var libwayland_egl: std.DynLib = undefined;
var libEGL: std.DynLib = undefined;

pub var display: *h.wl_display = undefined;
var registry: *h.wl_registry = undefined;
var compositor: ?*h.wl_compositor = null;
var xdg_wm_base: ?*h.xdg_wm_base = null;
var seat: ?*h.wl_seat = null;
var keyboard: ?*h.wl_keyboard = null;
var pointer: ?*h.wl_pointer = null;
var cursor_shape_manager: ?*h.wp_cursor_shape_manager_v1 = null;
var cursor_shape_device: ?*h.wp_cursor_shape_device_v1 = null;

var xkb: *h.xkb_context = undefined;
var keymap: ?*h.xkb_keymap = null;
var xkb_state: ?*h.xkb_state = null;
var compose_state: ?*h.xkb_compose_state = null;

var focus: ?*@This() = null;
var pointer_enter_serial: u32 = 0;

var egl_display: h.EGLDisplay = undefined;

export var wio_wl_proxy_get_version: *const @TypeOf(h.wl_proxy_get_version) = undefined;
export var wio_wl_proxy_marshal_flags: *const @TypeOf(h.wl_proxy_marshal_flags) = undefined;
export var wio_wl_proxy_add_listener: *const @TypeOf(h.wl_proxy_add_listener) = undefined;
export var wio_wl_proxy_destroy: *const @TypeOf(h.wl_proxy_destroy) = undefined;
export var wio_wl_proxy_set_user_data: *const @TypeOf(h.wl_proxy_set_user_data) = undefined;
export var wio_wl_proxy_get_user_data: *const @TypeOf(h.wl_proxy_get_user_data) = undefined;

pub fn init(options: wio.InitOptions) !void {
    common.loadLibs(&c, &.{
        .{ .handle = &libxkbcommon, .name = "libxkbcommon.so.0", .prefix = "xkb" },
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
    errdefer if (compositor) |_| h.wl_compositor_destroy(compositor);
    errdefer if (xdg_wm_base) |_| h.xdg_wm_base_destroy(xdg_wm_base);
    errdefer if (seat) |_| h.wl_seat_destroy(seat);
    if (compositor == null or xdg_wm_base == null or seat == null) return error.Unexpected;

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

    c.xkb_compose_state_unref(compose_state);
    c.xkb_state_unref(xkb_state);
    c.xkb_keymap_unref(keymap);
    c.xkb_context_unref(xkb);
    libxkbcommon.close();

    if (cursor_shape_device) |_| h.wp_cursor_shape_device_v1_destroy(cursor_shape_device);
    if (cursor_shape_manager) |_| h.wp_cursor_shape_manager_v1_destroy(cursor_shape_manager);
    if (pointer) |_| h.wl_pointer_destroy(pointer);
    if (keyboard) |_| h.wl_keyboard_destroy(keyboard);
    h.wl_seat_destroy(seat);
    h.xdg_wm_base_destroy(xdg_wm_base);
    h.wl_compositor_destroy(compositor);
    h.wl_registry_destroy(registry);
    c.wl_display_disconnect(display);
    libwayland_client.close();
}

pub fn update() void {
    _ = c.wl_display_dispatch(display);
}

events: std.fifo.LinearFifo(wio.Event, .Dynamic),
surface: *h.wl_surface,
xdg_surface: *h.xdg_surface,
xdg_toplevel: *h.xdg_toplevel,
egl_window: ?*h.wl_egl_window = null,
egl_surface: h.EGLSurface = null,
egl_context: h.EGLContext = null,
size: wio.Size,
cursor: u32 = undefined,
cursor_mode: wio.CursorMode,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());

    const surface = h.wl_compositor_create_surface(compositor) orelse return error.Unexpected;
    errdefer h.wl_surface_destroy(surface);
    h.wl_surface_set_user_data(surface, self);

    const xdg_surface = h.xdg_wm_base_get_xdg_surface(xdg_wm_base, surface) orelse return error.Unexpected;
    errdefer h.xdg_surface_destroy(xdg_surface);
    _ = h.xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, null);

    const xdg_toplevel = h.xdg_surface_get_toplevel(xdg_surface) orelse return error.Unexpected;
    errdefer h.xdg_toplevel_destroy(xdg_toplevel);
    _ = h.xdg_toplevel_add_listener(xdg_toplevel, &xdg_toplevel_listener, self);

    self.* = .{
        .events = .init(wio.allocator),
        .surface = surface,
        .xdg_surface = xdg_surface,
        .xdg_toplevel = xdg_toplevel,
        .size = options.size,
        .cursor_mode = options.cursor_mode,
    };
    self.setTitle(options.title);
    self.setCursor(options.cursor);

    self.pushEvent(.{ .size = options.size });
    self.pushEvent(.{ .framebuffer = options.size });
    self.pushEvent(.create);

    h.wl_surface_commit(surface);
    _ = c.wl_display_roundtrip(display);
    self.setMode(options.mode);

    return self;
}

pub fn destroy(self: *@This()) void {
    if (focus == self) focus = null;
    if (self.egl_context) |_| _ = c.eglDestroyContext(egl_display, self.egl_context);
    if (self.egl_surface) |_| _ = c.eglDestroySurface(egl_display, self.egl_surface);
    if (self.egl_window) |_| c.wl_egl_window_destroy(self.egl_window);
    self.events.deinit();
    h.xdg_toplevel_destroy(self.xdg_toplevel);
    h.xdg_surface_destroy(self.xdg_surface);
    h.wl_surface_destroy(self.surface);
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_z = wio.allocator.dupeZ(u8, title) catch return;
    defer wio.allocator.free(title_z);
    h.xdg_toplevel_set_title(self.xdg_toplevel, title_z);
}

pub fn setSize(self: *@This(), size: wio.Size) void {
    _ = self;
    _ = size;
}

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    if (mode != .fullscreen) h.xdg_toplevel_unset_fullscreen(self.xdg_toplevel);
    switch (mode) {
        .normal => h.xdg_toplevel_unset_maximized(self.xdg_toplevel),
        .maximized => h.xdg_toplevel_set_maximized(self.xdg_toplevel),
        .fullscreen => h.xdg_toplevel_set_fullscreen(self.xdg_toplevel, null),
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
}

pub fn requestAttention(self: *@This()) void {
    _ = self;
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

pub fn messageBox(backend: ?*@This(), style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = backend;
    _ = style;
    _ = title;
    _ = message;
}

pub fn setClipboardText(text: []const u8) void {
    _ = text;
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    _ = allocator;
    return null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch return;
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

fn registryGlobal(_: ?*anyopaque, _: ?*h.wl_registry, name: u32, interface: [*c]const u8, _: u32) callconv(.C) void {
    const interface_z = std.mem.sliceTo(interface, 0);
    if (std.mem.eql(u8, interface_z, "wl_compositor")) {
        compositor = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_compositor_interface, 3));
    } else if (std.mem.eql(u8, interface_z, "xdg_wm_base")) {
        xdg_wm_base = @ptrCast(h.wl_registry_bind(registry, name, &h.xdg_wm_base_interface, 1));
        _ = h.xdg_wm_base_add_listener(xdg_wm_base, &xdg_wm_base_listener, null);
    } else if (std.mem.eql(u8, interface_z, "wl_seat")) {
        seat = @ptrCast(h.wl_registry_bind(registry, name, &h.wl_seat_interface, 3));
        _ = h.wl_seat_add_listener(seat, &seat_listener, null);
    } else if (std.mem.eql(u8, interface_z, "wp_cursor_shape_manager_v1")) {
        cursor_shape_manager = @ptrCast(h.wl_registry_bind(registry, name, &h.wp_cursor_shape_manager_v1_interface, 1));
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*h.wl_registry, _: u32) callconv(.C) void {}

const xdg_wm_base_listener = h.xdg_wm_base_listener{
    .ping = xdgWmBasePing,
};

fn xdgWmBasePing(_: ?*anyopaque, _: ?*h.xdg_wm_base, serial: u32) callconv(.C) void {
    h.xdg_wm_base_pong(xdg_wm_base, serial);
}

const xdg_surface_listener = h.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

fn xdgSurfaceConfigure(_: ?*anyopaque, xdg_surface: ?*h.xdg_surface, serial: u32) callconv(.C) void {
    h.xdg_surface_ack_configure(xdg_surface, serial);
}

const xdg_toplevel_listener = h.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
};

fn xdgToplevelConfigure(data: ?*anyopaque, _: ?*h.xdg_toplevel, width: i32, height: i32, states: ?*h.wl_array) callconv(.C) void {
    const self: *@This() = @alignCast(@ptrCast(data orelse return));

    var mode = wio.WindowMode.normal;
    var focused = false;

    for (@as([*]u32, @alignCast(@ptrCast(states.?.data.?)))[0 .. states.?.size / @sizeOf(u32)]) |state| {
        switch (state) {
            h.XDG_TOPLEVEL_STATE_MAXIMIZED => mode = .maximized,
            h.XDG_TOPLEVEL_STATE_FULLSCREEN => mode = .fullscreen,
            h.XDG_TOPLEVEL_STATE_ACTIVATED => focused = true,
            else => {},
        }
    }

    const size = if (width == 0 or height == 0) self.size else wio.Size{ .width = @intCast(width), .height = @intCast(height) };
    if (mode == .normal) self.size = size;

    self.pushEvent(if (focused) .focused else .unfocused);
    self.pushEvent(.{ .mode = mode });
    self.pushEvent(.{ .size = size });
    self.pushEvent(.{ .framebuffer = size });
    if (self.egl_window) |_| c.wl_egl_window_resize(self.egl_window, size.width, size.height, 0, 0);
}

fn xdgToplevelClose(data: ?*anyopaque, _: ?*h.xdg_toplevel) callconv(.C) void {
    const self: *@This() = @alignCast(@ptrCast(data orelse return));
    self.pushEvent(.close);
}

const seat_listener = h.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn seatCapabilities(_: ?*anyopaque, _: ?*h.wl_seat, capabilities: u32) callconv(.C) void {
    if (keyboard) |_| {
        h.wl_keyboard_release(keyboard);
        keyboard = null;
    }
    if (pointer) |_| {
        h.wl_pointer_release(pointer);
        pointer = null;
    }
    if (cursor_shape_device) |_| {
        h.wp_cursor_shape_device_v1_destroy(cursor_shape_device);
        cursor_shape_device = null;
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
    }
}

fn seatName(_: ?*anyopaque, _: ?*h.wl_seat, _: [*c]const u8) callconv(.C) void {}

const keyboard_listener = h.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
};

fn keyboardKeymap(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, fd: i32, size: u32) callconv(.C) void {
    defer _ = std.c.close(fd);
    c.xkb_keymap_unref(keymap);
    c.xkb_state_unref(xkb_state);

    const string = std.c.mmap(null, size, std.c.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
    defer _ = std.c.munmap(@alignCast(string), size);

    keymap = c.xkb_keymap_new_from_string(xkb, @ptrCast(string), h.XKB_KEYMAP_FORMAT_TEXT_V1, h.XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_state = c.xkb_state_new(keymap);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface, _: ?*h.wl_array) callconv(.C) void {
    focus = @alignCast(@ptrCast(h.wl_surface_get_user_data(surface)));
}

fn keyboardLeave(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, surface: ?*h.wl_surface) callconv(.C) void {
    if (focus) |window| {
        if (window.surface == surface) {
            focus = null;
        }
    }
    if (compose_state) |_| c.xkb_compose_state_reset(compose_state);
}

fn keyboardKey(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, _: u32, key: u32, state: u32) callconv(.C) void {
    if (focus) |window| {
        if (keyToButton(key)) |button| {
            if (state == h.WL_KEYBOARD_KEY_STATE_PRESSED) {
                window.pushEvent(.{ .button_press = button });
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
                if (char >= ' ' and char != 0x7F) window.pushEvent(.{ .char = char });
            } else {
                window.pushEvent(.{ .button_release = button });
            }
        }
    }
}

fn keyboardModifiers(_: ?*anyopaque, _: ?*h.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, _: u32) callconv(.C) void {
    _ = c.xkb_state_update_mask(xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, 0);
}

const pointer_listener = h.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
};

fn pointerEnter(_: ?*anyopaque, _: ?*h.wl_pointer, serial: u32, surface: ?*h.wl_surface, _: i32, _: i32) callconv(.C) void {
    pointer_enter_serial = serial;
    if (@as(?*@This(), @alignCast(@ptrCast(h.wl_surface_get_user_data(surface))))) |window| {
        window.applyCursor();
    }
}

fn pointerLeave(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, _: ?*h.wl_surface) callconv(.C) void {}

fn pointerMotion(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, surface_x: i32, surface_y: i32) callconv(.C) void {
    if (focus) |window| window.pushEvent(.{ .mouse = .{ .x = @intCast(surface_x >> 8), .y = @intCast(surface_y >> 8) } });
}

fn pointerButton(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, _: u32, button: u32, state: u32) callconv(.C) void {
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

fn pointerAxis(_: ?*anyopaque, _: ?*h.wl_pointer, _: u32, axis: u32, value: i32) callconv(.C) void {
    if (focus) |window| {
        const float = @as(f32, @floatFromInt(value)) / 2560;
        switch (axis) {
            h.WL_POINTER_AXIS_VERTICAL_SCROLL => window.pushEvent(.{ .scroll_vertical = float }),
            h.WL_POINTER_AXIS_HORIZONTAL_SCROLL => window.pushEvent(.{ .scroll_horizontal = float }),
            else => {},
        }
    }
}

fn keyToButton(key: u32) ?wio.Button {
    comptime var table: [126]wio.Button = undefined;
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
            else => .mouse_left,
        };
    };
    return if (key > 0 and key <= table.len and table[key - 1] != .mouse_left) table[key - 1] else null;
}

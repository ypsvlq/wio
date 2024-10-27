const std = @import("std");
const wio = @import("../wio.zig");
const unix = @import("../unix.zig");
const common = @import("common.zig");
const h = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/XKBlib.h");
    @cInclude("X11/Xcursor/Xcursor.h");
    @cInclude("X11/extensions/Xfixes.h");
    @cInclude("GL/glx.h");
    @cInclude("locale.h");
});
const log = std.log.scoped(.wio);

const EventQueue = std.fifo.LinearFifo(wio.Event, .Dynamic);

var c: extern struct {
    XkbOpenDisplay: *const @TypeOf(h.XkbOpenDisplay),
    XCloseDisplay: *const @TypeOf(h.XCloseDisplay),
    XInternAtom: *const @TypeOf(h.XInternAtom),
    XOpenIM: *const @TypeOf(h.XOpenIM),
    XCloseIM: *const @TypeOf(h.XCloseIM),
    XkbGetMap: *const @TypeOf(h.XkbGetMap),
    XkbFreeKeyboard: *const @TypeOf(h.XkbFreeKeyboard),
    XkbGetNames: *const @TypeOf(h.XkbGetNames),
    XGetDefault: *const @TypeOf(h.XGetDefault),
    XCreateWindow: *const @TypeOf(h.XCreateWindow),
    XDestroyWindow: *const @TypeOf(h.XDestroyWindow),
    XMapWindow: *const @TypeOf(h.XMapWindow),
    XChangeProperty: *const @TypeOf(h.XChangeProperty),
    XCreateIC: *const @TypeOf(h.XCreateIC),
    XDestroyIC: *const @TypeOf(h.XDestroyIC),
    XFree: *const @TypeOf(h.XFree),
    XNextEvent: *const @TypeOf(h.XNextEvent),
    XPending: *const @TypeOf(h.XPending),
    XFilterEvent: *const @TypeOf(h.XFilterEvent),
    XPeekEvent: *const @TypeOf(h.XPeekEvent),
    XGetWindowProperty: *const @TypeOf(h.XGetWindowProperty),
    Xutf8LookupString: *const @TypeOf(h.Xutf8LookupString),
    XConfigureWindow: *const @TypeOf(h.XConfigureWindow),
    XSendEvent: *const @TypeOf(h.XSendEvent),
    XcursorLibraryLoadCursor: *const @TypeOf(h.XcursorLibraryLoadCursor),
    XDefineCursor: *const @TypeOf(h.XDefineCursor),
    XFixesShowCursor: *const @TypeOf(h.XFixesShowCursor),
    XFixesHideCursor: *const @TypeOf(h.XFixesHideCursor),
    glXQueryExtensionsString: *const @TypeOf(h.glXQueryExtensionsString),
    glXGetProcAddress: *const @TypeOf(h.glXGetProcAddress),
    glXChooseFBConfig: *const @TypeOf(h.glXChooseFBConfig),
    glXCreateNewContext: *const @TypeOf(h.glXCreateNewContext),
    glXDestroyContext: *const @TypeOf(h.glXDestroyContext),
    glXMakeCurrent: *const @TypeOf(h.glXMakeCurrent),
    glXSwapBuffers: *const @TypeOf(h.glXSwapBuffers),
} = undefined;

var glx: struct {
    swapIntervalEXT: h.PFNGLXSWAPINTERVALEXTPROC = null,
} = .{};

var atoms: struct {
    WM_PROTOCOLS: h.Atom,
    WM_DELETE_WINDOW: h.Atom,
    _NET_WM_STATE: h.Atom,
    _NET_WM_STATE_MAXIMIZED_VERT: h.Atom,
    _NET_WM_STATE_MAXIMIZED_HORZ: h.Atom,
    _NET_WM_STATE_FULLSCREEN: h.Atom,
} = undefined;

var libX11: std.DynLib = undefined;
var libXcursor: std.DynLib = undefined;
var libXfixes: std.DynLib = undefined;
var libGL: std.DynLib = undefined;
var windows: std.AutoHashMap(h.Window, *@This()) = undefined;
pub var display: *h.Display = undefined;
var im: h.XIM = undefined;
var keycodes: [248]wio.Button = undefined;
var scale: f32 = 1;

pub fn init(options: wio.InitOptions) !void {
    common.loadLibs(&c, &.{
        .{ .handle = &libXcursor, .name = "libXcursor.so.1", .prefix = "Xcursor" },
        .{ .handle = &libXfixes, .name = "libXfixes.so.3", .prefix = "XFixes" },
        .{ .handle = &libGL, .name = "libGL.so.1", .prefix = "glX", .predicate = options.opengl },
        .{ .handle = &libX11, .name = "libX11.so.6" },
    }) catch return error.Unavailable;
    errdefer libX11.close();
    errdefer libXcursor.close();
    errdefer libXfixes.close();
    errdefer if (options.opengl) libGL.close();

    display = c.XkbOpenDisplay(null, null, null, null, null, null) orelse return error.Unavailable;
    errdefer _ = c.XCloseDisplay(display);

    inline for (@typeInfo(@TypeOf(atoms)).@"struct".fields) |field| {
        @field(atoms, field.name) = c.XInternAtom(display, field.name, h.False);
    }

    windows = std.AutoHashMap(h.Window, *@This()).init(wio.allocator);
    errdefer windows.deinit();

    _ = h.setlocale(h.LC_CTYPE, "");
    im = c.XOpenIM(display, null, null, null) orelse return error.Unexpected;
    errdefer _ = c.XCloseIM(im);

    const xkb: *h.XkbDescRec = c.XkbGetMap(display, h.XkbNamesMask, h.XkbUseCoreKbd) orelse return error.Unexpected;
    defer _ = c.XkbFreeKeyboard(xkb, 0, h.True);
    _ = c.XkbGetNames(display, h.XkbKeyNamesMask | h.XkbKeyAliasesMask, xkb);
    const names: *h.XkbNamesRec = xkb.names;

    var aliases = std.AutoHashMap([4]u8, wio.Button).init(wio.allocator);
    defer aliases.deinit();
    for (names.key_aliases[0..names.num_key_aliases]) |alias| {
        if (nameToButton(alias.alias)) |button| {
            try aliases.put(alias.real, button);
        }
    }

    for (&keycodes, names.keys[8..256]) |*keycode, key| {
        keycode.* = nameToButton(key.name) orelse aliases.get(key.name) orelse .mouse_left;
    }

    if (c.XGetDefault(display, "Xft", "dpi")) |string| {
        if (std.fmt.parseFloat(f32, std.mem.sliceTo(string, 0))) |dpi| {
            scale = dpi / 96;
        } else |_| {}
    }

    if (options.opengl) {
        if (c.glXQueryExtensionsString(display, h.DefaultScreen(display))) |extensions| {
            var iter = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
            while (iter.next()) |name| {
                if (std.mem.eql(u8, name, "GLX_EXT_swap_control")) {
                    glx.swapIntervalEXT = @ptrCast(c.glXGetProcAddress("glXSwapIntervalEXT"));
                }
            }
        }
    }
}

pub fn deinit() void {
    _ = c.XCloseIM(im);
    _ = c.XCloseDisplay(display);
    libGL.close();
    libXcursor.close();
    libX11.close();
    windows.deinit();
}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions, joystickFn: fn () void) !void {
    _ = options;
    var event: h.XEvent = undefined;
    while (try func()) {
        while (c.XPending(display) > 0) {
            _ = c.XNextEvent(display, &event);
            handle(&event);
        }
        if (wio.init_options.joystick) joystickFn();
    }
}

events: EventQueue,
window: h.Window,
ic: h.XIC,
cursor: bool = true,
context: h.GLXContext = null,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    errdefer wio.allocator.destroy(self);

    const size = options.size.multiply(scale / options.scale);
    var attributes: h.XSetWindowAttributes = undefined;
    attributes.event_mask = h.FocusChangeMask | h.ExposureMask | h.StructureNotifyMask | h.KeyPressMask | h.KeyReleaseMask | h.ButtonPressMask | h.ButtonReleaseMask | h.PointerMotionMask;
    const window = c.XCreateWindow(
        display,
        h.DefaultRootWindow(display),
        0,
        0,
        size.width,
        size.height,
        0,
        0,
        h.InputOutput,
        null,
        h.CWEventMask,
        &attributes,
    );
    errdefer _ = c.XDestroyWindow(display, window);
    _ = c.XMapWindow(display, window);

    const protocols = [_]h.Atom{atoms.WM_DELETE_WINDOW};
    _ = c.XChangeProperty(display, window, atoms.WM_PROTOCOLS, h.XA_ATOM, 32, h.PropModeReplace, @ptrCast(&protocols), protocols.len);

    const ic = c.XCreateIC(
        im,
        h.XNInputStyle,
        h.XIMPreeditNothing | h.XIMStatusNothing,
        h.XNClientWindow,
        window,
        @as(usize, 0),
    ) orelse return error.Unexpected;
    errdefer _ = c.XDestroyIC(ic);

    self.* = .{
        .events = EventQueue.init(wio.allocator),
        .window = window,
        .ic = ic,
    };
    self.setTitle(options.title);
    self.setMode(options.mode);
    if (options.cursor_mode != .normal) self.setCursorMode(options.cursor_mode);

    try self.events.writeItem(.{ .size = size });
    try self.events.writeItem(.{ .framebuffer = size });
    try self.events.writeItem(.{ .scale = scale });
    try self.events.writeItem(.create);

    try windows.put(window, self);
    return self;
}

pub fn destroy(self: *@This()) void {
    _ = windows.remove(self.window);
    if (self.context) |context| c.glXDestroyContext(display, context);
    _ = c.XDestroyIC(self.ic);
    _ = c.XDestroyWindow(display, self.window);
    self.events.deinit();
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    _ = c.XChangeProperty(display, self.window, h.XA_WM_NAME, h.XA_STRING, 8, h.PropModeReplace, title.ptr, @intCast(title.len));
}

pub fn setSize(self: *@This(), size: wio.Size) void {
    var changes: h.XWindowChanges = undefined;
    changes.width = size.width;
    changes.height = size.height;
    _ = c.XConfigureWindow(display, self.window, h.CWWidth | h.CWHeight, &changes);
}

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    var event = h.XEvent{
        .xclient = std.mem.zeroInit(h.XClientMessageEvent, .{
            .type = h.ClientMessage,
            .window = self.window,
            .message_type = atoms._NET_WM_STATE,
            .format = 32,
        }),
    };

    event.xclient.data.l = .{ if (mode == .fullscreen) 1 else 0, @bitCast(atoms._NET_WM_STATE_FULLSCREEN), 0, 1, 0 };
    _ = c.XSendEvent(display, h.DefaultRootWindow(display), h.False, h.SubstructureRedirectMask | h.SubstructureNotifyMask, &event);

    event.xclient.data.l = .{ if (mode == .maximized) 1 else 0, @bitCast(atoms._NET_WM_STATE_MAXIMIZED_VERT), @bitCast(atoms._NET_WM_STATE_MAXIMIZED_HORZ), 1, 0 };
    _ = c.XSendEvent(display, h.DefaultRootWindow(display), h.False, h.SubstructureRedirectMask | h.SubstructureNotifyMask, &event);
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    const name = switch (shape) {
        .arrow => "default",
        .arrow_busy => "progress",
        .busy => "wait",
        .text => "text",
        .hand => "pointer",
        .crosshair => "crosshair",
        .forbidden => "not-allowed",
        .move => "move",
        .size_ns => "ns-resize",
        .size_ew => "ew-resize",
        .size_nesw => "nesw-resize",
        .size_nwse => "nwse-resize",
    };
    const cursor = c.XcursorLibraryLoadCursor(display, name);
    _ = c.XDefineCursor(display, self.window, cursor);
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    switch (mode) {
        .normal => {
            if (!self.cursor) {
                c.XFixesShowCursor(display, self.window);
                self.cursor = true;
            }
        },
        .hidden => {
            if (self.cursor) {
                c.XFixesHideCursor(display, self.window);
                self.cursor = false;
            }
        },
        .relative => {},
    }
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    var count: c_int = undefined;
    const configs = c.glXChooseFBConfig(display, h.DefaultScreen(display), &[_]c_int{
        h.GLX_DOUBLEBUFFER,   if (options.doublebuffer) h.True else h.False,
        h.GLX_RED_SIZE,       options.red_bits,
        h.GLX_GREEN_SIZE,     options.green_bits,
        h.GLX_BLUE_SIZE,      options.blue_bits,
        h.GLX_ALPHA_SIZE,     options.alpha_bits,
        h.GLX_DEPTH_SIZE,     options.depth_bits,
        h.GLX_STENCIL_SIZE,   options.stencil_bits,
        h.GLX_SAMPLE_BUFFERS, if (options.samples != 0) 1 else 0,
        h.GLX_SAMPLES,        options.samples,
        h.None,
    }, &count) orelse {
        log.err("{s} failed", .{"glXChooseFBConfig"});
        return error.Unexpected;
    };
    defer _ = c.XFree(@ptrCast(configs));
    self.context = c.glXCreateNewContext(display, configs[0], h.GLX_RGBA_TYPE, null, h.True) orelse return error.Unexpected;
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = c.glXMakeCurrent(display, self.window, self.context);
}

pub fn swapBuffers(self: *@This()) void {
    c.glXSwapBuffers(display, self.window);
}

pub fn swapInterval(self: *@This(), interval: i32) void {
    if (glx.swapIntervalEXT) |swapIntervalEXT| {
        swapIntervalEXT(display, self.window, interval);
    }
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
    return c.glXGetProcAddress(name);
}

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch {};
}

fn handle(event: *h.XEvent) void {
    switch (event.type) {
        h.ClientMessage => {
            if (event.xclient.message_type == atoms.WM_PROTOCOLS) {
                if (event.xclient.data.l[0] == atoms.WM_DELETE_WINDOW) {
                    if (windows.get(event.xclient.window)) |window| {
                        window.pushEvent(.close);
                    }
                }
            }
        },
        h.FocusIn => {
            if (windows.get(event.xfocus.window)) |window| {
                window.pushEvent(.focused);
            }
        },
        h.FocusOut => {
            if (windows.get(event.xfocus.window)) |window| {
                window.pushEvent(.unfocused);
            }
        },
        h.Expose => {
            if (event.xexpose.count == 0) {
                if (windows.get(event.xexpose.window)) |window| {
                    window.pushEvent(.draw);
                }
            }
        },
        h.ConfigureNotify => {
            if (windows.get(event.xconfigure.window)) |window| {
                var states: [*]c_long = undefined;
                var actual_type: h.Atom = undefined;
                var actual_format: c_int = undefined;
                var count: c_ulong = undefined;
                var bytes_after: c_ulong = undefined;
                _ = c.XGetWindowProperty(display, window.window, atoms._NET_WM_STATE, 0, 1024, h.False, h.XA_ATOM, &actual_type, &actual_format, &count, &bytes_after, @ptrCast(&states));
                defer _ = c.XFree(states);

                var mode = wio.WindowMode.normal;
                var maximized_vert = false;
                var maximized_horz = false;
                if (actual_type == h.XA_ATOM and actual_format == 32) {
                    for (states[0..count]) |state| {
                        if (state == atoms._NET_WM_STATE_MAXIMIZED_VERT) {
                            maximized_vert = true;
                        } else if (state == atoms._NET_WM_STATE_MAXIMIZED_HORZ) {
                            maximized_horz = true;
                        } else if (state == atoms._NET_WM_STATE_FULLSCREEN) {
                            mode = .fullscreen;
                        }
                    }
                }
                if (mode == .normal and maximized_horz and maximized_vert) mode = .maximized;
                window.pushEvent(.{ .mode = mode });

                const size = wio.Size{ .width = @intCast(event.xconfigure.width), .height = @intCast(event.xconfigure.height) };
                window.pushEvent(.{ .size = size });
                window.pushEvent(.{ .framebuffer = size });
            }
        },
        h.KeyPress => {
            if (c.XFilterEvent(event, event.xkey.window) == h.True) return;
            handleKeyPress(event);
        },
        h.KeyRelease => {
            if (c.XPending(display) > 0) {
                // key repeats are sent as a consecutive release and press
                var next: h.XEvent = undefined;
                _ = c.XPeekEvent(display, &next);
                if (next.type == h.KeyPress and next.xkey.time == event.xkey.time) {
                    _ = c.XNextEvent(display, &next);
                    handleKeyPress(&next);
                    return;
                }
            }
            if (windows.get(event.xkey.window)) |window| {
                const button = keycodes[event.xkey.keycode - 8];
                if (button != .mouse_left) window.pushEvent(.{ .button_release = button });
            }
        },
        h.ButtonPress => {
            if (windows.get(event.xbutton.window)) |window| {
                const button: wio.Button = switch (event.xbutton.button) {
                    1 => .mouse_left,
                    2 => .mouse_middle,
                    3 => .mouse_right,
                    4 => return window.pushEvent(.{ .scroll_vertical = -1 }),
                    5 => return window.pushEvent(.{ .scroll_vertical = 1 }),
                    6 => return window.pushEvent(.{ .scroll_horizontal = -1 }),
                    7 => return window.pushEvent(.{ .scroll_horizontal = 1 }),
                    8 => .mouse_back,
                    9 => .mouse_forward,
                    else => return,
                };
                window.pushEvent(.{ .button_press = button });
            }
        },
        h.ButtonRelease => {
            if (windows.get(event.xbutton.window)) |window| {
                const button: wio.Button = switch (event.xbutton.button) {
                    1 => .mouse_left,
                    2 => .mouse_middle,
                    3 => .mouse_right,
                    8 => .mouse_back,
                    9 => .mouse_forward,
                    else => return,
                };
                window.pushEvent(.{ .button_release = button });
            }
        },
        h.MotionNotify => {
            if (windows.get(event.xmotion.window)) |window| {
                const x = std.math.cast(u16, event.xmotion.x) orelse return;
                const y = std.math.cast(u16, event.xmotion.y) orelse return;
                window.pushEvent(.{ .mouse = .{ .x = x, .y = y } });
            }
        },
        else => {},
    }
}

fn handleKeyPress(event: *h.XEvent) void {
    if (windows.get(event.xkey.window)) |window| {
        if (event.xkey.keycode != 0) {
            const button = keycodes[event.xkey.keycode - 8];
            if (button != .mouse_left) {
                window.pushEvent(.{ .button_press = button });
            }
        }

        var stack: [4]u8 = undefined;
        const len = c.Xutf8LookupString(window.ic, &event.xkey, &stack, stack.len, null, null);
        var slice: []u8 = undefined;
        if (len > stack.len) {
            slice = wio.allocator.alloc(u8, @intCast(len)) catch return;
            _ = c.Xutf8LookupString(window.ic, &event.xkey, slice.ptr, len, null, null);
        } else {
            slice = stack[0..@intCast(len)];
        }
        defer if (len > stack.len) wio.allocator.free(slice);

        const view = std.unicode.Utf8View.init(slice) catch return;
        var iter = view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (codepoint >= ' ' and codepoint != 0x7F) {
                window.pushEvent(.{ .char = codepoint });
            }
        }
    }
}

fn nameToButton(name: [4]u8) ?wio.Button {
    const kvs = [_]struct { *const [4]u8, wio.Button }{
        .{ "ESC\x00", .escape },
        .{ "AE01", .@"1" },
        .{ "AE02", .@"2" },
        .{ "AE03", .@"3" },
        .{ "AE04", .@"4" },
        .{ "AE05", .@"5" },
        .{ "AE06", .@"6" },
        .{ "AE07", .@"7" },
        .{ "AE08", .@"8" },
        .{ "AE09", .@"9" },
        .{ "AE10", .@"0" },
        .{ "AE11", .minus },
        .{ "AE12", .equals },
        .{ "BKSP", .backspace },
        .{ "TAB\x00", .tab },
        .{ "AD01", .q },
        .{ "AD02", .w },
        .{ "AD03", .e },
        .{ "AD04", .r },
        .{ "AD05", .t },
        .{ "AD06", .y },
        .{ "AD07", .u },
        .{ "AD08", .i },
        .{ "AD09", .o },
        .{ "AD10", .p },
        .{ "AD11", .left_bracket },
        .{ "AD12", .right_bracket },
        .{ "RTRN", .enter },
        .{ "LCTL", .left_control },
        .{ "AC01", .a },
        .{ "AC02", .s },
        .{ "AC03", .d },
        .{ "AC04", .f },
        .{ "AC05", .g },
        .{ "AC06", .h },
        .{ "AC07", .j },
        .{ "AC08", .k },
        .{ "AC09", .l },
        .{ "AC10", .semicolon },
        .{ "AC11", .apostrophe },
        .{ "TLDE", .grave },
        .{ "LFSH", .left_shift },
        .{ "BKSL", .backslash },
        .{ "AB01", .z },
        .{ "AB02", .x },
        .{ "AB03", .c },
        .{ "AB04", .v },
        .{ "AB05", .b },
        .{ "AB06", .n },
        .{ "AB07", .m },
        .{ "AB08", .comma },
        .{ "AB09", .dot },
        .{ "AB10", .slash },
        .{ "RTSH", .right_shift },
        .{ "KPMU", .kp_star },
        .{ "LALT", .left_alt },
        .{ "SPCE", .space },
        .{ "CAPS", .caps_lock },
        .{ "FK01", .f1 },
        .{ "FK02", .f2 },
        .{ "FK03", .f3 },
        .{ "FK04", .f4 },
        .{ "FK05", .f5 },
        .{ "FK06", .f6 },
        .{ "FK07", .f7 },
        .{ "FK08", .f8 },
        .{ "FK09", .f9 },
        .{ "FK10", .f10 },
        .{ "NMLK", .num_lock },
        .{ "SCLK", .scroll_lock },
        .{ "KP7\x00", .kp_7 },
        .{ "KP8\x00", .kp_8 },
        .{ "KP9\x00", .kp_9 },
        .{ "KPSU", .kp_minus },
        .{ "KP4\x00", .kp_4 },
        .{ "KP5\x00", .kp_5 },
        .{ "KP6\x00", .kp_6 },
        .{ "KPAD", .kp_plus },
        .{ "KP1\x00", .kp_1 },
        .{ "KP2\x00", .kp_2 },
        .{ "KP3\x00", .kp_3 },
        .{ "KP0\x00", .kp_0 },
        .{ "KPDL", .kp_dot },
        .{ "LSGT", .iso_backslash },
        .{ "FK11", .f11 },
        .{ "FK12", .f12 },
        .{ "AB11", .international1 },
        .{ "HENK", .international4 },
        .{ "HKTG", .international2 },
        .{ "MUHE", .international5 },
        .{ "KPEN", .kp_enter },
        .{ "RCTL", .right_control },
        .{ "KPDV", .kp_slash },
        .{ "PRSC", .print_screen },
        .{ "RALT", .right_alt },
        .{ "HOME", .home },
        .{ "UP\x00\x00", .up },
        .{ "PGUP", .page_up },
        .{ "LEFT", .left },
        .{ "RGHT", .right },
        .{ "END\x00", .end },
        .{ "DOWN", .down },
        .{ "PGDN", .page_down },
        .{ "INS\x00", .insert },
        .{ "DELE", .delete },
        .{ "KPEQ", .kp_equals },
        .{ "PAUS", .pause },
        .{ "KPPT", .kp_comma },
        .{ "HNGL", .lang1 },
        .{ "HJCV", .lang2 },
        .{ "AE13", .international3 },
        .{ "LWIN", .left_gui },
        .{ "RWIN", .right_gui },
        .{ "COMP", .application },
    };
    comptime var keys: [kvs.len]u32 = undefined;
    comptime var values: [kvs.len]wio.Button = undefined;
    comptime for (&keys, &values, kvs) |*key, *value, kv| {
        key.* = @bitCast(kv[0].*);
        value.* = kv[1];
    };
    for (keys, values) |key, value| if (key == @as(u32, @bitCast(name))) return value;
    return null;
}

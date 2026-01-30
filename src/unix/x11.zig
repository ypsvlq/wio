const std = @import("std");
const build_options = @import("build_options");
const wio = @import("../wio.zig");
const internal = @import("../wio.internal.zig");
const unix = @import("../unix.zig");
const DynLib = @import("DynLib.zig");
const h = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/XKBlib.h");
    @cInclude("X11/Xcursor/Xcursor.h");
    @cInclude("GL/glx.h");
});
const log = std.log.scoped(.wio);

var imports: extern struct {
    XkbOpenDisplay: *const @TypeOf(h.XkbOpenDisplay),
    XCloseDisplay: *const @TypeOf(h.XCloseDisplay),
    XInternAtoms: *const @TypeOf(h.XInternAtoms),
    XSetLocaleModifiers: *const @TypeOf(h.XSetLocaleModifiers),
    XOpenIM: *const @TypeOf(h.XOpenIM),
    XCloseIM: *const @TypeOf(h.XCloseIM),
    XGetIMValues: *const @TypeOf(h.XGetIMValues),
    XFree: *const @TypeOf(h.XFree),
    XkbGetMap: *const @TypeOf(h.XkbGetMap),
    XkbFreeKeyboard: *const @TypeOf(h.XkbFreeKeyboard),
    XkbGetNames: *const @TypeOf(h.XkbGetNames),
    XGetDefault: *const @TypeOf(h.XGetDefault),
    XFlush: *const @TypeOf(h.XFlush),
    XCreateWindow: *const @TypeOf(h.XCreateWindow),
    XDestroyWindow: *const @TypeOf(h.XDestroyWindow),
    XMapWindow: *const @TypeOf(h.XMapWindow),
    XChangeProperty: *const @TypeOf(h.XChangeProperty),
    XVaCreateNestedList: *const @TypeOf(h.XVaCreateNestedList),
    XCreateIC: *const @TypeOf(h.XCreateIC),
    XDestroyIC: *const @TypeOf(h.XDestroyIC),
    XNextEvent: *const @TypeOf(h.XNextEvent),
    XPending: *const @TypeOf(h.XPending),
    XFilterEvent: *const @TypeOf(h.XFilterEvent),
    XPeekEvent: *const @TypeOf(h.XPeekEvent),
    XGetWindowProperty: *const @TypeOf(h.XGetWindowProperty),
    Xutf8LookupString: *const @TypeOf(h.Xutf8LookupString),
    XSendEvent: *const @TypeOf(h.XSendEvent),
    XSetICValues: *const @TypeOf(h.XSetICValues),
    XResizeWindow: *const @TypeOf(h.XResizeWindow),
    XReparentWindow: *const @TypeOf(h.XReparentWindow),
    XcursorLibraryLoadCursor: *const @TypeOf(h.XcursorLibraryLoadCursor),
    XDefineCursor: *const @TypeOf(h.XDefineCursor),
    XCreatePixmap: *const @TypeOf(h.XCreatePixmap),
    XCreateGC: *const @TypeOf(h.XCreateGC),
    XFreeGC: *const @TypeOf(h.XFreeGC),
    XDrawPoint: *const @TypeOf(h.XDrawPoint),
    XCreatePixmapCursor: *const @TypeOf(h.XCreatePixmapCursor),
    XGrabPointer: *const @TypeOf(h.XGrabPointer),
    XUngrabPointer: *const @TypeOf(h.XUngrabPointer),
    XWarpPointer: *const @TypeOf(h.XWarpPointer),
    XSetSelectionOwner: *const @TypeOf(h.XSetSelectionOwner),
    XConvertSelection: *const @TypeOf(h.XConvertSelection),
    XCheckTypedWindowEvent: *const @TypeOf(h.XCheckTypedWindowEvent),
    XCreateColormap: *const @TypeOf(h.XCreateColormap),
    XFreeColormap: *const @TypeOf(h.XFreeColormap),
    glXQueryExtensionsString: *const @TypeOf(h.glXQueryExtensionsString),
    glXGetProcAddress: *const @TypeOf(h.glXGetProcAddress),
    glXChooseFBConfig: *const @TypeOf(h.glXChooseFBConfig),
    glXGetVisualFromFBConfig: *const @TypeOf(h.glXGetVisualFromFBConfig),
    glXCreateNewContext: *const @TypeOf(h.glXCreateNewContext),
    glXDestroyContext: *const @TypeOf(h.glXDestroyContext),
    glXMakeCurrent: *const @TypeOf(h.glXMakeCurrent),
    glXSwapBuffers: *const @TypeOf(h.glXSwapBuffers),
} = undefined;
const c = if (build_options.system_integration) h else &imports;

var glx: struct {
    swapIntervalEXT: h.PFNGLXSWAPINTERVALEXTPROC = null,
    createContextAttribsARB: h.PFNGLXCREATECONTEXTATTRIBSARBPROC = null,
} = .{};

var atoms: extern struct {
    WM_PROTOCOLS: h.Atom,
    WM_DELETE_WINDOW: h.Atom,
    _NET_WM_STATE: h.Atom,
    _NET_WM_STATE_MAXIMIZED_VERT: h.Atom,
    _NET_WM_STATE_MAXIMIZED_HORZ: h.Atom,
    _NET_WM_STATE_FULLSCREEN: h.Atom,
    _NET_WM_STATE_DEMANDS_ATTENTION: h.Atom,
    CLIPBOARD: h.Atom,
    UTF8_STRING: h.Atom,
    TARGETS: h.Atom,
    INCR: h.Atom,
    SELECTION: h.Atom,
} = undefined;

var libX11: DynLib = undefined;
var libXcursor: DynLib = undefined;
var libGL: DynLib = undefined;
var windows: std.AutoHashMapUnmanaged(h.Window, *Window) = undefined;
pub var display: *h.Display = undefined;
var im: h.XIM = undefined;
var im_style: h.XIMStyle = 0;
var keycodes: [248]wio.Button = undefined;
var scale: f32 = 1;
var clipboard_text: []const u8 = "";

pub fn init() !bool {
    DynLib.load(&imports, &.{
        .{ .handle = &libXcursor, .name = "libXcursor.so.1", .prefix = "Xcursor" },
        .{ .handle = &libX11, .name = "libX11.so.6", .prefix = "X" },
    }) catch return false;
    errdefer libX11.close();
    errdefer libXcursor.close();

    if (build_options.opengl) {
        DynLib.load(&imports, &.{.{ .handle = &libGL, .name = "libGL.so.1", .prefix = "glX" }}) catch return false;
    }
    errdefer if (build_options.opengl) libGL.close();

    display = c.XkbOpenDisplay(null, null, null, null, null, null) orelse return false;
    errdefer _ = c.XCloseDisplay(display);
    try unix.pollfds.append(internal.allocator, .{ .fd = h.ConnectionNumber(display), .events = std.c.POLL.IN, .revents = undefined });

    var atom_names: [@typeInfo(@TypeOf(atoms)).@"struct".fields.len][*:0]const u8 = undefined;
    for (&atom_names, std.meta.fieldNames(@TypeOf(atoms))) |*name_z, name| name_z.* = name;
    _ = c.XInternAtoms(display, @ptrCast(&atom_names), atom_names.len, h.False, @ptrCast(&atoms));

    windows = .empty;
    errdefer windows.deinit(internal.allocator);

    _ = std.c.setlocale(.CTYPE, "");
    _ = c.XSetLocaleModifiers("");
    im = c.XOpenIM(display, null, null, null) orelse return error.Unexpected;
    errdefer _ = c.XCloseIM(im);

    var im_styles: *h.XIMStyles = undefined;
    if (c.XGetIMValues(im, h.XNQueryInputStyle, &im_styles, @as(usize, 0)) != null) return error.Unexpected;
    defer _ = c.XFree(im_styles);

    const supported_styles = im_styles.supported_styles[0..im_styles.count_styles];
    const preferred_styles = [_]h.XIMStyle{
        h.XIMPreeditCallbacks | h.XIMStatusNothing,
        h.XIMPreeditNothing | h.XIMStatusNothing,
    };
    for (preferred_styles) |style| {
        if (std.mem.indexOfScalar(h.XIMStyle, supported_styles, style) != null) {
            im_style = style;
            break;
        }
    }

    const xkb: *h.XkbDescRec = c.XkbGetMap(display, h.XkbNamesMask, h.XkbUseCoreKbd) orelse return error.Unexpected;
    defer _ = c.XkbFreeKeyboard(xkb, 0, h.True);
    _ = c.XkbGetNames(display, h.XkbKeyNamesMask | h.XkbKeyAliasesMask, xkb);
    const names: *h.XkbNamesRec = xkb.names;

    var aliases: std.AutoHashMapUnmanaged([4]u8, wio.Button) = .empty;
    defer aliases.deinit(internal.allocator);
    for (names.key_aliases[0..names.num_key_aliases]) |alias| {
        if (nameToButton(alias.alias)) |button| {
            try aliases.put(internal.allocator, alias.real, button);
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

    if (build_options.opengl) {
        if (c.glXQueryExtensionsString(display, h.DefaultScreen(display))) |extensions| {
            var iter = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
            while (iter.next()) |name| {
                if (std.mem.eql(u8, name, "GLX_ARB_create_context_profile")) {
                    glx.createContextAttribsARB = @ptrCast(c.glXGetProcAddress("glXCreateContextAttribsARB"));
                } else if (std.mem.eql(u8, name, "GLX_EXT_swap_control")) {
                    glx.swapIntervalEXT = @ptrCast(c.glXGetProcAddress("glXSwapIntervalEXT"));
                }
            }
        }
    }

    return true;
}

pub fn deinit() void {
    internal.allocator.free(clipboard_text);
    _ = c.XCloseIM(im);
    _ = c.XCloseDisplay(display);
    if (build_options.opengl) libGL.close();
    libXcursor.close();
    libX11.close();
    windows.deinit(internal.allocator);
}

pub fn update() void {
    var event: h.XEvent = undefined;
    while (c.XPending(display) > 0) {
        _ = c.XNextEvent(display, &event);
        handle(&event);
    }
}

pub fn createWindow(options: wio.CreateWindowOptions) !*Window {
    var attributes: h.XSetWindowAttributes = undefined;
    attributes.event_mask = h.PropertyChangeMask | h.FocusChangeMask | h.ExposureMask | h.StructureNotifyMask | h.KeyPressMask | h.KeyReleaseMask | h.ButtonPressMask | h.ButtonReleaseMask | h.PointerMotionMask;
    attributes.colormap = h.CopyFromParent;

    var depth: c_int = h.CopyFromParent;
    var visual: ?*h.Visual = null;
    var context: h.GLXContext = null;
    if (build_options.opengl) {
        if (options.opengl) |opengl| {
            var count: c_int = undefined;
            const configs = c.glXChooseFBConfig(display, h.DefaultScreen(display), &[_]c_int{
                h.GLX_DOUBLEBUFFER,   if (opengl.doublebuffer) h.True else h.False,
                h.GLX_RED_SIZE,       opengl.red_bits,
                h.GLX_GREEN_SIZE,     opengl.green_bits,
                h.GLX_BLUE_SIZE,      opengl.blue_bits,
                h.GLX_ALPHA_SIZE,     opengl.alpha_bits,
                h.GLX_DEPTH_SIZE,     opengl.depth_bits,
                h.GLX_STENCIL_SIZE,   opengl.stencil_bits,
                h.GLX_SAMPLE_BUFFERS, if (opengl.samples != 0) 1 else 0,
                h.GLX_SAMPLES,        opengl.samples,
                h.None,
            }, &count) orelse return internal.logUnexpected("glXChooseFBConfig");
            defer _ = c.XFree(@ptrCast(configs));

            const config = configs[0];

            const info: *h.XVisualInfo = c.glXGetVisualFromFBConfig(display, config) orelse return internal.logUnexpected("glXGetVisualFromFBConfig");
            defer _ = c.XFree(info);
            visual = info.visual;
            depth = info.depth;

            attributes.colormap = c.XCreateColormap(display, h.DefaultRootWindow(display), visual, h.AllocNone);
            errdefer _ = c.XFreeColormap(display, attributes.colormap);

            context = if (glx.createContextAttribsARB) |createContextAttribsARB|
                createContextAttribsARB(display, config, null, h.True, &[_]c_int{
                    h.GLX_CONTEXT_MAJOR_VERSION_ARB, opengl.major_version,
                    h.GLX_CONTEXT_MINOR_VERSION_ARB, opengl.minor_version,
                    h.GLX_CONTEXT_FLAGS_ARB,         (if (opengl.forward_compatible) h.GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB else 0) | (if (opengl.debug) h.GLX_CONTEXT_DEBUG_BIT_ARB else 0),
                    h.GLX_CONTEXT_PROFILE_MASK_ARB,  if (opengl.profile == .core) h.GLX_CONTEXT_CORE_PROFILE_BIT_ARB else h.GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
                    h.None,
                }) orelse return internal.logUnexpected("glXCreateContextAttribsARB")
            else
                c.glXCreateNewContext(display, config, h.GLX_RGBA_TYPE, null, h.True) orelse return internal.logUnexpected("glXCreateNewContext");
        }
    }
    errdefer if (build_options.opengl) {
        if (options.opengl != null) {
            c.glXDestroyContext(display, context);
            _ = c.XFreeColormap(display, attributes.colormap);
        }
    };

    const size = if (options.scale) |base| options.size.multiply(scale / base) else options.size;
    const window = c.XCreateWindow(
        display,
        if (options.parent != 0) options.parent else h.DefaultRootWindow(display),
        0,
        0,
        size.width,
        size.height,
        0,
        depth,
        h.InputOutput,
        visual,
        h.CWEventMask | h.CWColormap,
        &attributes,
    );
    errdefer _ = c.XDestroyWindow(display, window);
    _ = c.XMapWindow(display, window);

    const protocols = [_]h.Atom{atoms.WM_DELETE_WINDOW};
    _ = c.XChangeProperty(display, window, atoms.WM_PROTOCOLS, h.XA_ATOM, 32, h.PropModeReplace, @ptrCast(&protocols), protocols.len);

    const self = try internal.allocator.create(Window);
    errdefer internal.allocator.destroy(self);

    const preedit_attributes = c.XVaCreateNestedList(
        0,
        h.XNPreeditStartCallback,
        &h.XIMCallback{ .callback = @ptrCast(&preeditStart) },
        h.XNPreeditDoneCallback,
        &h.XIMCallback{ .client_data = @ptrCast(self), .callback = @ptrCast(&preeditDone) },
        h.XNPreeditDrawCallback,
        &h.XIMCallback{ .client_data = @ptrCast(self), .callback = @ptrCast(&preeditDraw) },
        @as(usize, 0),
    );
    defer _ = c.XFree(preedit_attributes);

    const ic = c.XCreateIC(
        im,
        h.XNInputStyle,
        im_style,
        h.XNClientWindow,
        window,
        h.XNPreeditAttributes,
        preedit_attributes,
        @as(usize, 0),
    ) orelse return internal.logUnexpected("XCreateIC");
    errdefer _ = c.XDestroyIC(ic);

    self.* = .{
        .events = .init(),
        .window = window,
        .ic = ic,
        .size = options.size,
        .opengl = if (build_options.opengl) .{ .colormap = attributes.colormap, .context = context } else .{},
    };

    self.setTitle(options.title);
    self.setMode(options.mode);

    self.events.push(.visible);
    self.events.push(.{ .scale = scale });
    self.events.push(.{ .size = size });
    self.events.push(.{ .framebuffer = size });
    self.events.push(.draw);

    try windows.put(internal.allocator, window, self);
    return self;
}

pub const Window = struct {
    events: internal.EventQueue,
    window: h.Window,
    ic: h.XIC,
    text: bool = false,
    preedit_string: std.ArrayList(u21) = .empty,
    cursor: h.Cursor = h.None,
    cursor_mode: wio.CursorMode = .normal,
    size: wio.Size,
    warped: bool = false,
    opengl: if (build_options.opengl) struct {
        colormap: h.Colormap,
        context: h.GLXContext,
    } else struct {},

    pub fn destroy(self: *Window) void {
        _ = windows.remove(self.window);

        if (build_options.opengl) {
            if (self.opengl.context) |context| c.glXDestroyContext(display, context);
            if (self.opengl.colormap != h.CopyFromParent) _ = c.XFreeColormap(display, self.opengl.colormap);
        }
        _ = c.XDestroyIC(self.ic);
        _ = c.XDestroyWindow(display, self.window);
        _ = c.XFlush(display);

        self.preedit_string.deinit(internal.allocator);
        self.events.deinit();
        internal.allocator.destroy(self);
    }

    pub fn getEvent(self: *Window) ?wio.Event {
        return self.events.pop();
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        self.text = true;
        if (options.cursor) |cursor| {
            const attributes = c.XVaCreateNestedList(0, h.XNSpotLocation, &h.XPoint{ .x = std.math.cast(c_short, cursor.x) orelse return, .y = std.math.cast(c_short, cursor.y) orelse return }, @as(usize, 0));
            defer _ = c.XFree(attributes);
            _ = c.XSetICValues(self.ic, h.XNPreeditAttributes, attributes, @as(usize, 0));
        }
    }

    pub fn disableTextInput(self: *Window) void {
        self.text = false;
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        _ = c.XChangeProperty(display, self.window, h.XA_WM_NAME, h.XA_STRING, 8, h.PropModeReplace, title.ptr, std.math.cast(c_int, title.len) orelse return);
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
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

    pub fn setSize(self: *Window, size: wio.Size) void {
        _ = c.XResizeWindow(display, self.window, size.width, size.height);
    }

    pub fn setParent(self: *Window, parent: usize) void {
        _ = c.XReparentWindow(display, self.window, parent, 0, 0);
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
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
        self.cursor = c.XcursorLibraryLoadCursor(display, name);
        if (self.cursor_mode == .normal) {
            _ = c.XDefineCursor(display, self.window, self.cursor);
        }
    }

    pub fn setCursorMode(self: *Window, mode: wio.CursorMode) void {
        self.cursor_mode = mode;
        if (mode == .normal) {
            _ = c.XDefineCursor(display, self.window, self.cursor);
        } else {
            const pixmap = c.XCreatePixmap(display, self.window, 1, 1, 1);
            const gc = c.XCreateGC(display, pixmap, 0, null);
            defer _ = c.XFreeGC(display, gc);
            _ = c.XDrawPoint(display, pixmap, gc, 0, 0);
            var color = std.mem.zeroes(h.XColor);
            const cursor = c.XCreatePixmapCursor(display, pixmap, pixmap, &color, &color, 0, 0);
            _ = c.XDefineCursor(display, self.window, cursor);
        }
        if (mode == .relative) {
            _ = c.XGrabPointer(display, self.window, h.True, 0, h.GrabModeAsync, h.GrabModeAsync, self.window, h.None, h.CurrentTime);
            self.warped = false;
        } else {
            _ = c.XUngrabPointer(display, h.CurrentTime);
        }
    }

    pub fn requestAttention(self: *Window) void {
        var event = h.XEvent{
            .xclient = .{
                .type = h.ClientMessage,
                .serial = undefined,
                .send_event = undefined,
                .display = undefined,
                .window = self.window,
                .message_type = atoms._NET_WM_STATE,
                .format = 32,
                .data = .{
                    .l = .{ 1, @as(c_long, @bitCast(atoms._NET_WM_STATE_DEMANDS_ATTENTION)), 0, 1, 0 },
                },
            },
        };
        _ = c.XSendEvent(display, h.DefaultRootWindow(display), h.False, h.SubstructureRedirectMask | h.SubstructureNotifyMask, &event);
    }

    pub fn setClipboardText(self: *Window, text: []const u8) void {
        internal.allocator.free(clipboard_text);
        clipboard_text = internal.allocator.dupe(u8, text) catch "";
        _ = c.XSetSelectionOwner(display, atoms.CLIPBOARD, self.window, h.CurrentTime);
    }

    pub fn getClipboardText(self: *Window, allocator: std.mem.Allocator) ?[]u8 {
        _ = c.XConvertSelection(display, atoms.CLIPBOARD, atoms.UTF8_STRING, atoms.SELECTION, self.window, h.CurrentTime);
        var event: h.XEvent = undefined;
        while (c.XCheckTypedWindowEvent(display, self.window, h.SelectionNotify, &event) == h.False) {
            if (c.XCheckTypedWindowEvent(display, self.window, h.SelectionRequest, &event) == h.True) handle(&event);
        }
        if (event.xselection.property == h.None) return null;

        var actual_type: h.Atom = undefined;
        var actual_format: c_int = undefined;
        var nitems: c_ulong = undefined;
        var bytes_after: c_ulong = undefined;
        var property: [*]u8 = undefined;
        _ = c.XGetWindowProperty(display, self.window, atoms.SELECTION, 0, std.math.maxInt(c_long), h.True, h.AnyPropertyType, &actual_type, &actual_format, &nitems, &bytes_after, @ptrCast(&property));
        defer _ = c.XFree(property);

        if (actual_type == atoms.INCR) {
            var result = allocator.alloc(u8, 0) catch unreachable;
            while (true) {
                while (c.XCheckTypedWindowEvent(display, self.window, h.PropertyNotify, &event) == h.False) {}
                if (event.xproperty.atom != atoms.SELECTION or event.xproperty.state != h.PropertyNewValue) continue;

                var chunk: [*]u8 = undefined;
                _ = c.XGetWindowProperty(display, self.window, atoms.SELECTION, 0, std.math.maxInt(c_long), h.True, h.AnyPropertyType, &actual_type, &actual_format, &nitems, &bytes_after, @ptrCast(&chunk));
                defer _ = c.XFree(chunk);

                if (result.len > 0 and nitems == 0) break;
                result = allocator.realloc(result, result.len + nitems) catch return null;
                @memcpy(result[result.len - nitems ..], chunk);
            }
            return result;
        } else {
            return allocator.dupe(u8, property[0..nitems]) catch null;
        }
    }

    pub fn makeContextCurrent(self: *Window) void {
        _ = c.glXMakeCurrent(display, self.window, self.opengl.context);
    }

    pub fn swapBuffers(self: *Window) void {
        c.glXSwapBuffers(display, self.window);
    }

    pub fn swapInterval(self: *Window, interval: i32) void {
        if (glx.swapIntervalEXT) |swapIntervalEXT| {
            swapIntervalEXT(display, self.window, interval);
        }
    }

    pub fn createSurface(self: Window, instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
        const VkXlibSurfaceCreateInfoKHR = extern struct {
            sType: i32 = 1000004000,
            pNext: ?*const anyopaque = null,
            flags: u32 = 0,
            dpy: *h.Display,
            window: h.Window,
        };

        const vkCreateXlibSurfaceKHR: *const fn (usize, *const VkXlibSurfaceCreateInfoKHR, ?*const anyopaque, *u64) callconv(.c) i32 =
            @ptrCast(unix.vkGetInstanceProcAddr(instance, "vkCreateXlibSurfaceKHR"));

        return vkCreateXlibSurfaceKHR(
            instance,
            &.{
                .dpy = display,
                .window = self.window,
            },
            allocator,
            surface,
        );
    }
};

pub fn glGetProcAddress(name: [:0]const u8) ?*const anyopaque {
    return c.glXGetProcAddress(name);
}

pub fn getVulkanExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_xlib_surface" };
}

fn preeditStart(_: h.XIC, _: h.XPointer, _: h.XPointer) callconv(.c) c_int {
    return -1; // no size limit
}

fn preeditDone(_: h.XIC, window: *Window, _: h.XPointer) callconv(.c) void {
    window.preedit_string.clearRetainingCapacity();
    window.events.push(.preview_reset);
}

fn preeditDraw(_: h.XIC, window: *Window, data: *h.XIMPreeditDrawCallbackStruct) callconv(.c) void {
    const chg_first = std.math.cast(u16, data.chg_first) orelse return;
    const chg_length = std.math.cast(u16, data.chg_length) orelse return;
    const caret = std.math.cast(u16, data.caret) orelse return;

    var cursor: [2]u16 = .{ caret, caret };

    if (@as(?*h.XIMText, data.text)) |text| {
        if (text.encoding_is_wchar == h.False) {
            if (text.string.multi_byte) |string| {
                window.preedit_string.replaceRangeAssumeCapacity(chg_first, chg_length, &.{});
                const view = std.unicode.Utf8View.init(std.mem.sliceTo(string, 0)) catch return;
                var iter = view.iterator();
                var i = chg_first;
                while (iter.nextCodepoint()) |char| : (i += 1) {
                    window.preedit_string.insert(internal.allocator, i, char) catch return;
                }
            }
        }

        if (text.feedback) |feedback| {
            var start: u16 = 0;
            var end: u16 = 0;
            while (start < text.length) : (start += 1) {
                if (feedback[start] & h.XIMReverse != 0) {
                    end = start;
                    while (end < text.length and feedback[end] == feedback[start]) : (end += 1) {}
                    cursor = .{ chg_first + start, chg_first + end };
                    break;
                }
            }
        }
    } else {
        window.preedit_string.replaceRangeAssumeCapacity(chg_first, chg_length, &.{});
    }

    window.events.push(.preview_reset);
    for (window.preedit_string.items) |char| {
        window.events.push(.{ .preview_char = char });
    }
    if (window.preedit_string.items.len > 0) {
        window.events.push(.{ .preview_cursor = cursor });
    }
}

fn handle(event: *h.XEvent) void {
    if (event.type == h.SelectionRequest) {
        const requestor = event.xselectionrequest.requestor;
        const target = event.xselectionrequest.target;
        var property = event.xselectionrequest.property;
        if (property == h.None) property = target;

        if (target == atoms.TARGETS) {
            const targets = [_]h.Atom{ atoms.TARGETS, atoms.UTF8_STRING };
            _ = c.XChangeProperty(display, requestor, property, h.XA_ATOM, 32, h.PropModeReplace, @ptrCast(&targets), targets.len);
        } else if (target == atoms.UTF8_STRING) {
            _ = c.XChangeProperty(display, requestor, property, atoms.UTF8_STRING, 8, h.PropModeReplace, clipboard_text.ptr, std.math.lossyCast(c_int, clipboard_text.len));
        } else {
            property = h.None;
        }

        var reply = h.XEvent{
            .xselection = .{
                .type = h.SelectionNotify,
                .requestor = requestor,
                .selection = event.xselectionrequest.selection,
                .target = target,
                .property = property,
                .time = h.CurrentTime,
            },
        };
        _ = c.XSendEvent(display, requestor, h.True, h.NoEventMask, &reply);

        return;
    }

    const window = windows.get(event.xany.window) orelse {
        _ = c.XFilterEvent(event, h.None);
        return;
    };

    if (window.text and c.XFilterEvent(event, h.None) == h.True) {
        return;
    }

    switch (event.type) {
        h.ClientMessage => {
            if (event.xclient.message_type == atoms.WM_PROTOCOLS) {
                if (event.xclient.data.l[0] == atoms.WM_DELETE_WINDOW) {
                    window.events.push(.close);
                }
            }
        },
        h.FocusIn => {
            window.events.push(.focused);
            window.warped = false;
        },
        h.FocusOut => window.events.push(.unfocused),
        h.Expose => {
            if (event.xexpose.count == 0) {
                window.events.push(.draw);
            }
        },
        h.ConfigureNotify => {
            var states: [*]c_long = undefined;
            var actual_type: h.Atom = undefined;
            var actual_format: c_int = undefined;
            var count: c_ulong = undefined;
            var bytes_after: c_ulong = undefined;
            _ = c.XGetWindowProperty(display, window.window, atoms._NET_WM_STATE, 0, std.math.maxInt(c_long), h.False, h.XA_ATOM, &actual_type, &actual_format, &count, &bytes_after, @ptrCast(&states));
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
            window.events.push(.{ .mode = mode });

            window.size = wio.Size{ .width = std.math.lossyCast(u16, event.xconfigure.width), .height = std.math.lossyCast(u16, event.xconfigure.height) };
            window.events.push(.{ .size = window.size });
            window.events.push(.{ .framebuffer = window.size });
            window.events.push(.draw);
        },
        h.KeyPress => handleKeyPress(window, event, false),
        h.KeyRelease => {
            if (c.XPending(display) > 0) {
                // key repeats are sent as a consecutive release and press
                var next: h.XEvent = undefined;
                _ = c.XPeekEvent(display, &next);
                if (next.type == h.KeyPress and next.xkey.time == event.xkey.time) {
                    _ = c.XNextEvent(display, &next);
                    handleKeyPress(window, &next, true);
                    return;
                }
            }
            const button = keycodes[event.xkey.keycode - 8];
            if (button != .mouse_left) window.events.push(.{ .button_release = button });
        },
        h.ButtonPress => {
            const button: wio.Button = switch (event.xbutton.button) {
                1 => .mouse_left,
                2 => .mouse_middle,
                3 => .mouse_right,
                4 => return window.events.push(.{ .scroll_vertical = -1 }),
                5 => return window.events.push(.{ .scroll_vertical = 1 }),
                6 => return window.events.push(.{ .scroll_horizontal = -1 }),
                7 => return window.events.push(.{ .scroll_horizontal = 1 }),
                8 => .mouse_back,
                9 => .mouse_forward,
                else => return,
            };
            window.events.push(.{ .button_press = button });
        },
        h.ButtonRelease => {
            const button: wio.Button = switch (event.xbutton.button) {
                1 => .mouse_left,
                2 => .mouse_middle,
                3 => .mouse_right,
                8 => .mouse_back,
                9 => .mouse_forward,
                else => return,
            };
            window.events.push(.{ .button_release = button });
        },
        h.MotionNotify => {
            if (window.cursor_mode == .relative) {
                const dx = event.xmotion.x - (window.size.width / 2);
                const dy = event.xmotion.y - (window.size.height / 2);
                if (dx != 0 or dy != 0) {
                    if (window.warped) window.events.push(.{ .mouse_relative = .{ .x = std.math.cast(i16, dx) orelse return, .y = std.math.cast(i16, dy) orelse return } });
                    _ = c.XWarpPointer(display, h.None, window.window, 0, 0, 0, 0, window.size.width / 2, window.size.height / 2);
                    window.warped = true;
                }
            } else {
                const x = std.math.cast(u16, event.xmotion.x) orelse return;
                const y = std.math.cast(u16, event.xmotion.y) orelse return;
                window.events.push(.{ .mouse = .{ .x = x, .y = y } });
            }
        },
        else => {},
    }
}

fn handleKeyPress(window: *Window, event: *h.XEvent, repeat: bool) void {
    if (event.xkey.keycode != 0) {
        const button = keycodes[event.xkey.keycode - 8];
        if (button != .mouse_left) {
            window.events.push(if (repeat) .{ .button_repeat = button } else .{ .button_press = button });
        }
    }

    if (window.text) {
        var stack: [4]u8 = undefined;
        const len = c.Xutf8LookupString(window.ic, &event.xkey, &stack, stack.len, null, null);
        var slice: []u8 = undefined;
        if (len > stack.len) {
            slice = internal.allocator.alloc(u8, @intCast(len)) catch return;
            _ = c.Xutf8LookupString(window.ic, &event.xkey, slice.ptr, len, null, null);
        } else {
            slice = stack[0..@intCast(len)];
        }
        defer if (len > stack.len) internal.allocator.free(slice);

        const view = std.unicode.Utf8View.init(slice) catch return;
        var iter = view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (codepoint >= ' ' and codepoint != 0x7F) {
                window.events.push(.{ .char = codepoint });
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

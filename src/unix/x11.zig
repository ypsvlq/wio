const std = @import("std");
const build_options = @import("build_options");
const h = @import("c");
const wio = @import("../wio.zig");
const internal = @import("../wio.internal.zig");
const unix = @import("../unix.zig");
const DynLib = @import("DynLib.zig");
const log = std.log.scoped(.wio);

var imports: extern struct {
    XkbOpenDisplay: *const fn ([*c]const u8, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int) callconv(.c) ?*h.Display,
    XCloseDisplay: *const fn (?*h.Display) callconv(.c) c_int,
    XInternAtoms: *const fn (?*h.Display, [*c][*c]u8, c_int, c_int, [*c]h.Atom) callconv(.c) c_int,
    XSetLocaleModifiers: *const fn ([*c]const u8) callconv(.c) [*c]u8,
    XOpenIM: *const fn (?*h.Display, ?*h.struct__XrmHashBucketRec, [*c]u8, [*c]u8) callconv(.c) h.XIM,
    XCloseIM: *const fn (h.XIM) callconv(.c) c_int,
    XGetIMValues: *const fn (h.XIM, ...) callconv(.c) [*c]u8,
    XFree: *const fn (?*anyopaque) callconv(.c) c_int,
    XkbGetMap: *const fn (?*h.Display, c_uint, c_uint) callconv(.c) h.XkbDescPtr,
    XkbFreeKeyboard: *const fn (h.XkbDescPtr, c_uint, c_int) callconv(.c) void,
    XkbGetNames: *const fn (?*h.Display, c_uint, h.XkbDescPtr) callconv(.c) c_int,
    XGetDefault: *const fn (?*h.Display, [*c]const u8, [*c]const u8) callconv(.c) [*c]u8,
    XkbGetState: *const fn (?*h.Display, c_uint, h.XkbStatePtr) callconv(.c) c_int,
    XFlush: *const fn (?*h.Display) callconv(.c) c_int,
    XCreateWindow: *const fn (?*h.Display, h.Window, c_int, c_int, c_uint, c_uint, c_uint, c_int, c_uint, [*c]h.Visual, c_ulong, [*c]h.XSetWindowAttributes) callconv(.c) h.Window,
    XDestroyWindow: *const fn (?*h.Display, h.Window) callconv(.c) c_int,
    XMapWindow: *const fn (?*h.Display, h.Window) callconv(.c) c_int,
    XChangeProperty: *const fn (?*h.Display, h.Window, h.Atom, h.Atom, c_int, c_int, [*c]const u8, c_int) callconv(.c) c_int,
    XVaCreateNestedList: *const fn (c_int, ...) callconv(.c) h.XVaNestedList,
    XCreateIC: *const fn (h.XIM, ...) callconv(.c) h.XIC,
    XDestroyIC: *const fn (h.XIC) callconv(.c) void,
    XNextEvent: *const fn (?*h.Display, [*c]h.XEvent) callconv(.c) c_int,
    XPending: *const fn (?*h.Display) callconv(.c) c_int,
    XFilterEvent: *const fn ([*c]h.XEvent, h.Window) callconv(.c) c_int,
    XPeekEvent: *const fn (?*h.Display, [*c]h.XEvent) callconv(.c) c_int,
    XGetWindowProperty: *const fn (?*h.Display, h.Window, h.Atom, c_long, c_long, c_int, h.Atom, [*c]h.Atom, [*c]c_int, [*c]c_ulong, [*c]c_ulong, [*c][*c]u8) callconv(.c) c_int,
    Xutf8LookupString: *const fn (h.XIC, [*c]h.XKeyPressedEvent, [*c]u8, c_int, [*c]h.KeySym, [*c]c_int) callconv(.c) c_int,
    XSendEvent: *const fn (?*h.Display, h.Window, c_int, c_long, [*c]h.XEvent) callconv(.c) c_int,
    XSetICValues: *const fn (h.XIC, ...) callconv(.c) [*c]u8,
    XResizeWindow: *const fn (?*h.Display, h.Window, c_uint, c_uint) callconv(.c) c_int,
    XReparentWindow: *const fn (?*h.Display, h.Window, h.Window, c_int, c_int) callconv(.c) c_int,
    XcursorLibraryLoadCursor: *const fn (dpy: ?*h.Display, file: [*c]const u8) callconv(.c) h.Cursor,
    XDefineCursor: *const fn (?*h.Display, h.Window, h.Cursor) callconv(.c) c_int,
    XCreatePixmap: *const fn (?*h.Display, h.Drawable, c_uint, c_uint, c_uint) callconv(.c) h.Pixmap,
    XCreateGC: *const fn (?*h.Display, h.Drawable, c_ulong, [*c]h.XGCValues) callconv(.c) h.GC,
    XFreeGC: *const fn (?*h.Display, h.GC) callconv(.c) c_int,
    XDrawPoint: *const fn (?*h.Display, h.Drawable, h.GC, c_int, c_int) callconv(.c) c_int,
    XCreatePixmapCursor: *const fn (?*h.Display, h.Pixmap, h.Pixmap, [*c]h.XColor, [*c]h.XColor, c_uint, c_uint) callconv(.c) h.Cursor,
    XGrabPointer: *const fn (?*h.Display, h.Window, c_int, c_uint, c_int, c_int, h.Window, h.Cursor, h.Time) callconv(.c) c_int,
    XUngrabPointer: *const fn (?*h.Display, h.Time) callconv(.c) c_int,
    XWarpPointer: *const fn (?*h.Display, h.Window, h.Window, c_int, c_int, c_uint, c_uint, c_int, c_int) callconv(.c) c_int,
    XSetClassHint: *const fn (?*h.Display, h.Window, [*c]h.XClassHint) callconv(.c) c_int,
    XSetSelectionOwner: *const fn (?*h.Display, h.Atom, h.Window, h.Time) callconv(.c) c_int,
    XConvertSelection: *const fn (?*h.Display, h.Atom, h.Atom, h.Atom, h.Window, h.Time) callconv(.c) c_int,
    XInternAtom: *const fn (?*h.Display, [*c]const u8, c_int) callconv(.c) h.Atom,
    XTranslateCoordinates: *const fn (?*h.Display, h.Window, h.Window, c_int, c_int, [*c]c_int, [*c]c_int, [*c]h.Window) callconv(.c) c_int,
    XCheckTypedWindowEvent: *const fn (?*h.Display, h.Window, c_int, [*c]h.XEvent) callconv(.c) c_int,
    XCreateColormap: *const fn (?*h.Display, h.Window, [*c]h.Visual, c_int) callconv(.c) h.Colormap,
    XFreeColormap: *const fn (?*h.Display, h.Colormap) callconv(.c) c_int,
    XCreateImage: *const fn (?*h.Display, [*c]h.Visual, c_uint, c_int, c_int, [*c]u8, c_uint, c_uint, c_int, c_int) callconv(.c) [*c]h.XImage,
    XPutImage: *const fn (?*h.Display, h.Drawable, h.GC, [*c]h.XImage, c_int, c_int, c_int, c_int, c_uint, c_uint) callconv(.c) c_int,
    glXQueryExtensionsString: *const fn (dpy: ?*h.Display, screen: c_int) callconv(.c) [*c]const u8,
    glXGetProcAddress: *const fn (procname: [*c]const h.GLubyte) callconv(.c) ?*const fn () callconv(.c) void,
    glXChooseFBConfig: *const fn (dpy: ?*h.Display, screen: c_int, attribList: [*c]const c_int, nitems: [*c]c_int) callconv(.c) [*c]h.GLXFBConfig,
    glXGetVisualFromFBConfig: *const fn (dpy: ?*h.Display, config: h.GLXFBConfig) callconv(.c) [*c]h.XVisualInfo,
    glXCreateNewContext: *const fn (dpy: ?*h.Display, config: h.GLXFBConfig, renderType: c_int, shareList: h.GLXContext, direct: c_int) callconv(.c) h.GLXContext,
    glXDestroyContext: *const fn (dpy: ?*h.Display, ctx: h.GLXContext) callconv(.c) void,
    glXMakeCurrent: *const fn (dpy: ?*h.Display, drawable: h.GLXDrawable, ctx: h.GLXContext) callconv(.c) c_int,
    glXSwapBuffers: *const fn (dpy: ?*h.Display, drawable: h.GLXDrawable) callconv(.c) void,
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
    XdndAware: h.Atom,
    XdndEnter: h.Atom,
    XdndPosition: h.Atom,
    XdndStatus: h.Atom,
    XdndLeave: h.Atom,
    XdndDrop: h.Atom,
    XdndFinished: h.Atom,
    XdndTypeList: h.Atom,
    XdndSelection: h.Atom,
    XdndActionCopy: h.Atom,
} = undefined;

var atom_text_uri_list: h.Atom = undefined;

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

    var atom_names = comptime blk: {
        const fields = @typeInfo(@TypeOf(atoms)).@"struct".fields;
        var atom_names: [fields.len][*:0]const u8 = undefined;
        for (&atom_names, fields) |*name, field| name.* = field.name;
        break :blk atom_names;
    };
    _ = c.XInternAtoms(display, @ptrCast(&atom_names), atom_names.len, h.False, @ptrCast(&atoms));
    atom_text_uri_list = c.XInternAtom(display, "text/uri-list", h.False);

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

pub fn getModifiers() wio.Modifiers {
    var state: h.XkbStateRec = undefined;
    _ = c.XkbGetState(display, h.XkbUseCoreKbd, &state);
    return .{
        .control = (state.mods & h.ControlMask != 0),
        .shift = (state.mods & h.ShiftMask != 0),
        .alt = (state.mods & h.Mod1Mask != 0),
        .gui = (state.mods & h.Mod4Mask != 0),
    };
}

pub fn createWindow(options: wio.CreateWindowOptions) !*Window {
    var attributes: h.XSetWindowAttributes = undefined;
    attributes.event_mask = h.PropertyChangeMask | h.FocusChangeMask | h.ExposureMask | h.StructureNotifyMask | h.KeyPressMask | h.KeyReleaseMask | h.ButtonPressMask | h.ButtonReleaseMask | h.PointerMotionMask | h.LeaveWindowMask;
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

    const xdnd_version: c_long = 5;
    _ = c.XChangeProperty(display, window, atoms.XdndAware, h.XA_ATOM, 32, h.PropModeReplace, @ptrCast(&xdnd_version), 1);

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

    {
        const id = try internal.allocator.dupeZ(u8, options.app_id orelse options.title);
        defer internal.allocator.free(id);
        var class_hint = h.XClassHint{ .res_name = @constCast(id.ptr), .res_class = @constCast(id.ptr) };
        _ = c.XSetClassHint(display, window, &class_hint);
    }

    self.events.push(.visible);
    self.events.push(.{ .scale = scale });
    self.events.push(.{ .size_logical = size });
    self.events.push(.{ .size_physical = size });
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
    xdnd_source: h.Window = 0,
    xdnd_req: h.Atom = h.None,
    xdnd_version: c_int = 0,
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

    pub fn createFramebuffer(self: *Window, size: wio.Size) !Framebuffer {
        const pixels = try internal.allocator.alloc(u32, @as(usize, size.width) * size.height);
        errdefer internal.allocator.free(pixels);

        const image = c.XCreateImage(
            display,
            h.DefaultVisual(display, h.DefaultScreen(display)),
            24,
            h.ZPixmap,
            0,
            @ptrCast(pixels.ptr),
            size.width,
            size.height,
            32,
            0,
        ) orelse return internal.logUnexpected("XCreateImage");

        const gc = c.XCreateGC(display, self.window, 0, null);

        return .{
            .image = image,
            .gc = gc,
            .pixels = pixels,
            .size = size,
        };
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        _ = c.XPutImage(display, self.window, framebuffer.gc, framebuffer.image, 0, 0, 0, 0, framebuffer.size.width, framebuffer.size.height);
        _ = c.XFlush(display);
    }

    pub fn glMakeContextCurrent(self: *Window) void {
        _ = c.glXMakeCurrent(display, self.window, self.opengl.context);
    }

    pub fn glSwapBuffers(self: *Window) void {
        c.glXSwapBuffers(display, self.window);
    }

    pub fn glSwapInterval(self: *Window, interval: i32) void {
        if (glx.swapIntervalEXT) |swapIntervalEXT| {
            swapIntervalEXT(display, self.window, interval);
        }
    }

    pub fn vkCreateSurface(self: Window, instance: usize, allocation_callbacks: ?*const anyopaque, surface: *u64) i32 {
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
            allocation_callbacks,
            surface,
        );
    }
};

pub const Framebuffer = struct {
    image: *h.XImage,
    gc: h.GC,
    pixels: []u32,
    size: wio.Size,

    pub fn destroy(self: *Framebuffer) void {
        self.image.data = null;
        _ = c.XFree(self.image);
        _ = c.XFreeGC(display, self.gc);
        internal.allocator.free(self.pixels);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        std.mem.writeInt(u32, std.mem.asBytes(&self.pixels[y * self.size.width + x]), rgb, .little);
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return c.glXGetProcAddress(name);
}

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
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
            } else if (event.xclient.message_type == atoms.XdndEnter) {
                window.xdnd_source = @intCast(event.xclient.data.l[0]);
                window.xdnd_version = @intCast(event.xclient.data.l[1] >> 24);
                const use_list = event.xclient.data.l[1] & 1 != 0;
                window.xdnd_req = h.None;
                if (use_list) {
                    var actual_type: h.Atom = undefined;
                    var actual_format: c_int = undefined;
                    var nitems: c_ulong = undefined;
                    var bytes_after: c_ulong = undefined;
                    var data: [*]u8 = undefined;
                    _ = c.XGetWindowProperty(display, window.xdnd_source, atoms.XdndTypeList, 0, std.math.maxInt(c_long), h.False, h.XA_ATOM, &actual_type, &actual_format, &nitems, &bytes_after, @ptrCast(&data));
                    defer _ = c.XFree(data);
                    for (@as([*]h.Atom, @ptrCast(@alignCast(data)))[0..nitems]) |atom| {
                        if (atom == atom_text_uri_list) {
                            window.xdnd_req = atom;
                            break;
                        }
                    }
                } else {
                    for (1..4) |i| {
                        if (@as(h.Atom, @bitCast(event.xclient.data.l[i])) == atom_text_uri_list) {
                            window.xdnd_req = atom_text_uri_list;
                            break;
                        }
                    }
                }
            } else if (event.xclient.message_type == atoms.XdndPosition) {
                const root_x: c_int = @intCast(event.xclient.data.l[2] >> 16);
                const root_y: c_int = @intCast(event.xclient.data.l[2] & 0xffff);
                var win_x: c_int = undefined;
                var win_y: c_int = undefined;
                var child: h.Window = undefined;
                _ = c.XTranslateCoordinates(display, h.DefaultRootWindow(display), window.window, root_x, root_y, &win_x, &win_y, &child);

                var reply = h.XEvent{ .xclient = std.mem.zeroInit(h.XClientMessageEvent, .{
                    .type = h.ClientMessage,
                    .display = display,
                    .window = window.xdnd_source,
                    .message_type = atoms.XdndStatus,
                    .format = 32,
                }) };
                reply.xclient.data.l[0] = @bitCast(@as(c_ulong, window.window));
                reply.xclient.data.l[1] = if (window.xdnd_req != h.None) 1 else 0;
                reply.xclient.data.l[4] = @bitCast(atoms.XdndActionCopy);
                _ = c.XSendEvent(display, window.xdnd_source, h.False, h.NoEventMask, &reply);
                _ = c.XFlush(display);
            } else if (event.xclient.message_type == atoms.XdndLeave) {
                window.xdnd_source = 0;
                window.xdnd_req = h.None;
            } else if (event.xclient.message_type == atoms.XdndDrop) {
                if (window.xdnd_req == h.None) {
                    var reply = h.XEvent{ .xclient = std.mem.zeroInit(h.XClientMessageEvent, .{
                        .type = h.ClientMessage,
                        .display = display,
                        .window = window.xdnd_source,
                        .message_type = atoms.XdndFinished,
                        .format = 32,
                    }) };
                    reply.xclient.data.l[0] = @bitCast(@as(c_ulong, window.window));
                    _ = c.XSendEvent(display, window.xdnd_source, h.False, h.NoEventMask, &reply);
                } else {
                    const time: h.Time = if (window.xdnd_version >= 1) @intCast(event.xclient.data.l[2]) else h.CurrentTime;
                    _ = c.XConvertSelection(display, atoms.XdndSelection, window.xdnd_req, atoms.SELECTION, window.window, time);
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
            window.events.push(.{ .size_logical = window.size });
            window.events.push(.{ .size_physical = window.size });
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
        h.LeaveNotify => {
            window.events.push(.mouse_leave);
        },
        h.SelectionNotify => {
            if (window.xdnd_req != h.None and event.xselection.property != h.None and event.xselection.selection == atoms.XdndSelection) {
                var actual_type: h.Atom = undefined;
                var actual_format: c_int = undefined;
                var nitems: c_ulong = undefined;
                var bytes_after: c_ulong = undefined;
                var data: [*]u8 = undefined;
                _ = c.XGetWindowProperty(display, window.window, atoms.SELECTION, 0, std.math.maxInt(c_long), h.True, h.AnyPropertyType, &actual_type, &actual_format, &nitems, &bytes_after, @ptrCast(&data));
                defer _ = c.XFree(data);

                if (actual_format == 8) {
                    var iter = std.mem.splitAny(u8, data[0..nitems], "\r\n");
                    while (iter.next()) |line| {
                        if (line.len == 0 or line[0] == '#') continue;
                        if (uriToPath(line)) |path| {
                            window.events.push(.{ .drop_file = path });
                        }
                    }
                }
                window.events.push(.drop_complete);

                var reply = h.XEvent{ .xclient = std.mem.zeroInit(h.XClientMessageEvent, .{
                    .type = h.ClientMessage,
                    .display = display,
                    .window = window.xdnd_source,
                    .message_type = atoms.XdndFinished,
                    .format = 32,
                }) };
                reply.xclient.data.l[0] = @bitCast(@as(c_ulong, window.window));
                reply.xclient.data.l[1] = 1;
                reply.xclient.data.l[2] = @bitCast(atoms.XdndActionCopy);
                _ = c.XSendEvent(display, window.xdnd_source, h.False, h.NoEventMask, &reply);
                _ = c.XFlush(display);

                window.xdnd_source = 0;
                window.xdnd_req = h.None;
            } else {
                // clipboard SelectionNotify is handled in getClipboardText via XCheckTypedWindowEvent
            }
        },
        else => {},
    }
}

fn uriToPath(uri: []const u8) ?[]u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, uri, prefix)) return null;
    const encoded = uri[prefix.len..];

    var path = internal.allocator.alloc(u8, encoded.len) catch return null;
    var out: usize = 0;
    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hi = std.fmt.charToDigit(encoded[i + 1], 16) catch {
                path[out] = encoded[i];
                out += 1;
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(encoded[i + 2], 16) catch {
                path[out] = encoded[i];
                out += 1;
                i += 1;
                continue;
            };
            path[out] = hi << 4 | lo;
            out += 1;
            i += 3;
        } else {
            path[out] = encoded[i];
            out += 1;
            i += 1;
        }
    }
    return internal.allocator.realloc(path, out) catch {
        internal.allocator.free(path);
        return null;
    };
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

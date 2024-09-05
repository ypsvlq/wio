const std = @import("std");
const w = @import("win32");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

const EventQueue = std.fifo.LinearFifo(wio.Event, .Dynamic);
const class_name = w.L("wio");

var dinput: *w.IDirectInput8W = undefined;
var dinput_loaded = false;

var wgl: struct {
    swapIntervalEXT: ?*const fn (i32) callconv(w.WINAPI) w.BOOL = null,
} = .{};
var wgl_loaded = false;

pub fn init(options: wio.InitOptions) !void {
    const instance = w.GetModuleHandleW(null);

    const class = std.mem.zeroInit(w.WNDCLASSW, .{
        .lpfnWndProc = windowProc,
        .hInstance = instance,
        .lpszClassName = class_name,
    });
    if (w.RegisterClassW(&class) == 0) return logLastError("RegisterClassW");

    if (options.joystick) {
        try SUCCEED(w.DirectInput8Create(instance, w.DIRECTINPUT_VERSION, &w.IID_IDirectInput8W, @ptrCast(&dinput), null), "DirectInput8Create");
        dinput_loaded = true;
    }

    if (options.opengl) {
        const window = w.CreateWindowExW(
            0,
            class_name,
            w.L("wio"),
            0,
            w.CW_USEDEFAULT,
            w.CW_USEDEFAULT,
            w.CW_USEDEFAULT,
            w.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        ) orelse return error.Unexpected;

        const dc = w.GetDC(window);
        defer _ = w.ReleaseDC(window, dc);

        var pfd = std.mem.zeroInit(w.PIXELFORMATDESCRIPTOR, .{
            .nSize = @sizeOf(w.PIXELFORMATDESCRIPTOR),
            .nVersion = 1,
            .dwFlags = w.PFD_DRAW_TO_WINDOW | w.PFD_SUPPORT_OPENGL | w.PFD_DOUBLEBUFFER,
            .iPixelType = w.PFD_TYPE_RGBA,
            .cColorBits = 24,
        });
        _ = w.SetPixelFormat(dc, w.ChoosePixelFormat(dc, &pfd), &pfd);

        const temp_rc = w.wglCreateContext(dc);
        defer _ = w.wglDeleteContext(temp_rc);
        _ = w.wglMakeCurrent(dc, temp_rc);

        if (w.wglGetProcAddress("wglGetExtensionsStringARB")) |proc| {
            const getExtensionsStringARB: *const fn (w.HDC) callconv(w.WINAPI) ?[*:0]const u8 = @ptrCast(proc);
            if (getExtensionsStringARB(dc)) |extensions| {
                var iter = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (iter.next()) |name| {
                    if (std.mem.eql(u8, name, "WGL_EXT_swap_control")) {
                        wgl.swapIntervalEXT = @ptrCast(w.wglGetProcAddress("wglSwapIntervalEXT"));
                    }
                }
            }
        }

        wgl_loaded = true;
    }
}

pub fn deinit() void {
    if (dinput_loaded) {
        _ = dinput.Release();
    }
}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions) !void {
    var msg: w.MSG = undefined;
    while (true) {
        if (options.wait) {
            _ = w.GetMessageW(&msg, null, 0, 0);
            _ = w.TranslateMessage(&msg);
            _ = w.DispatchMessageW(&msg);
        } else {
            while (w.PeekMessageW(&msg, null, 0, 0, w.PM_REMOVE) != 0) {
                _ = w.TranslateMessage(&msg);
                _ = w.DispatchMessageW(&msg);
            }
        }
        if (!try func()) return;
    }
}

events: EventQueue,
window: w.HWND,
cursor: w.HCURSOR,
cursor_mode: wio.CursorMode,
surrogate: u16 = 0,
dc: w.HDC = null,
rc: w.HGLRC = null,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    errdefer wio.allocator.destroy(self);

    const title = try std.unicode.utf8ToUtf16LeAllocZ(wio.allocator, options.title);
    defer wio.allocator.free(title);
    const style: u32 = if (options.display_mode == .borderless) w.WS_POPUP else w.WS_OVERLAPPEDWINDOW;
    const size = clientToWindow(options.size, style);
    const window = w.CreateWindowExW(
        0,
        class_name,
        title.ptr,
        style,
        w.CW_USEDEFAULT,
        w.CW_USEDEFAULT,
        size.width,
        size.height,
        null,
        null,
        w.GetModuleHandleW(null),
        null,
    ) orelse return logLastError("CreateWindowExW");

    self.* = .{
        .events = EventQueue.init(wio.allocator),
        .window = window,
        .cursor = w.LoadCursorW(null, w.IDC_ARROW),
        .cursor_mode = options.cursor_mode,
    };
    _ = w.SetWindowLongPtrW(window, w.GWLP_USERDATA, @bitCast(@intFromPtr(self)));

    const dpi: f32 = @floatFromInt(w.GetDpiForWindow(window));
    const scale = dpi / w.USER_DEFAULT_SCREEN_DPI;
    self.pushEvent(.{ .scale = scale });

    const size_scaled = options.size.multiply(scale / options.scale);
    self.setSize(size_scaled);

    if (options.display_mode == .borderless and scale / options.scale == 1) {
        self.pushEvent(.{ .size = size_scaled });
        self.pushEvent(.{ .framebuffer = size_scaled });
    }

    self.setDisplayMode(options.display_mode);
    if (options.cursor != .arrow) self.setCursor(options.cursor);

    self.pushEvent(.create);
    return self;
}

pub fn destroy(self: *@This()) void {
    if (wgl_loaded) {
        _ = w.wglDeleteContext(self.rc);
        _ = w.ReleaseDC(self.window, self.dc);
    }
    _ = w.DestroyWindow(self.window);
    self.events.deinit();
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_w = std.unicode.utf8ToUtf16LeAllocZ(wio.allocator, title) catch return;
    defer wio.allocator.free(title_w);
    _ = w.SetWindowTextW(self.window, title_w);
}

pub fn setSize(self: *@This(), client_size: wio.Size) void {
    const style: u32 = @truncate(@as(usize, @bitCast(w.GetWindowLongPtrW(self.window, w.GWL_STYLE))));
    const size = clientToWindow(client_size, style);
    _ = w.SetWindowPos(self.window, null, 0, 0, size.width, size.height, w.SWP_NOMOVE | w.SWP_NOZORDER);
}

pub fn setDisplayMode(self: *@This(), mode: wio.DisplayMode) void {
    switch (mode) {
        .windowed, .borderless => _ = w.ShowWindow(self.window, w.SW_RESTORE),
        .maximized => {},
        .hidden => {
            _ = w.ShowWindow(self.window, w.SW_HIDE);
            return;
        },
    }

    var rect: w.RECT = undefined;
    _ = w.GetClientRect(self.window, &rect);
    const style: u32 = if (mode == .borderless) w.WS_POPUP else w.WS_OVERLAPPEDWINDOW;
    _ = w.AdjustWindowRect(&rect, style, w.FALSE);

    _ = w.SetWindowLongPtrW(self.window, w.GWL_STYLE, @as(i32, @bitCast(style)));
    _ = w.SetWindowPos(
        self.window,
        null,
        0,
        0,
        rect.right - rect.left,
        rect.bottom - rect.top,
        blk: {
            var flags: u32 = w.SWP_FRAMECHANGED | w.SWP_NOZORDER;
            if (mode != .borderless) flags |= w.SWP_NOMOVE;
            break :blk flags;
        },
    );

    switch (mode) {
        .windowed, .borderless => _ = w.ShowWindow(self.window, w.SW_RESTORE),
        .maximized => _ = w.ShowWindow(self.window, w.SW_MAXIMIZE),
        .hidden => unreachable,
    }
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    self.cursor = w.LoadCursorW(null, switch (shape) {
        .arrow => w.IDC_ARROW,
        .arrow_busy => w.IDC_APPSTARTING,
        .busy => w.IDC_WAIT,
        .text => w.IDC_IBEAM,
        .hand => w.IDC_HAND,
        .crosshair => w.IDC_CROSS,
        .forbidden => w.IDC_NO,
        .move => w.IDC_SIZEALL,
        .size_ns => w.IDC_SIZENS,
        .size_ew => w.IDC_SIZEWE,
        .size_nesw => w.IDC_SIZENESW,
        .size_nwse => w.IDC_SIZENWSE,
    });
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    self.cursor_mode = mode;
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    _ = options;
    self.dc = w.GetDC(self.window);
    var pfd = std.mem.zeroInit(w.PIXELFORMATDESCRIPTOR, .{
        .nSize = @sizeOf(w.PIXELFORMATDESCRIPTOR),
        .nVersion = 1,
        .dwFlags = w.PFD_DRAW_TO_WINDOW | w.PFD_SUPPORT_OPENGL | w.PFD_DOUBLEBUFFER,
        .iPixelType = w.PFD_TYPE_RGBA,
        .cColorBits = 24,
    });
    _ = w.SetPixelFormat(self.dc, w.ChoosePixelFormat(self.dc, &pfd), &pfd);
    self.rc = w.wglCreateContext(self.dc) orelse return logLastError("wglCreateContext");
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = w.wglMakeCurrent(self.dc, self.rc);
}

pub fn swapBuffers(self: *@This()) void {
    _ = w.SwapBuffers(self.dc);
}

pub fn swapInterval(_: @This(), interval: i32) void {
    if (wgl.swapIntervalEXT) |swapIntervalEXT| {
        _ = swapIntervalEXT(interval);
    }
}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    var instances = std.ArrayList(w.DIDEVICEINSTANCEW).init(wio.allocator);
    defer instances.deinit();
    try SUCCEED(dinput.EnumDevices(w.DI8DEVCLASS_GAMECTRL, enumDevicesCallback, &instances, w.DIEDFL_ATTACHEDONLY), "IDirectInput8::EnumDevices");

    var list = try std.ArrayList(wio.JoystickInfo).initCapacity(allocator, instances.items.len);
    errdefer {
        for (list.items) |info| {
            allocator.free(info.id);
            allocator.free(info.name);
        }
        list.deinit();
    }
    for (instances.items) |instance| {
        const guid = instance.guidInstance;
        const id = try std.fmt.allocPrint(allocator, "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ guid.Data1, guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7] });
        errdefer allocator.free(id);
        const name = try std.unicode.utf16LeToUtf8Alloc(allocator, &instance.tszInstanceName);
        errdefer allocator.free(name);
        list.appendAssumeCapacity(.{
            .id = id,
            .name = name,
        });
    }
    return list.toOwnedSlice();
}

fn enumDevicesCallback(ddi: [*c]w.DIDEVICEINSTANCEW, ref: ?*anyopaque) callconv(w.WINAPI) i32 {
    const list: *std.ArrayList(w.DIDEVICEINSTANCEW) = @alignCast(@ptrCast(ref));
    list.append(ddi.*) catch return w.DIENUM_STOP;
    return w.DIENUM_CONTINUE;
}

pub fn openJoystick(id: []const u8) !?Joystick {
    if (id.len != 36 or id[8] != '-' or id[13] != '-' or id[18] != '-' or id[23] != '-') return null;
    const guid = std.os.windows.GUID.parseNoBraces(id) catch return null;
    var device: *w.IDirectInputDevice8W = undefined;
    switch (dinput.CreateDevice(&guid, @ptrCast(&device), null)) {
        w.DIERR_DEVICENOTREG => return null,
        else => |hr| try SUCCEED(hr, "IDirectInput8::CreateDevice"),
    }
    errdefer _ = device.Release();

    var caps: w.DIDEVCAPS = undefined;
    caps.dwSize = @sizeOf(w.DIDEVCAPS);
    try SUCCEED(device.GetCapabilities(&caps), "IDirectInputDevice8W::GetCapabilities");

    const objects = try wio.allocator.alloc(w.DIOBJECTDATAFORMAT, caps.dwAxes + caps.dwButtons);
    defer wio.allocator.free(objects);
    var offset: u32 = 0;
    for (objects, 0..) |*object, i| {
        const flag: u32 = if (i < caps.dwAxes)
            w.DIDFT_AXIS
        else if (i < caps.dwAxes + caps.dwPOVs)
            w.DIDFT_POV
        else
            w.DIDFT_BUTTON;

        object.* = .{
            .pguid = null,
            .dwOfs = offset,
            .dwType = flag | w.DIDFT_ANYINSTANCE,
            .dwFlags = 0,
        };

        offset += if (flag == w.DIDFT_BUTTON) 1 else 4;
    }

    var format = w.DIDATAFORMAT{
        .dwSize = @sizeOf(w.DIDATAFORMAT),
        .dwObjSize = @sizeOf(w.DIOBJECTDATAFORMAT),
        .dwFlags = w.DIDF_ABSAXIS,
        .dwDataSize = (caps.dwAxes + caps.dwPOVs) * 4 + ((caps.dwButtons + 3) / 4 * 4),
        .dwNumObjs = @intCast(objects.len),
        .rgodf = objects.ptr,
    };
    try SUCCEED(device.SetDataFormat(&format), "IDirectInputDevice8W::SetDataFormat");
    try SUCCEED(device.Acquire(), "IDirectInputDevice8W::Acquire");

    const buf = try wio.allocator.alloc(u8, format.dwDataSize);
    errdefer wio.allocator.free(buf);
    const axes = try wio.allocator.alloc(u16, caps.dwAxes);
    errdefer wio.allocator.free(axes);
    const hats = try wio.allocator.alloc(wio.Hat, caps.dwPOVs);
    errdefer wio.allocator.free(hats);
    const buttons = try wio.allocator.alloc(bool, caps.dwButtons);
    errdefer wio.allocator.free(buttons);

    return .{
        .device = device,
        .buf = buf,
        .axes = axes,
        .hats = hats,
        .buttons = buttons,
    };
}

pub const Joystick = struct {
    device: *w.IDirectInputDevice8W,
    buf: []u8,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        _ = self.device.Release();
        wio.allocator.free(self.buf);
        wio.allocator.free(self.axes);
        wio.allocator.free(self.hats);
        wio.allocator.free(self.buttons);
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        switch (self.device.Poll()) {
            w.DIERR_INPUTLOST => return null,
            else => |hr| try SUCCEED(hr, "IDirectInputDevice8::Poll"),
        }
        switch (self.device.GetDeviceState(@intCast(self.buf.len), self.buf.ptr)) {
            w.DIERR_INPUTLOST => return null,
            else => |hr| try SUCCEED(hr, "IDirectInputDevice8::GetDeviceState"),
        }

        var offset: usize = 0;

        for (self.axes) |*axis| {
            axis.* = std.mem.bytesToValue(u16, self.buf[offset..]);
            offset += 4;
        }

        for (self.hats) |*hat| {
            const positions = [_]wio.Hat{
                .{ .up = true },
                .{ .up = true, .right = true },
                .{ .right = true },
                .{ .right = true, .down = true },
                .{ .down = true },
                .{ .down = true, .left = true },
                .{ .left = true },
                .{ .left = true, .up = true },
                .{},
            };
            const angle = std.mem.bytesToValue(u16, self.buf[offset..]);
            var index = angle / 4500;
            if (index >= positions.len) index = positions.len - 1;
            hat.* = positions[index];
            offset += 4;
        }

        for (self.buttons) |*button| {
            button.* = (self.buf[offset] != 0);
            offset += 1;
        }

        return .{ .axes = self.axes, .hats = self.hats, .buttons = self.buttons };
    }
};

pub fn messageBox(backend: ?*@This(), style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    const window = if (backend) |self| self.window else null;

    const title_w = std.unicode.utf8ToUtf16LeAllocZ(wio.allocator, title) catch return;
    defer wio.allocator.free(title_w);
    const message_w = std.unicode.utf8ToUtf16LeAllocZ(wio.allocator, message) catch return;
    defer wio.allocator.free(message_w);

    _ = w.MessageBoxW(window, message_w, title_w, switch (style) {
        .info => w.MB_ICONINFORMATION,
        .warn => w.MB_ICONWARNING,
        .err => w.MB_ICONERROR,
    });
}

pub fn setClipboardText(text: []const u8) void {
    if (w.OpenClipboard(null) == 0) return;
    defer _ = w.CloseClipboard();
    const text_w = std.unicode.utf8ToUtf16LeAlloc(wio.allocator, text) catch return;
    defer wio.allocator.free(text_w);
    const mem = w.GlobalAlloc(w.GMEM_MOVEABLE, (text_w.len + 1) * @sizeOf(u16)) orelse return;
    const buf: [*]u16 = @alignCast(@ptrCast(w.GlobalLock(mem) orelse {
        _ = w.GlobalFree(mem);
        return;
    }));
    @memcpy(buf, text_w);
    buf[text_w.len] = 0;
    _ = w.GlobalUnlock(mem);
    if (w.SetClipboardData(w.CF_UNICODETEXT, buf) == null) {
        _ = w.GlobalFree(mem);
    }
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    if (w.OpenClipboard(null) == 0) return null;
    defer _ = w.CloseClipboard();
    const mem = w.GetClipboardData(w.CF_UNICODETEXT) orelse return null;
    const text: [*:0]const u16 = @alignCast(@ptrCast(w.GlobalLock(mem) orelse return null));
    defer _ = w.GlobalUnlock(mem);
    return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(text, 0)) catch null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    if (@hasDecl(w, name)) {
        return &@field(w, name);
    }
    return w.wglGetProcAddress(name);
}

fn clientToWindow(size: wio.Size, style: u32) wio.Size {
    var rect = w.RECT{
        .left = 0,
        .top = 0,
        .right = size.width,
        .bottom = size.height,
    };
    _ = w.AdjustWindowRect(&rect, style, w.FALSE);
    return .{ .width = @intCast(rect.right - rect.left), .height = @intCast(rect.bottom - rect.top) };
}

fn logLastError(name: []const u8) error{Unexpected} {
    log.err("{s} failed, error {}", .{ name, w.GetLastError() });
    return error.Unexpected;
}

fn SUCCEED(hr: w.HRESULT, name: []const u8) !void {
    if (hr < 0) {
        const value: u32 = @bitCast(hr);
        log.err("{s} failed, hr={x:0>8}", .{ name, value });
        return error.Unexpected;
    }
}

fn LOWORD(x: anytype) u16 {
    return @intCast(x & 0xFFFF);
}

fn HIWORD(x: anytype) u16 {
    return @intCast((x >> 16) & 0xFFFF);
}

fn HISHORT(x: anytype) i16 {
    return @bitCast(HIWORD(x));
}

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch {};
}

fn windowProc(window: w.HWND, msg: u32, wParam: w.WPARAM, lParam: w.LPARAM) callconv(w.WINAPI) w.LRESULT {
    const self = blk: {
        const userdata: usize = @bitCast(w.GetWindowLongPtrW(window, w.GWLP_USERDATA));
        const ptr: ?*@This() = @ptrFromInt(userdata);
        break :blk ptr orelse return w.DefWindowProcW(window, msg, wParam, lParam);
    };

    switch (msg) {
        w.WM_SYSCOMMAND => {
            switch (wParam & 0xFFF0) {
                w.SC_KEYMENU => return 0,
                else => return w.DefWindowProcW(window, msg, wParam, lParam),
            }
        },
        w.WM_SETCURSOR => {
            if (LOWORD(lParam) == w.HTCLIENT) {
                _ = w.SetCursor(self.cursor);
                switch (self.cursor_mode) {
                    .normal => while (w.ShowCursor(w.TRUE) < 0) {},
                    .hidden => while (w.ShowCursor(w.FALSE) >= 0) {},
                }
                return w.TRUE;
            } else {
                while (w.ShowCursor(w.TRUE) < 0) {}
                return w.DefWindowProcW(window, msg, wParam, lParam);
            }
        },
        w.WM_CLOSE => {
            self.pushEvent(.close);
            return 0;
        },
        w.WM_SETFOCUS => {
            self.pushEvent(.focused);
            return 0;
        },
        w.WM_KILLFOCUS => {
            self.pushEvent(.unfocused);
            return 0;
        },
        w.WM_PAINT => {
            self.pushEvent(.draw);
            _ = w.ValidateRgn(window, null);
            return 0;
        },
        w.WM_SIZE => {
            const size = wio.Size{ .width = LOWORD(lParam), .height = HIWORD(lParam) };
            if (wParam == w.SIZE_RESTORED or wParam == w.SIZE_MAXIMIZED) {
                if (wParam == w.SIZE_MAXIMIZED) {
                    self.pushEvent(.{ .maximized = size });
                } else {
                    self.pushEvent(.{ .size = size });
                }
                self.pushEvent(.{ .framebuffer = size });
            }
            return 0;
        },
        w.WM_DPICHANGED => {
            const dpi: f32 = @floatFromInt(LOWORD(wParam));
            const scale = dpi / w.USER_DEFAULT_SCREEN_DPI;
            self.pushEvent(.{ .scale = scale });
            return 0;
        },
        w.WM_CHAR => {
            const char: u16 = @intCast(wParam);
            var chars: []const u16 = undefined;
            if (self.surrogate != 0) {
                chars = &.{ self.surrogate, char };
                self.surrogate = 0;
            } else if (std.unicode.utf16IsHighSurrogate(char)) {
                self.surrogate = char;
                return 0;
            } else {
                chars = &.{char};
            }
            var iter = std.unicode.Utf16LeIterator.init(chars);
            const codepoint = (iter.nextCodepoint() catch return 0).?; // never returns null on first call
            if (codepoint >= ' ') {
                self.pushEvent(.{ .char = codepoint });
            }
            return 0;
        },
        w.WM_KEYDOWN, w.WM_SYSKEYDOWN, w.WM_KEYUP, w.WM_SYSKEYUP => {
            if (wParam == w.VK_PROCESSKEY) {
                return 0;
            }

            if (msg == w.WM_SYSKEYDOWN and wParam == w.VK_F4) {
                self.pushEvent(.close);
            }

            const flags = HIWORD(lParam);
            const scancode: u9 = @intCast(flags & 0x1FF);

            if (scancode == 0x1D) {
                // discard spurious left control sent before right alt in some layouts
                var next: w.MSG = undefined;
                if (w.PeekMessageW(&next, window, 0, 0, w.PM_NOREMOVE) != 0 and
                    next.time == w.GetMessageTime() and
                    (HIWORD(next.lParam) & (0x1FF | w.KF_UP)) == (0x138 | (flags & w.KF_UP)))
                {
                    return 0;
                }
            }

            if (buttonFromScancode(scancode)) |button| {
                if (flags & w.KF_UP == 0) {
                    if (flags & w.KF_REPEAT == 0) {
                        self.pushEvent(.{ .button_press = button });
                    } else {
                        self.pushEvent(.{ .button_repeat = button });
                    }
                } else {
                    self.pushEvent(.{ .button_release = button });
                }
            } else {
                log.warn("unknown scancode 0x{x}", .{scancode});
            }
            return 0;
        },
        w.WM_LBUTTONDOWN,
        w.WM_LBUTTONUP,
        w.WM_RBUTTONDOWN,
        w.WM_RBUTTONUP,
        w.WM_MBUTTONDOWN,
        w.WM_MBUTTONUP,
        w.WM_XBUTTONDOWN,
        w.WM_XBUTTONUP,
        => {
            const button: wio.Button = switch (msg) {
                w.WM_LBUTTONDOWN, w.WM_LBUTTONUP => .mouse_left,
                w.WM_RBUTTONDOWN, w.WM_RBUTTONUP => .mouse_right,
                w.WM_MBUTTONDOWN, w.WM_MBUTTONUP => .mouse_middle,
                else => if (HIWORD(wParam) == w.XBUTTON1) .mouse_back else .mouse_forward,
            };

            switch (msg) {
                w.WM_LBUTTONDOWN,
                w.WM_MBUTTONDOWN,
                w.WM_RBUTTONDOWN,
                w.WM_XBUTTONDOWN,
                => self.pushEvent(.{ .button_press = button }),
                else => self.pushEvent(.{ .button_release = button }),
            }

            return if (msg == w.WM_XBUTTONDOWN or msg == w.WM_XBUTTONUP) w.TRUE else 0;
        },
        w.WM_MOUSEMOVE => {
            self.pushEvent(.{ .mouse = .{ .x = LOWORD(lParam), .y = HIWORD(lParam) } });
            return 0;
        },
        w.WM_MOUSEWHEEL, w.WM_MOUSEHWHEEL => {
            const delta: f32 = @floatFromInt(HISHORT(wParam));
            const value = delta / w.WHEEL_DELTA;
            self.pushEvent(if (msg == w.WM_MOUSEWHEEL) .{ .scroll_vertical = -value } else .{ .scroll_horizontal = value });
            return 0;
        },
        w.WM_DEVICECHANGE => {
            if (wParam == w.DBT_DEVNODES_CHANGED) {
                self.pushEvent(.joystick);
            }
            return w.TRUE;
        },
        else => return w.DefWindowProcW(window, msg, wParam, lParam),
    }
}

fn buttonFromScancode(scancode: u9) ?wio.Button {
    comptime var table: [0x15D]wio.Button = undefined;
    comptime for (&table, 1..) |*ptr, i| {
        ptr.* = switch (i) {
            0x1 => .escape,
            0x2 => .@"1",
            0x3 => .@"2",
            0x4 => .@"3",
            0x5 => .@"4",
            0x6 => .@"5",
            0x7 => .@"6",
            0x8 => .@"7",
            0x9 => .@"8",
            0xA => .@"9",
            0xB => .@"0",
            0xC => .minus,
            0xD => .equals,
            0xE => .backspace,
            0xF => .tab,
            0x10 => .q,
            0x11 => .w,
            0x12 => .e,
            0x13 => .r,
            0x14 => .t,
            0x15 => .y,
            0x16 => .u,
            0x17 => .i,
            0x18 => .o,
            0x19 => .p,
            0x1A => .left_bracket,
            0x1B => .right_bracket,
            0x1C => .enter,
            0x1D => .left_control,
            0x1E => .a,
            0x1F => .s,
            0x20 => .d,
            0x21 => .f,
            0x22 => .g,
            0x23 => .h,
            0x24 => .j,
            0x25 => .k,
            0x26 => .l,
            0x27 => .semicolon,
            0x28 => .apostrophe,
            0x29 => .grave,
            0x2A => .left_shift,
            0x2B => .backslash,
            0x2C => .z,
            0x2D => .x,
            0x2E => .c,
            0x2F => .v,
            0x30 => .b,
            0x31 => .n,
            0x32 => .m,
            0x33 => .comma,
            0x34 => .dot,
            0x35 => .slash,
            0x36 => .right_shift,
            0x37 => .kp_star,
            0x38 => .left_alt,
            0x39 => .space,
            0x3A => .caps_lock,
            0x3B => .f1,
            0x3C => .f2,
            0x3D => .f3,
            0x3E => .f4,
            0x3F => .f5,
            0x40 => .f6,
            0x41 => .f7,
            0x42 => .f8,
            0x43 => .f9,
            0x44 => .f10,
            0x45 => .pause,
            0x46 => .scroll_lock,
            0x47 => .kp_7,
            0x48 => .kp_8,
            0x49 => .kp_9,
            0x4A => .kp_minus,
            0x4B => .kp_4,
            0x4C => .kp_5,
            0x4D => .kp_6,
            0x4E => .kp_plus,
            0x4F => .kp_1,
            0x50 => .kp_2,
            0x51 => .kp_3,
            0x52 => .kp_0,
            0x53 => .kp_dot,
            0x54 => .print_screen, // sysrq
            0x56 => .iso_backslash,
            0x57 => .f11,
            0x58 => .f12,
            0x59 => .kp_equals,
            0x5B => .left_gui, // sent by touchpad gestures
            0x64 => .f13,
            0x65 => .f14,
            0x66 => .f15,
            0x67 => .f16,
            0x68 => .f17,
            0x69 => .f18,
            0x6A => .f19,
            0x6B => .f20,
            0x6C => .f21,
            0x6D => .f22,
            0x6E => .f23,
            0x70 => .international2,
            0x73 => .international1,
            0x76 => .f24,
            0x79 => .international4,
            0x7B => .international5,
            0x7D => .international3,
            0x7E => .kp_comma,
            0x11C => .kp_enter,
            0x11D => .right_control,
            0x135 => .kp_slash,
            0x136 => .right_shift, // sent by IME
            0x137 => .print_screen,
            0x138 => .right_alt,
            0x145 => .num_lock,
            0x146 => .pause, // break
            0x147 => .home,
            0x148 => .up,
            0x149 => .page_up,
            0x14B => .left,
            0x14D => .right,
            0x14F => .end,
            0x150 => .down,
            0x151 => .page_down,
            0x152 => .insert,
            0x153 => .delete,
            0x15B => .left_gui,
            0x15C => .right_gui,
            0x15D => .application,
            else => .mouse_left,
        };
    };
    return if (scancode > 0 and scancode <= table.len and table[scancode - 1] != .mouse_left) table[scancode - 1] else null;
}

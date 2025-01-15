const std = @import("std");
const w = @import("win32");
const wio = @import("wio.zig");
const log = std.log.scoped(.wio);

const class_name = w.L("wio");

var helper_window: w.HWND = undefined;
var helper_input: []u8 = &.{};

const JoystickInfo = struct {
    interface: []u16,
    joystick: ?*RawInputJoystick = null,
};

var joysticks: std.AutoHashMap(w.HANDLE, JoystickInfo) = undefined;
var xinput = std.StaticBitSet(4).initEmpty();

var mm_device_enumerator: *w.IMMDeviceEnumerator = undefined;
var mm_notification_client = MMNotificationClient{};

var wgl: struct {
    swapIntervalEXT: ?*const fn (i32) callconv(w.WINAPI) w.BOOL = null,
    choosePixelFormatARB: ?*const fn (w.HDC, ?[*]const i32, ?[*]const f32, u32, [*c]i32, *u32) callconv(w.WINAPI) w.BOOL = null,
} = .{};

pub fn init(options: wio.InitOptions) !void {
    const instance = w.GetModuleHandleW(null);

    const class = std.mem.zeroInit(w.WNDCLASSW, .{
        .lpfnWndProc = windowProc,
        .hInstance = instance,
        .lpszClassName = class_name,
    });
    if (w.RegisterClassW(&class) == 0) return logLastError("RegisterClassW");

    helper_window = w.CreateWindowExW(
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
    ) orelse return logLastError("CreateWindowExW");
    errdefer _ = w.DestroyWindow(helper_window);
    _ = w.SetWindowLongPtrW(helper_window, w.GWLP_WNDPROC, @bitCast(@intFromPtr(&helperWindowProc)));

    var rid = [_]w.RAWINPUTDEVICE{
        .{
            .usUsagePage = w.HID_USAGE_PAGE_GENERIC,
            .usUsage = w.HID_USAGE_GENERIC_MOUSE,
            .dwFlags = 0,
            .hwndTarget = null,
        },
        .{
            .usUsagePage = w.HID_USAGE_PAGE_GENERIC,
            .usUsage = w.HID_USAGE_GENERIC_JOYSTICK,
            .dwFlags = w.RIDEV_DEVNOTIFY,
            .hwndTarget = helper_window,
        },
        .{
            .usUsagePage = w.HID_USAGE_PAGE_GENERIC,
            .usUsage = w.HID_USAGE_GENERIC_GAMEPAD,
            .dwFlags = w.RIDEV_DEVNOTIFY,
            .hwndTarget = helper_window,
        },
    };
    if (w.RegisterRawInputDevices(&rid, rid.len, @sizeOf(w.RAWINPUTDEVICE)) == w.FALSE) return logLastError("RegisterRawInputDevices");

    if (options.joystick) {
        joysticks = .init(wio.allocator);
    }

    if (options.audio) {
        try SUCCEED(w.CoInitializeEx(null, w.COINIT_MULTITHREADED | w.COINIT_DISABLE_OLE1DDE), "CoInitializeEx");
        try SUCCEED(w.CoCreateInstance(&w.CLSID_MMDeviceEnumerator, null, w.CLSCTX_ALL, &w.IID_IMMDeviceEnumerator, @ptrCast(&mm_device_enumerator)), "CoCreateInstance");

        var device: *w.IMMDevice = undefined;
        if (wio.init_options.audioDefaultOutputFn) |callback| {
            if (SUCCEED(mm_device_enumerator.GetDefaultAudioEndpoint(w.eRender, w.eConsole, @ptrCast(&device)), "GetDefaultAudioEndpoint")) {
                callback(.{ .backend = .{ .device = device } });
            } else |_| {}
        }
        if (wio.init_options.audioDefaultInputFn) |callback| {
            if (SUCCEED(mm_device_enumerator.GetDefaultAudioEndpoint(w.eCapture, w.eConsole, @ptrCast(&device)), "GetDefaultAudioEndpoint")) {
                callback(.{ .backend = .{ .device = device } });
            } else |_| {}
        }

        if (wio.init_options.audioDefaultOutputFn != null or wio.init_options.audioDefaultInputFn != null) {
            try SUCCEED(mm_device_enumerator.RegisterEndpointNotificationCallback(&mm_notification_client.parent), "RegisterEndpointNotificationCallback");
        }
    }

    if (options.opengl) {
        const dc = w.GetDC(helper_window);
        defer _ = w.ReleaseDC(helper_window, dc);

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
                    } else if (std.mem.eql(u8, name, "WGL_ARB_pixel_format")) {
                        wgl.choosePixelFormatARB = @ptrCast(w.wglGetProcAddress("wglChoosePixelFormatARB"));
                    }
                }
            }
        }
    }
}

pub fn deinit() void {
    if (wio.init_options.audio) {
        _ = mm_device_enumerator.Release();
        w.CoUninitialize();
    }
    if (wio.init_options.joystick) {
        var iter = joysticks.valueIterator();
        while (iter.next()) |info| wio.allocator.free(info.interface);
        joysticks.deinit();
    }
    wio.allocator.free(helper_input);
    _ = w.DestroyWindow(helper_window);
}

pub fn run(func: fn () anyerror!bool) !void {
    var msg: w.MSG = undefined;
    while (true) {
        while (w.PeekMessageW(&msg, null, 0, 0, w.PM_REMOVE) != 0) {
            _ = w.TranslateMessage(&msg);
            _ = w.DispatchMessageW(&msg);
        }

        if (!try func()) return;

        if (wio.init_options.audio) {
            var maybe_device: ?*w.IMMDevice = undefined;
            if (wio.init_options.audioDefaultOutputFn) |callback| {
                mm_notification_client.mutex.lock();
                maybe_device = mm_notification_client.default_output;
                mm_notification_client.default_output = null;
                mm_notification_client.mutex.unlock();
                if (maybe_device) |device| callback(.{ .backend = .{ .device = device } });
            }
            if (wio.init_options.audioDefaultInputFn) |callback| {
                mm_notification_client.mutex.lock();
                maybe_device = mm_notification_client.default_input;
                mm_notification_client.default_input = null;
                mm_notification_client.mutex.unlock();
                if (maybe_device) |device| callback(.{ .backend = .{ .device = device } });
            }
        }
    }
}

events: std.fifo.LinearFifo(wio.Event, .Dynamic),
window: w.HWND,
cursor: w.HCURSOR,
cursor_mode: wio.CursorMode,
rect: w.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
surrogate: u16 = 0,
left_shift: bool = false,
right_shift: bool = false,
left_control: bool = false,
right_control: bool = false,
left_alt: bool = false,
right_alt: bool = false,
international2: bool = false,
international3: bool = false,
international4: bool = false,
input: []u8 = &.{},
last_x: u16 = 0,
last_y: u16 = 0,
dc: w.HDC = null,
rc: w.HGLRC = null,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    errdefer wio.allocator.destroy(self);

    const title = try std.unicode.utf8ToUtf16LeAllocZ(wio.allocator, options.title);
    defer wio.allocator.free(title);
    const style: u32 = w.WS_OVERLAPPEDWINDOW;
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
        .events = .init(wio.allocator),
        .window = window,
        .cursor = w.LoadCursorW(null, w.IDC_ARROW),
        .cursor_mode = options.cursor_mode,
    };
    _ = w.SetWindowLongPtrW(window, w.GWLP_USERDATA, @bitCast(@intFromPtr(self)));

    const dpi: f32 = @floatFromInt(w.GetDpiForWindow(window));
    const scale = dpi / w.USER_DEFAULT_SCREEN_DPI;
    self.pushEvent(.{ .scale = scale });

    const size_scaled = clientToWindow(options.size.multiply(scale / options.scale), style);
    _ = w.SetWindowPos(window, null, 0, 0, size_scaled.width, size_scaled.height, w.SWP_NOMOVE | w.SWP_NOZORDER);

    self.setMode(options.mode);
    if (options.cursor != .arrow) self.setCursor(options.cursor);

    self.pushEvent(.create);
    return self;
}

pub fn destroy(self: *@This()) void {
    if (wio.init_options.opengl) {
        _ = w.wglDeleteContext(self.rc);
        _ = w.ReleaseDC(self.window, self.dc);
    }
    _ = w.DestroyWindow(self.window);
    self.events.deinit();
    wio.allocator.free(self.input);
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

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    switch (mode) {
        .normal, .maximized => {
            if (self.isFullscreen()) {
                _ = w.SetWindowLongPtrW(self.window, w.GWL_STYLE, w.WS_OVERLAPPEDWINDOW);
                _ = w.SetWindowPos(
                    self.window,
                    null,
                    self.rect.left,
                    self.rect.top,
                    self.rect.right - self.rect.left,
                    self.rect.bottom - self.rect.top,
                    w.SWP_FRAMECHANGED | w.SWP_NOZORDER,
                );
            }
        },
        .fullscreen => {
            const monitor = w.MonitorFromWindow(self.window, w.MONITOR_DEFAULTTONEAREST);
            var info: w.MONITORINFO = undefined;
            info.cbSize = @sizeOf(w.MONITORINFO);
            _ = w.GetMonitorInfoW(monitor, &info);
            _ = w.SetWindowLongPtrW(self.window, w.GWL_STYLE, @bitCast(@as(usize, w.WS_POPUP)));
            _ = w.SetWindowPos(
                self.window,
                null,
                info.rcMonitor.left,
                info.rcMonitor.top,
                info.rcMonitor.right - info.rcMonitor.left,
                info.rcMonitor.bottom - info.rcMonitor.top,
                w.SWP_FRAMECHANGED | w.SWP_NOZORDER,
            );
        },
    }

    switch (mode) {
        .normal, .fullscreen => _ = w.ShowWindow(self.window, w.SW_RESTORE),
        .maximized => _ = w.ShowWindow(self.window, w.SW_MAXIMIZE),
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

    // trigger WM_SETCURSOR
    var pos: w.POINT = undefined;
    _ = w.GetCursorPos(&pos);
    _ = w.SetCursorPos(pos.x, pos.y);
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    self.cursor_mode = mode;
    if (mode == .relative) {
        self.clipCursor();
    } else {
        _ = w.ClipCursor(null);
    }

    // trigger WM_SETCURSOR
    var pos: w.POINT = undefined;
    _ = w.GetCursorPos(&pos);
    _ = w.SetCursorPos(pos.x, pos.y);
}

pub fn requestAttention(self: *@This()) void {
    _ = w.FlashWindow(self.window, w.TRUE);
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    self.dc = w.GetDC(self.window);

    var format: i32 = undefined;
    var pfd: w.PIXELFORMATDESCRIPTOR = undefined;
    if (wgl.choosePixelFormatARB) |choosePixelFormatARB| {
        var count: u32 = undefined;
        _ = choosePixelFormatARB(self.dc, &.{
            0x2011, if (options.doublebuffer) 1 else 0,
            0x2015, options.red_bits,
            0x2017, options.green_bits,
            0x2019, options.blue_bits,
            0x201B, options.alpha_bits,
            0x2022, options.depth_bits,
            0x2023, options.stencil_bits,
            0x2041, if (options.samples != 0) 1 else 0,
            0x2042, options.samples,
            0,
        }, null, 1, &format, &count);
        if (count != 1) return logLastError("wglChoosePixelFormatARB");
        _ = w.DescribePixelFormat(self.dc, format, @sizeOf(w.PIXELFORMATDESCRIPTOR), &pfd);
    } else {
        pfd = std.mem.zeroInit(w.PIXELFORMATDESCRIPTOR, .{
            .nSize = @sizeOf(w.PIXELFORMATDESCRIPTOR),
            .nVersion = 1,
            .dwFlags = w.PFD_DRAW_TO_WINDOW | w.PFD_SUPPORT_OPENGL | if (options.doublebuffer) w.PFD_DOUBLEBUFFER else @as(u32, 0),
            .iPixelType = w.PFD_TYPE_RGBA,
            .cColorBits = options.red_bits + options.green_bits + options.blue_bits,
            .cAlphaBits = options.alpha_bits,
            .cDepthBits = options.depth_bits,
            .cStencilBits = options.stencil_bits,
        });
        format = w.ChoosePixelFormat(self.dc, &pfd);
        if (format == 0) return logLastError("ChoosePixelFormat");
    }

    _ = w.SetPixelFormat(self.dc, format, &pfd);
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

pub const JoystickDeviceIterator = struct {
    joysticks: @TypeOf(joysticks).KeyIterator,
    xinput: @TypeOf(xinput).Iterator(.{}),

    pub fn init() JoystickDeviceIterator {
        return .{ .joysticks = joysticks.keyIterator(), .xinput = xinput.iterator(.{}) };
    }

    pub fn deinit(_: *JoystickDeviceIterator) void {}

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        return if (self.joysticks.next()) |key_ptr|
            .{ .rawinput = key_ptr.* }
        else if (self.xinput.next()) |index|
            .{ .xinput = @intCast(index) }
        else
            null;
    }
};

pub const JoystickDevice = union(enum) {
    rawinput: w.HANDLE,
    xinput: u2,

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !*Joystick {
        const joystick = try wio.allocator.create(Joystick);
        errdefer wio.allocator.destroy(joystick);
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.getPtr(device) orelse return error.Unexpected;
                if (info.joystick) |_| return error.Unexpected;

                var preparsed_size: u32 = undefined;
                if (w.GetRawInputDeviceInfoW(device, w.RIDI_PREPARSEDDATA, null, &preparsed_size) < 0) return error.Unexpected;
                const preparsed = try wio.allocator.alloc(u8, preparsed_size);
                errdefer wio.allocator.free(preparsed);
                if (w.GetRawInputDeviceInfoW(device, w.RIDI_PREPARSEDDATA, preparsed.ptr, &preparsed_size) < 0) return error.Unexpected;

                var caps: w.HIDP_CAPS = undefined;
                if (w.HidP_GetCaps(@bitCast(@intFromPtr(preparsed.ptr)), &caps) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                var value_caps_len = caps.NumberInputValueCaps;
                const value_caps = try wio.allocator.alloc(w.HIDP_VALUE_CAPS, value_caps_len);
                errdefer wio.allocator.free(value_caps);
                if (w.HidP_GetValueCaps(w.HidP_Input, value_caps.ptr, &value_caps_len, @bitCast(@intFromPtr(preparsed.ptr))) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                var button_caps_len = caps.NumberInputButtonCaps;
                const button_caps = try wio.allocator.alloc(w.HIDP_BUTTON_CAPS, button_caps_len);
                defer wio.allocator.free(button_caps);
                if (w.HidP_GetButtonCaps(w.HidP_Input, button_caps.ptr, &button_caps_len, @bitCast(@intFromPtr(preparsed.ptr))) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                const data_len = w.HidP_MaxDataListLength(w.HidP_Input, @bitCast(@intFromPtr(preparsed.ptr)));
                const data = try wio.allocator.alloc(w.HIDP_DATA, data_len);
                errdefer wio.allocator.free(data);

                const indices = try wio.allocator.alloc(RawInputJoystick.DataIndex, data_len);
                errdefer wio.allocator.free(indices);
                @memset(indices, .none);

                var axis_count: u16 = 0;
                var hat_count: u16 = 0;
                for (value_caps, 0..) |cap, cap_index| {
                    const min = if (cap.IsRange == w.TRUE) cap.Anonymous.Range.DataIndexMin else cap.Anonymous.NotRange.DataIndex;
                    const max = (if (cap.IsRange == w.TRUE) cap.Anonymous.Range.DataIndexMax else cap.Anonymous.NotRange.DataIndex) + 1;
                    for (min..max) |i| {
                        const usage = if (cap.IsRange == w.TRUE) cap.Anonymous.Range.UsageMin + i else cap.Anonymous.NotRange.Usage;
                        switch (cap.UsagePage) {
                            w.HID_USAGE_PAGE_GENERIC => {
                                switch (usage) {
                                    w.HID_USAGE_GENERIC_HATSWITCH => {
                                        indices[i] = .{ .hat = hat_count };
                                        hat_count += 1;
                                        continue;
                                    },
                                    w.HID_USAGE_GENERIC_X,
                                    w.HID_USAGE_GENERIC_Y,
                                    w.HID_USAGE_GENERIC_Z,
                                    w.HID_USAGE_GENERIC_RX,
                                    w.HID_USAGE_GENERIC_RY,
                                    w.HID_USAGE_GENERIC_RZ,
                                    w.HID_USAGE_GENERIC_SLIDER,
                                    w.HID_USAGE_GENERIC_DIAL,
                                    w.HID_USAGE_GENERIC_WHEEL,
                                    => {},
                                    else => continue,
                                }
                            },
                            else => continue,
                        }
                        indices[i] = .{
                            .axis = .{
                                .index = axis_count,
                                .caps_index = @intCast(cap_index),
                            },
                        };
                        axis_count += 1;
                    }
                }

                var button_count: u16 = 0;
                for (button_caps) |cap| {
                    const min = if (cap.IsRange == w.TRUE) cap.Anonymous.Range.DataIndexMin else cap.Anonymous.NotRange.DataIndex;
                    const max = (if (cap.IsRange == w.TRUE) cap.Anonymous.Range.DataIndexMax else cap.Anonymous.NotRange.DataIndex) + 1;
                    for (min..max) |i| {
                        indices[i] = .{ .button = button_count };
                        button_count += 1;
                    }
                }

                const axes = try wio.allocator.alloc(u16, axis_count);
                errdefer wio.allocator.free(axes);
                @memset(axes, 0xFFFF / 2);

                const hats = try wio.allocator.alloc(wio.Hat, hat_count);
                errdefer wio.allocator.free(hats);
                @memset(hats, .{});

                const buttons = try wio.allocator.alloc(bool, button_count);
                errdefer wio.allocator.free(buttons);
                @memset(buttons, false);

                joystick.* = .{
                    .rawinput = .{
                        .device = device,
                        .preparsed = preparsed,
                        .value_caps = value_caps,
                        .data = data,
                        .indices = indices,
                        .axes = axes,
                        .hats = hats,
                        .buttons = buttons,
                    },
                };
                info.joystick = &joystick.rawinput;
                return joystick;
            },
            .xinput => |index| {
                joystick.* = .{ .xinput = .{ .index = index } };
                return joystick;
            },
        }
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) !?[]u8 {
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.get(device) orelse return null;
                return try std.unicode.utf16LeToUtf8Alloc(allocator, info.interface[0 .. info.interface.len - 1]);
            },
            .xinput => |index| return try std.fmt.allocPrint(allocator, "{}", .{index}),
        }
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.get(device) orelse return "";
                const collection = w.CreateFileW(info.interface.ptr, 0, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_EXISTING, 0, null) orelse return "";
                defer std.os.windows.CloseHandle(collection);
                var product: [2046]u16 = undefined;
                product[0] = 0;
                if (w.HidD_GetProductString(collection, &product, product.len * @sizeOf(u16)) == w.FALSE) return "";
                return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(&product, 0));
            },
            .xinput => return allocator.dupe(u8, "XInput Controller"),
        }
    }
};

pub const Joystick = union(enum) {
    rawinput: RawInputJoystick,
    xinput: XInputJoystick,

    pub fn close(self: *Joystick) void {
        switch (self.*) {
            inline else => |*joystick| joystick.close(),
        }
        wio.allocator.destroy(self);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        switch (self.*) {
            inline else => |*joystick| return joystick.poll(),
        }
    }
};

const RawInputJoystick = struct {
    device: w.HANDLE,
    preparsed: []u8,
    value_caps: []w.HIDP_VALUE_CAPS,
    data: []w.HIDP_DATA,
    indices: []DataIndex,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,
    disconnected: bool = false,

    const DataIndex = union(enum) {
        none: void,
        axis: struct {
            index: u16,
            caps_index: u16,
        },
        hat: u16,
        button: u16,
    };

    pub fn close(self: *RawInputJoystick) void {
        if (joysticks.getPtr(self.device)) |info| {
            info.joystick = null;
        }
        wio.allocator.free(self.buttons);
        wio.allocator.free(self.hats);
        wio.allocator.free(self.axes);
        wio.allocator.free(self.indices);
        wio.allocator.free(self.data);
        wio.allocator.free(self.value_caps);
        wio.allocator.free(self.preparsed);
    }

    pub fn poll(self: *RawInputJoystick) ?wio.JoystickState {
        return if (!self.disconnected) .{ .axes = self.axes, .hats = self.hats, .buttons = self.buttons } else null;
    }
};

const XInputJoystick = struct {
    index: u2,
    axes: [6]u16 = undefined,
    hats: [1]wio.Hat = undefined,
    buttons: [10]bool = undefined,

    pub fn close(_: *XInputJoystick) void {}

    pub fn poll(self: *XInputJoystick) ?wio.JoystickState {
        var state: w.XINPUT_STATE = undefined;
        if (w.XInputGetState(self.index, &state) != w.ERROR_SUCCESS) return null;

        self.axes[0] = @bitCast(state.Gamepad.sThumbLX +% -0x8000);
        self.axes[1] = @bitCast(-(state.Gamepad.sThumbLY -% 0x7FFF));
        self.axes[2] = @bitCast(state.Gamepad.sThumbRX +% -0x8000);
        self.axes[3] = @bitCast(-(state.Gamepad.sThumbRY -% 0x7FFF));
        self.axes[4] = @as(u16, state.Gamepad.bLeftTrigger) * 0x80 + 0x8000;
        self.axes[5] = @as(u16, state.Gamepad.bRightTrigger) * 0x80 + 0x8000;

        self.hats[0] = .{
            .up = (state.Gamepad.wButtons & w.XINPUT_GAMEPAD_DPAD_UP != 0),
            .right = (state.Gamepad.wButtons & w.XINPUT_GAMEPAD_DPAD_RIGHT != 0),
            .down = (state.Gamepad.wButtons & w.XINPUT_GAMEPAD_DPAD_DOWN != 0),
            .left = (state.Gamepad.wButtons & w.XINPUT_GAMEPAD_DPAD_LEFT != 0),
        };

        const button_masks = [_]u16{
            w.XINPUT_GAMEPAD_A,
            w.XINPUT_GAMEPAD_B,
            w.XINPUT_GAMEPAD_X,
            w.XINPUT_GAMEPAD_Y,
            w.XINPUT_GAMEPAD_LEFT_SHOULDER,
            w.XINPUT_GAMEPAD_RIGHT_SHOULDER,
            w.XINPUT_GAMEPAD_BACK,
            w.XINPUT_GAMEPAD_START,
            w.XINPUT_GAMEPAD_LEFT_THUMB,
            w.XINPUT_GAMEPAD_RIGHT_THUMB,
        };
        for (&self.buttons, button_masks) |*button, mask| {
            button.* = (state.Gamepad.wButtons & mask != 0);
        }

        return .{ .axes = &self.axes, .hats = &self.hats, .buttons = &self.buttons };
    }
};

pub const AudioDeviceIterator = struct {
    devices: ?*w.IMMDeviceCollection = null,
    count: u32 = 0,
    index: u32 = 0,

    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        var result = AudioDeviceIterator{};
        if (SUCCEED(mm_device_enumerator.EnumAudioEndpoints(if (mode == .output) w.eRender else w.eCapture, w.DEVICE_STATE_ACTIVE, @ptrCast(&result.devices)), "EnumAudioEndpoints")) {
            SUCCEED(result.devices.?.GetCount(&result.count), "IMMDeviceCollection::GetCount") catch {};
        } else |_| {}
        return result;
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        if (self.devices) |devices| _ = devices.Release();
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.index == self.count) return null;
        var device: *w.IMMDevice = undefined;
        SUCCEED(self.devices.?.Item(self.index, @ptrCast(&device)), "IMMDeviceCollection::Item") catch return null;
        self.index += 1;
        return .{ .device = device };
    }
};

pub const AudioDevice = struct {
    device: *w.IMMDevice,

    pub fn release(self: AudioDevice) void {
        _ = self.device.Release();
    }

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !*AudioOutput {
        return self.openAudioClient(format, &w.IID_IAudioRenderClient, @ptrCast(writeFn), AudioClient.outputThread);
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !*AudioInput {
        return self.openAudioClient(format, &w.IID_IAudioCaptureClient, @ptrCast(readFn), AudioClient.inputThread);
    }

    fn openAudioClient(self: AudioDevice, format: wio.AudioFormat, guid: *const w.GUID, dataFn: *const fn () void, threadFn: fn (*AudioClient) void) !*AudioClient {
        var client: *w.IAudioClient = undefined;
        try SUCCEED(self.device.Activate(&w.IID_IAudioClient, w.CLSCTX_ALL, null, @ptrCast(&client)), "IMMDevice::Activate");
        errdefer _ = client.Release();

        var channel_mask: u32 = 0;
        var iter = format.channels.iterator();
        while (iter.next()) |channel| {
            channel_mask |= switch (channel) {
                .FL => w.SPEAKER_FRONT_LEFT,
                .FR => w.SPEAKER_FRONT_RIGHT,
                .FC => w.SPEAKER_FRONT_CENTER,
                .LFE1 => w.SPEAKER_LOW_FREQUENCY,
                .BL => w.SPEAKER_BACK_LEFT,
                .BR => w.SPEAKER_BACK_RIGHT,
                .FLc => w.SPEAKER_FRONT_LEFT_OF_CENTER,
                .FRc => w.SPEAKER_FRONT_RIGHT_OF_CENTER,
                .BC => w.SPEAKER_BACK_CENTER,
                .SiL => w.SPEAKER_SIDE_LEFT,
                .SiR => w.SPEAKER_SIDE_RIGHT,
                .TpC => w.SPEAKER_TOP_CENTER,
                .TpFL => w.SPEAKER_TOP_FRONT_LEFT,
                .TpFC => w.SPEAKER_TOP_FRONT_CENTER,
                .TpFR => w.SPEAKER_TOP_FRONT_RIGHT,
                .TpBL => w.SPEAKER_TOP_BACK_LEFT,
                .TpBC => w.SPEAKER_TOP_BACK_CENTER,
                .TpBR => w.SPEAKER_TOP_BACK_RIGHT,
                else => return error.Unexpected,
            };
        }

        const T = f32;
        const channels: u16 = @intCast(format.channels.count());
        const block_align = channels * @sizeOf(T);
        const waveformat = w.WAVEFORMATEXTENSIBLE{
            .Format = .{
                .wFormatTag = w.WAVE_FORMAT_EXTENSIBLE,
                .nChannels = channels,
                .nSamplesPerSec = format.sample_rate,
                .nAvgBytesPerSec = format.sample_rate * block_align,
                .nBlockAlign = block_align,
                .wBitsPerSample = @bitSizeOf(T),
                .cbSize = @sizeOf(w.WAVEFORMATEXTENSIBLE) - @sizeOf(w.WAVEFORMATEX),
            },
            .Samples = .{ .wValidBitsPerSample = @bitSizeOf(T) },
            .dwChannelMask = channel_mask,
            .SubFormat = if (T == f32) w.KSDATAFORMAT_SUBTYPE_IEEE_FLOAT else w.KSDATAFORMAT_SUBTYPE_PCM,
        };
        try SUCCEED(client.Initialize(w.AUDCLNT_SHAREMODE_SHARED, w.AUDCLNT_STREAMFLAGS_EVENTCALLBACK | w.AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | w.AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, 0, 0, &waveformat.Format, null), "IAudioClient::Initialize");

        const event = w.CreateEventW(null, w.FALSE, w.FALSE, null) orelse return logLastError("CreateEventW");
        errdefer std.os.windows.CloseHandle(event);
        try SUCCEED(client.SetEventHandle(event), "IAudioClient::SetEventHandle");

        var service: *w.IUnknown = undefined;
        try SUCCEED(client.GetService(guid, @ptrCast(&service)), "IAudioClient::GetService");
        errdefer _ = service.Release();

        try SUCCEED(client.Start(), "IAudioClient::Start");

        const result = try wio.allocator.create(AudioClient);
        errdefer wio.allocator.destroy(result);
        result.* = .{
            .thread = undefined,
            .client = client,
            .event = event,
            .channels = channels,
            .service = service,
            .dataFn = dataFn,
        };
        result.thread = try std.Thread.spawn(.{}, threadFn, .{result});
        return result;
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        var id: [*:0]u16 = undefined;
        try SUCCEED(self.device.GetId(@ptrCast(&id)), "IMMDevice::GetID");
        defer w.CoTaskMemFree(id);
        return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(id, 0));
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        var properties: *w.IPropertyStore = undefined;
        try SUCCEED(self.device.OpenPropertyStore(w.STGM_READ, @ptrCast(&properties)), "IMMDevice::OpenPropertyStore");
        defer _ = properties.Release();

        var variant: w.PROPVARIANT = undefined;
        try SUCCEED(properties.GetValue(&w.PKEY_Device_FriendlyName, &variant), "IPropertyStore::GetValue");
        defer _ = w.PropVariantClear(&variant);

        return if (variant.Anonymous.Anonymous.vt == w.VT_LPWSTR)
            std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(variant.Anonymous.Anonymous.Anonymous.pwszVal, 0))
        else
            "";
    }

    pub fn getChannelOrder(_: AudioDevice) []const wio.Channel {
        return &.{
            .FL,
            .FR,
            .FC,
            .LFE1,
            .BL,
            .BR,
            .FLc,
            .FRc,
            .BC,
            .SiL,
            .SiR,
            .TpC,
            .TpFL,
            .TpFC,
            .TpFR,
            .TpBL,
            .TpBC,
            .TpBR,
        };
    }
};

const AudioClient = struct {
    thread: std.Thread,
    client: *w.IAudioClient,
    service: *w.IUnknown,
    dataFn: *const fn () void,
    event: w.HANDLE,
    channels: u16,
    stop: bool = false,

    pub fn close(self: *AudioOutput) void {
        self.stop = true;
        self.thread.join();

        std.os.windows.CloseHandle(self.event.?);
        _ = self.service.Release();
        _ = self.client.Release();
        wio.allocator.destroy(self);
    }

    fn outputThread(self: *AudioClient) void {
        const render_client: *w.IAudioRenderClient = @ptrCast(self.service);
        const writeFn: *const fn ([]f32) void = @ptrCast(self.dataFn);

        var size: u32 = undefined;
        SUCCEED(self.client.GetBufferSize(&size), "IAudioClient::GetBufferSize") catch return;

        while (!self.stop) {
            _ = w.WaitForSingleObject(self.event, w.INFINITE);

            var used: u32 = undefined;
            SUCCEED(self.client.GetCurrentPadding(&used), "IAudioClient::GetCurrentPadding") catch break;
            const available = size - used;

            var buffer: [*]f32 = undefined;
            SUCCEED(render_client.GetBuffer(available, @ptrCast(&buffer)), "IAudioRenderClient::GetBuffer") catch break;
            writeFn(buffer[0 .. available * self.channels]);
            SUCCEED(render_client.ReleaseBuffer(available, 0), "IAudioRenderClient::ReleaseBuffer") catch break;
        }
    }

    fn inputThread(self: *AudioClient) void {
        const capture_client: *w.IAudioCaptureClient = @ptrCast(self.service);
        const readFn: *const fn ([]const f32) void = @ptrCast(self.dataFn);

        while (!self.stop) {
            _ = w.WaitForSingleObject(self.event, w.INFINITE);

            var count: u32 = undefined;
            SUCCEED(self.client.GetCurrentPadding(&count), "IAudioClient::GetCurrentPadding") catch break;

            var buffer: [*]f32 = undefined;
            var flags: u32 = undefined;
            SUCCEED(capture_client.GetBuffer(@ptrCast(&buffer), &count, &flags, null, null), "IAudioCaptureClient::GetBuffer") catch break;
            readFn(buffer[0 .. count * self.channels]);
            SUCCEED(capture_client.ReleaseBuffer(count), "IAudioCaptureClient::ReleaseBuffer") catch break;
        }
    }
};

pub const AudioOutput = AudioClient;
pub const AudioInput = AudioClient;

const MMNotificationClient = struct {
    parent: w.IMMNotificationClient = .{ .lpVtbl = &vtbl },
    mutex: std.Thread.Mutex = .{},
    default_output: ?*w.IMMDevice = null,
    default_input: ?*w.IMMDevice = null,

    const vtbl = w.IMMNotificationClient.Vtbl{
        .parent = .{
            .AddRef = AddRef,
            .Release = Release,
            .QueryInterface = QueryInterface,
        },
        .OnDeviceStateChanged = OnDeviceStateChanged,
        .OnDeviceAdded = OnDeviceAdded,
        .OnDeviceRemoved = OnDeviceRemoved,
        .OnDefaultDeviceChanged = OnDefaultDeviceChanged,
        .OnPropertyValueChanged = OnPropertyValueChanged,
    };

    fn AddRef(_: *const anyopaque) callconv(w.WINAPI) u32 {
        return 1;
    }

    fn Release(_: *const anyopaque) callconv(w.WINAPI) u32 {
        return 1;
    }

    fn QueryInterface(_: *const anyopaque, _: [*c]const w.GUID, _: [*c]?*anyopaque) callconv(w.WINAPI) w.HRESULT {
        return w.E_NOINTERFACE;
    }

    fn OnDeviceStateChanged(_: *const anyopaque, _: [*c]const u16, _: u32) callconv(w.WINAPI) w.HRESULT {
        return w.S_OK;
    }

    fn OnDeviceAdded(_: *const anyopaque, _: [*c]const u16) callconv(w.WINAPI) w.HRESULT {
        return w.S_OK;
    }

    fn OnDeviceRemoved(_: *const anyopaque, _: [*c]const u16) callconv(w.WINAPI) w.HRESULT {
        return w.S_OK;
    }

    fn OnDefaultDeviceChanged(_: *const anyopaque, flow: i32, role: i32, id: [*c]const u16) callconv(w.WINAPI) w.HRESULT {
        if (role == w.eConsole) {
            const maybe_device = if (flow == w.eRender and wio.init_options.audioDefaultOutputFn != null)
                &mm_notification_client.default_output
            else if (flow != w.eRender and wio.init_options.audioDefaultInputFn != null)
                &mm_notification_client.default_input
            else
                null;

            if (maybe_device) |device| {
                mm_notification_client.mutex.lock();
                if (device.*) |old| {
                    _ = old.Release();
                    device.* = null;
                }
                SUCCEED(mm_device_enumerator.GetDevice(id, @ptrCast(device)), "IMMDeviceEnumerator::GetDevice") catch {};
                mm_notification_client.mutex.unlock();
            }
        }
        return w.S_OK;
    }

    fn OnPropertyValueChanged(_: *const anyopaque, _: [*c]const u16, _: w.PROPERTYKEY) callconv(w.WINAPI) w.HRESULT {
        return w.S_OK;
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

fn isFullscreen(self: *@This()) bool {
    return (w.GetWindowLongPtrW(self.window, w.GWL_STYLE) & w.WS_OVERLAPPEDWINDOW != w.WS_OVERLAPPEDWINDOW);
}

fn clipCursor(self: *@This()) void {
    var rect: w.RECT = undefined;
    _ = w.GetClientRect(self.window, &rect);
    _ = w.ClientToScreen(self.window, @ptrCast(&rect.left));
    _ = w.ClientToScreen(self.window, @ptrCast(&rect.right));
    _ = w.ClipCursor(&rect);
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

fn helperWindowProc(window: w.HWND, msg: u32, wParam: w.WPARAM, lParam: w.LPARAM) callconv(w.WINAPI) w.LRESULT {
    switch (msg) {
        w.WM_INPUT_DEVICE_CHANGE => {
            if (wio.init_options.joystick) {
                const device: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(lParam)));
                switch (wParam) {
                    w.GIDC_ARRIVAL => {
                        var interface_size: u32 = undefined;
                        if (w.GetRawInputDeviceInfoW(device, w.RIDI_DEVICENAME, null, &interface_size) < 0) return 0;
                        const interface = wio.allocator.alloc(u16, interface_size) catch return 0;
                        if (w.GetRawInputDeviceInfoW(device, w.RIDI_DEVICENAME, interface.ptr, &interface_size) < 0) {
                            wio.allocator.free(interface);
                            return 0;
                        }

                        if (std.mem.indexOf(u16, interface, w.L("IG_"))) |_| {
                            var iter = xinput.iterator(.{ .kind = .unset });
                            while (iter.next()) |i| {
                                var state: w.XINPUT_STATE = undefined;
                                if (w.XInputGetState(@intCast(i), &state) == w.ERROR_SUCCESS) {
                                    xinput.set(i);
                                    if (wio.init_options.joystickConnectedFn) |callback| callback(.{ .backend = .{ .xinput = @intCast(i) } });
                                }
                            }
                            wio.allocator.free(interface);
                            return 0;
                        }

                        joysticks.put(device, .{ .interface = interface }) catch {
                            wio.allocator.free(interface);
                            return 0;
                        };

                        if (wio.init_options.joystickConnectedFn) |callback| callback(.{ .backend = .{ .rawinput = device } });
                    },
                    w.GIDC_REMOVAL => {
                        var iter = xinput.iterator(.{});
                        while (iter.next()) |i| {
                            var state: w.XINPUT_STATE = undefined;
                            if (w.XInputGetState(@intCast(i), &state) == w.ERROR_DEVICE_NOT_CONNECTED) {
                                xinput.unset(i);
                            }
                        }

                        if (joysticks.get(device)) |info| {
                            if (info.joystick) |joystick| {
                                joystick.disconnected = true;
                            }
                            wio.allocator.free(info.interface);
                            _ = joysticks.remove(device);
                        }
                    },
                    else => {},
                }
                return 0;
            }
        },
        w.WM_INPUT => {
            if (wio.init_options.joystick) {
                const handle: w.HRAWINPUT = @ptrFromInt(@as(usize, @bitCast(lParam)));
                var size: u32 = undefined;
                if (w.GetRawInputData(handle, w.RID_INPUT, null, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                if (size > helper_input.len) helper_input = wio.allocator.realloc(helper_input, size) catch return 0;
                if (w.GetRawInputData(handle, w.RID_INPUT, helper_input.ptr, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                const raw: *w.RAWINPUT = @alignCast(@ptrCast(helper_input));

                if (joysticks.get(raw.header.hDevice)) |info| {
                    const joystick = info.joystick orelse return 0;
                    const report = raw.data.hid.bRawData()[0 .. raw.data.hid.dwSizeHid * raw.data.hid.dwCount];
                    var data_len: u32 = @intCast(joystick.data.len);
                    if (w.HidP_GetData(w.HidP_Input, joystick.data.ptr, &data_len, @bitCast(@intFromPtr(joystick.preparsed.ptr)), report.ptr, @intCast(report.len)) == w.HIDP_STATUS_SUCCESS) {
                        @memset(joystick.buttons, false);
                        for (joystick.data[0..data_len]) |data| {
                            switch (joystick.indices[data.DataIndex]) {
                                .none => {},
                                .axis => |axis| {
                                    const caps = &joystick.value_caps[axis.caps_index];
                                    if (data.Anonymous.RawValue >= caps.LogicalMin and data.Anonymous.RawValue <= caps.LogicalMax) {
                                        var float: f32 = @floatFromInt(data.Anonymous.RawValue);
                                        float -= @floatFromInt(caps.LogicalMin);
                                        float /= @floatFromInt(caps.LogicalMax - caps.LogicalMin);
                                        float *= 0xFFFF;
                                        joystick.axes[axis.index] = @intFromFloat(float);
                                    } else {
                                        // broken report descriptor, probably a u16
                                        joystick.axes[axis.index] = @truncate(data.Anonymous.RawValue);
                                    }
                                },
                                .hat => |index| {
                                    joystick.hats[index] = switch (data.Anonymous.RawValue) {
                                        0 => .{ .up = true },
                                        1 => .{ .up = true, .right = true },
                                        2 => .{ .right = true },
                                        3 => .{ .right = true, .down = true },
                                        4 => .{ .down = true },
                                        5 => .{ .down = true, .left = true },
                                        6 => .{ .left = true },
                                        7 => .{ .left = true, .up = true },
                                        else => .{},
                                    };
                                },
                                .button => |index| joystick.buttons[index] = (data.Anonymous.On == w.TRUE),
                            }
                        }
                    }
                }
                return 0;
            }
        },
        else => {},
    }
    return w.DefWindowProcW(window, msg, wParam, lParam);
}

fn windowProc(window: w.HWND, msg: u32, wParam: w.WPARAM, lParam: w.LPARAM) callconv(w.WINAPI) w.LRESULT {
    const self = blk: {
        const userdata: usize = @bitCast(w.GetWindowLongPtrW(window, w.GWLP_USERDATA));
        const ptr: ?*@This() = @ptrFromInt(userdata);
        break :blk ptr orelse return w.DefWindowProcW(window, msg, wParam, lParam);
    };

    if (self.left_shift and self.right_shift) {
        // when both shifts are pressed, only one keyup message is sent
        if (w.GetAsyncKeyState(w.VK_LSHIFT) == 0) {
            self.left_shift = false;
            self.pushEvent(.{ .button_release = .left_shift });
        }
        if (w.GetAsyncKeyState(w.VK_RSHIFT) == 0) {
            self.right_shift = false;
            self.pushEvent(.{ .button_release = .right_shift });
        }
    }

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
                    .hidden, .relative => while (w.ShowCursor(w.FALSE) >= 0) {},
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
            if (self.cursor_mode == .relative) {
                self.clipCursor();
            }
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
            if (self.cursor_mode == .relative) {
                self.clipCursor();
            }
            if (wParam == w.SIZE_RESTORED or wParam == w.SIZE_MAXIMIZED) {
                const fullscreen = self.isFullscreen();
                if (wParam == w.SIZE_RESTORED and !fullscreen) {
                    _ = w.GetWindowRect(window, &self.rect);
                }
                self.pushEvent(.{ .mode = if (fullscreen) .fullscreen else if (wParam == w.SIZE_MAXIMIZED) .maximized else .normal });
                self.pushEvent(.{ .size = size });
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

            if (scancodeToButton(scancode)) |button| {
                const modifier = switch (button) {
                    .left_shift => &self.left_shift,
                    .right_shift => &self.right_shift,
                    .left_control => &self.left_control,
                    .right_control => &self.right_control,
                    .left_alt => &self.left_alt,
                    .right_alt => &self.right_alt,
                    .international2 => &self.international2,
                    .international3 => &self.international3,
                    .international4 => &self.international4,
                    else => null,
                };
                if (flags & w.KF_UP == 0) {
                    var repeat = (flags & w.KF_REPEAT != 0);
                    if (modifier) |ptr| {
                        repeat = ptr.*;
                        ptr.* = true;
                    }
                    self.pushEvent(if (repeat) .{ .button_repeat = button } else .{ .button_press = button });
                } else {
                    if (modifier) |ptr| ptr.* = false;
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
            if (self.cursor_mode != .relative) self.pushEvent(.{ .mouse = .{ .x = LOWORD(lParam), .y = HIWORD(lParam) } });
            return 0;
        },
        w.WM_INPUT => {
            if (self.cursor_mode == .relative) {
                const handle: w.HRAWINPUT = @ptrFromInt(@as(usize, @bitCast(lParam)));
                var size: u32 = undefined;
                if (w.GetRawInputData(handle, w.RID_INPUT, null, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                if (size > self.input.len) self.input = wio.allocator.realloc(self.input, size) catch return 0;
                if (w.GetRawInputData(handle, w.RID_INPUT, self.input.ptr, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                const raw: *w.RAWINPUT = @alignCast(@ptrCast(self.input));

                if (raw.data.mouse.usFlags & w.MOUSE_MOVE_ABSOLUTE != 0) {
                    if (raw.data.mouse.lLastX != 0 or raw.data.mouse.lLastY != 0) { // prevent spurious (0,0)
                        if (raw.data.mouse.Anonymous.Anonymous.usButtonFlags == 0) { // prevent jumping on touch input
                            self.pushEvent(.{ .mouse_relative = .{ .x = @intCast(raw.data.mouse.lLastX - self.last_x), .y = @intCast(raw.data.mouse.lLastY - self.last_y) } });
                        }
                        self.last_x = @intCast(raw.data.mouse.lLastX);
                        self.last_y = @intCast(raw.data.mouse.lLastY);
                    }
                } else {
                    self.pushEvent(.{ .mouse_relative = .{ .x = @intCast(raw.data.mouse.lLastX), .y = @intCast(raw.data.mouse.lLastY) } });
                }
            }
            return 0;
        },
        w.WM_MOUSEWHEEL, w.WM_MOUSEHWHEEL => {
            const delta: f32 = @floatFromInt(HISHORT(wParam));
            const value = delta / w.WHEEL_DELTA;
            self.pushEvent(if (msg == w.WM_MOUSEWHEEL) .{ .scroll_vertical = -value } else .{ .scroll_horizontal = value });
            return 0;
        },
        else => return w.DefWindowProcW(window, msg, wParam, lParam),
    }
}

fn scancodeToButton(scancode: u9) ?wio.Button {
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
            0x71 => .lang2,
            0x72 => .lang1,
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

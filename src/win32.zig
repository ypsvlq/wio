const std = @import("std");
const build_options = @import("build_options");
pub const win32 = @import("win32");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const w = win32;
const log = std.log.scoped(.wio);

const class_name = w.L("wio");

var helper_window: w.HWND = undefined;

var wgl: struct {
    swapIntervalEXT: ?*const fn (i32) callconv(.winapi) w.BOOL = null,
    choosePixelFormatARB: ?*const fn (w.HDC, ?[*]const i32, ?[*]const f32, u32, [*c]i32, *u32) callconv(.winapi) w.BOOL = null,
    createContextAttribsARB: ?*const fn (w.HDC, w.HGLRC, [*]const i32) callconv(.winapi) w.HGLRC = null,
} = .{};

var vulkan: w.HMODULE = undefined;

const JoystickInfo = struct {
    interface: []u16,
    joystick: ?*RawInputJoystick = null,
};
var joysticks: std.AutoHashMapUnmanaged(w.HANDLE, JoystickInfo) = undefined;
var xinput = std.StaticBitSet(4).initEmpty();
var helper_input: []u8 = &.{};

var mm_device_enumerator: *w.IMMDeviceEnumerator = undefined;
var mm_notification_client = MMNotificationClient{};

pub fn init() !void {
    const instance = w.GetModuleHandleW(null);

    const class = std.mem.zeroInit(w.WNDCLASSW, .{
        .lpfnWndProc = windowProc,
        .hInstance = instance,
        .lpszClassName = class_name,
    });
    if (w.RegisterClassW(&class) == 0) return logLastError("RegisterClassW");

    var mouse = w.RAWINPUTDEVICE{
        .usUsagePage = w.HID_USAGE_PAGE_GENERIC,
        .usUsage = w.HID_USAGE_GENERIC_MOUSE,
        .dwFlags = 0,
        .hwndTarget = null,
    };
    if (w.RegisterRawInputDevices(&mouse, 1, @sizeOf(w.RAWINPUTDEVICE)) == w.FALSE) return logLastError("RegisterRawInputDevices");

    if (build_options.opengl or build_options.joystick) {
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

        if (build_options.joystick) {
            _ = w.SetWindowLongPtrW(helper_window, w.GWLP_WNDPROC, @bitCast(@intFromPtr(&helperWindowProc)));
        }
    }

    if (build_options.opengl) {
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
            const getExtensionsStringARB: *const fn (w.HDC) callconv(.winapi) ?[*:0]const u8 = @ptrCast(proc);
            if (getExtensionsStringARB(dc)) |extensions| {
                var iter = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (iter.next()) |name| {
                    if (std.mem.eql(u8, name, "WGL_EXT_swap_control")) {
                        wgl.swapIntervalEXT = @ptrCast(w.wglGetProcAddress("wglSwapIntervalEXT"));
                    } else if (std.mem.eql(u8, name, "WGL_ARB_pixel_format")) {
                        wgl.choosePixelFormatARB = @ptrCast(w.wglGetProcAddress("wglChoosePixelFormatARB"));
                    } else if (std.mem.eql(u8, name, "WGL_ARB_create_context_profile")) {
                        wgl.createContextAttribsARB = @ptrCast(w.wglGetProcAddress("wglCreateContextAttribsARB"));
                    }
                }
            }
        }
    }

    if (build_options.vulkan) {
        vulkan = w.LoadLibraryW(w.L("vulkan-1.dll")) orelse return logLastError("LoadLibraryW");
        vkGetInstanceProcAddr = @ptrCast(w.GetProcAddress(vulkan, "vkGetInstanceProcAddr") orelse return logLastError("GetProcAddress"));
    }

    if (build_options.joystick) {
        joysticks = .empty;

        var devices = [_]w.RAWINPUTDEVICE{
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
        if (w.RegisterRawInputDevices(&devices, devices.len, @sizeOf(w.RAWINPUTDEVICE)) == w.FALSE) return logLastError("RegisterRawInputDevices");
    }

    if (build_options.audio) {
        try SUCCEED(w.CoInitializeEx(null, w.COINIT_MULTITHREADED | w.COINIT_DISABLE_OLE1DDE), "CoInitializeEx");
        try SUCCEED(w.CoCreateInstance(&w.CLSID_MMDeviceEnumerator, null, w.CLSCTX_ALL, &w.IID_IMMDeviceEnumerator, @ptrCast(&mm_device_enumerator)), "CoCreateInstance");

        var device: *w.IMMDevice = undefined;
        if (internal.init_options.audioDefaultOutputFn) |callback| {
            if (SUCCEED(mm_device_enumerator.GetDefaultAudioEndpoint(w.eRender, w.eConsole, @ptrCast(&device)), "GetDefaultAudioEndpoint")) {
                callback(.{ .backend = .{ .device = device } });
            } else |_| {}
        }
        if (internal.init_options.audioDefaultInputFn) |callback| {
            if (SUCCEED(mm_device_enumerator.GetDefaultAudioEndpoint(w.eCapture, w.eConsole, @ptrCast(&device)), "GetDefaultAudioEndpoint")) {
                callback(.{ .backend = .{ .device = device } });
            } else |_| {}
        }

        if (internal.init_options.audioDefaultOutputFn != null or internal.init_options.audioDefaultInputFn != null) {
            try SUCCEED(mm_device_enumerator.RegisterEndpointNotificationCallback(&mm_notification_client.interface), "RegisterEndpointNotificationCallback");
        }
    }
}

pub fn deinit() void {
    if (build_options.vulkan) {
        _ = w.FreeLibrary(vulkan);
    }

    if (build_options.opengl or build_options.joystick) {
        _ = w.DestroyWindow(helper_window);
    }

    if (build_options.joystick) {
        internal.allocator.free(helper_input);

        var iter = joysticks.valueIterator();
        while (iter.next()) |info| internal.allocator.free(info.interface);
        joysticks.deinit(internal.allocator);
    }

    if (build_options.audio) {
        _ = mm_device_enumerator.Release();
        w.CoUninitialize();
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        update();
    }
}

pub fn update() void {
    var msg: w.MSG = undefined;

    while (w.PeekMessageW(&msg, null, 0, 0, w.PM_REMOVE) != 0) {
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }

    if (build_options.audio) {
        var maybe_device: ?*w.IMMDevice = undefined;
        if (internal.init_options.audioDefaultOutputFn) |callback| {
            mm_notification_client.mutex.lock();
            maybe_device = mm_notification_client.default_output;
            mm_notification_client.default_output = null;
            mm_notification_client.mutex.unlock();
            if (maybe_device) |device| callback(.{ .backend = .{ .device = device } });
        }
        if (internal.init_options.audioDefaultInputFn) |callback| {
            mm_notification_client.mutex.lock();
            maybe_device = mm_notification_client.default_input;
            mm_notification_client.default_input = null;
            mm_notification_client.mutex.unlock();
            if (maybe_device) |device| callback(.{ .backend = .{ .device = device } });
        }
    }
}

pub fn wait() void {
    _ = w.MsgWaitForMultipleObjects(0, null, w.FALSE, w.INFINITE, w.QS_ALLINPUT);
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    const title_w = std.unicode.utf8ToUtf16LeAllocZ(internal.allocator, title) catch return;
    defer internal.allocator.free(title_w);
    const message_w = std.unicode.utf8ToUtf16LeAllocZ(internal.allocator, message) catch return;
    defer internal.allocator.free(message_w);

    var flags: u32 = w.MB_TASKMODAL | w.MB_TOPMOST;
    flags |= switch (style) {
        .info => w.MB_ICONINFORMATION,
        .warn => w.MB_ICONWARNING,
        .err => w.MB_ICONERROR,
    };
    _ = w.MessageBoxW(null, message_w, title_w, flags);
}

events: internal.EventQueue,
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
opengl: if (build_options.opengl) struct { dc: w.HDC = null, rc: w.HGLRC = null } else struct {} = .{},

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const title = try std.unicode.utf8ToUtf16LeAllocZ(internal.allocator, options.title);
    defer internal.allocator.free(title);
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
        @ptrFromInt(options.parent),
        null,
        w.GetModuleHandleW(null),
        null,
    ) orelse return logLastError("CreateWindowExW");

    const self = try internal.allocator.create(@This());
    errdefer internal.allocator.destroy(self);
    self.* = .{
        .events = .init(),
        .window = window,
        .cursor = loadCursor(options.cursor),
        .cursor_mode = options.cursor_mode, // WM_SETFOCUS calls clipCursor, so setCursorMode is not needed
    };
    _ = w.SetWindowLongPtrW(window, w.GWLP_USERDATA, @bitCast(@intFromPtr(self)));

    const dpi: f32 = @floatFromInt(w.GetDpiForWindow(window));
    const scale = dpi / w.USER_DEFAULT_SCREEN_DPI;
    self.events.push(.{ .scale = scale });

    if (options.scale) |base| {
        const scaled = clientToWindow(options.size.multiply(scale / base), style);
        _ = w.SetWindowPos(window, null, 0, 0, scaled.width, scaled.height, w.SWP_NOMOVE | w.SWP_NOZORDER);
    }

    self.setMode(options.mode);

    if (build_options.opengl) {
        if (options.opengl) |opengl| {
            self.opengl.dc = w.GetDC(self.window);

            var format: i32 = undefined;
            var pfd: w.PIXELFORMATDESCRIPTOR = undefined;
            if (wgl.choosePixelFormatARB) |choosePixelFormatARB| {
                var count: u32 = undefined;
                _ = choosePixelFormatARB(self.opengl.dc, &.{
                    0x2011, if (opengl.doublebuffer) 1 else 0,
                    0x2015, opengl.red_bits,
                    0x2017, opengl.green_bits,
                    0x2019, opengl.blue_bits,
                    0x201B, opengl.alpha_bits,
                    0x2022, opengl.depth_bits,
                    0x2023, opengl.stencil_bits,
                    0x2041, if (opengl.samples != 0) 1 else 0,
                    0x2042, opengl.samples,
                    0,
                }, null, 1, &format, &count);
                if (count != 1) return logLastError("wglChoosePixelFormatARB");
                _ = w.DescribePixelFormat(self.opengl.dc, format, @sizeOf(w.PIXELFORMATDESCRIPTOR), &pfd);
            } else {
                pfd = std.mem.zeroInit(w.PIXELFORMATDESCRIPTOR, .{
                    .nSize = @sizeOf(w.PIXELFORMATDESCRIPTOR),
                    .nVersion = 1,
                    .dwFlags = w.PFD_DRAW_TO_WINDOW | w.PFD_SUPPORT_OPENGL | if (opengl.doublebuffer) w.PFD_DOUBLEBUFFER else 0,
                    .iPixelType = w.PFD_TYPE_RGBA,
                    .cColorBits = opengl.red_bits + opengl.green_bits + opengl.blue_bits,
                    .cAlphaBits = opengl.alpha_bits,
                    .cDepthBits = opengl.depth_bits,
                    .cStencilBits = opengl.stencil_bits,
                });
                format = w.ChoosePixelFormat(self.opengl.dc, &pfd);
                if (format == 0) return logLastError("ChoosePixelFormat");
            }
            _ = w.SetPixelFormat(self.opengl.dc, format, &pfd);

            self.opengl.rc = if (wgl.createContextAttribsARB) |createContextAttribsARB|
                createContextAttribsARB(self.opengl.dc, null, &[_]i32{
                    0x2091, opengl.major_version,
                    0x2092, opengl.minor_version,
                    0x2094, @as(i32, if (opengl.debug) 1 else 0) | @as(i32, if (opengl.forward_compatible) 2 else 0),
                    0x9126, if (opengl.profile == .core) 1 else 2,
                    0,
                }) orelse return logLastError("wglCreateContextAttribsARB")
            else
                w.wglCreateContext(self.opengl.dc) orelse return logLastError("wglCreateContext");
        }
    }

    return self;
}

pub fn destroy(self: *@This()) void {
    if (build_options.opengl) {
        _ = w.wglDeleteContext(self.opengl.rc);
        _ = w.ReleaseDC(self.window, self.opengl.dc);
    }
    _ = w.DestroyWindow(self.window);
    self.events.deinit();
    internal.allocator.free(self.input);
    internal.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.pop();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_w = std.unicode.utf8ToUtf16LeAllocZ(internal.allocator, title) catch return;
    defer internal.allocator.free(title_w);
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
    self.cursor = loadCursor(shape);

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

pub fn setSize(self: *@This(), size: wio.Size) void {
    const style: u32 = @bitCast(@as(i32, @intCast(w.GetWindowLongPtrW(self.window, w.GWL_STYLE))));
    const window_size = clientToWindow(size, style);
    _ = w.SetWindowPos(self.window, null, 0, 0, window_size.width, window_size.height, w.SWP_NOMOVE | w.SWP_NOZORDER);
}

pub fn setParent(self: *@This(), parent: usize) void {
    _ = w.SetParent(self.window, @ptrFromInt(parent));
}

pub fn requestAttention(self: *@This()) void {
    _ = w.FlashWindow(self.window, w.TRUE);
}

pub fn setClipboardText(_: *@This(), text: []const u8) void {
    if (w.OpenClipboard(null) == 0) return;
    defer _ = w.CloseClipboard();
    const text_w = std.unicode.utf8ToUtf16LeAlloc(internal.allocator, text) catch return;
    defer internal.allocator.free(text_w);
    const mem = w.GlobalAlloc(w.GMEM_MOVEABLE, (text_w.len + 1) * @sizeOf(u16)) orelse return;
    const buf: [*]u16 = @ptrCast(@alignCast(w.GlobalLock(mem) orelse {
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

pub fn getClipboardText(_: *@This(), allocator: std.mem.Allocator) ?[]u8 {
    if (w.OpenClipboard(null) == 0) return null;
    defer _ = w.CloseClipboard();
    const mem = w.GetClipboardData(w.CF_UNICODETEXT) orelse return null;
    const text: [*:0]const u16 = @ptrCast(@alignCast(w.GlobalLock(mem) orelse return null));
    defer _ = w.GlobalUnlock(mem);
    return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(text, 0)) catch null;
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = w.wglMakeCurrent(self.opengl.dc, self.opengl.rc);
}

pub fn swapBuffers(self: *@This()) void {
    _ = w.SwapBuffers(self.opengl.dc);
}

pub fn swapInterval(_: @This(), interval: i32) void {
    if (wgl.swapIntervalEXT) |swapIntervalEXT| {
        _ = swapIntervalEXT(interval);
    }
}

pub fn createSurface(self: @This(), instance: usize, allocator: ?*const anyopaque, surface: *u64) i32 {
    const VkWin32SurfaceCreateInfoKHR = extern struct {
        sType: i32 = 1000009000,
        pNext: ?*const anyopaque = null,
        flags: u32 = 0,
        hinstance: w.HINSTANCE,
        hwnd: w.HWND,
    };

    const vkCreateWin32SurfaceKHR: *const fn (usize, *const VkWin32SurfaceCreateInfoKHR, ?*const anyopaque, *u64) callconv(.winapi) i32 =
        @ptrCast(vkGetInstanceProcAddr(instance, "vkCreateWin32SurfaceKHR"));

    return vkCreateWin32SurfaceKHR(
        instance,
        &.{
            .hinstance = w.GetModuleHandleW(null),
            .hwnd = self.window,
        },
        allocator,
        surface,
    );
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    if (@hasDecl(w, name)) {
        return &@field(w, name);
    }
    return w.wglGetProcAddress(name);
}

pub var vkGetInstanceProcAddr: *const fn (usize, [*:0]const u8) callconv(.winapi) ?*const fn () void = undefined;

pub fn getVulkanExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_win32_surface" };
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
        const joystick = try internal.allocator.create(Joystick);
        errdefer internal.allocator.destroy(joystick);
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.getPtr(device) orelse return error.Unexpected;
                if (info.joystick) |_| return error.Unexpected;

                var preparsed_size: u32 = undefined;
                if (w.GetRawInputDeviceInfoW(device, w.RIDI_PREPARSEDDATA, null, &preparsed_size) < 0) return error.Unexpected;
                const preparsed = try internal.allocator.alloc(u8, preparsed_size);
                errdefer internal.allocator.free(preparsed);
                if (w.GetRawInputDeviceInfoW(device, w.RIDI_PREPARSEDDATA, preparsed.ptr, &preparsed_size) < 0) return error.Unexpected;

                var caps: w.HIDP_CAPS = undefined;
                if (w.HidP_GetCaps(@bitCast(@intFromPtr(preparsed.ptr)), &caps) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                var value_caps_len = caps.NumberInputValueCaps;
                const value_caps = try internal.allocator.alloc(w.HIDP_VALUE_CAPS, value_caps_len);
                errdefer internal.allocator.free(value_caps);
                if (w.HidP_GetValueCaps(w.HidP_Input, value_caps.ptr, &value_caps_len, @bitCast(@intFromPtr(preparsed.ptr))) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                var button_caps_len = caps.NumberInputButtonCaps;
                const button_caps = try internal.allocator.alloc(w.HIDP_BUTTON_CAPS, button_caps_len);
                defer internal.allocator.free(button_caps);
                if (w.HidP_GetButtonCaps(w.HidP_Input, button_caps.ptr, &button_caps_len, @bitCast(@intFromPtr(preparsed.ptr))) != w.HIDP_STATUS_SUCCESS) return error.Unexpected;

                const data_len = w.HidP_MaxDataListLength(w.HidP_Input, @bitCast(@intFromPtr(preparsed.ptr)));
                const data = try internal.allocator.alloc(w.HIDP_DATA, data_len);
                errdefer internal.allocator.free(data);

                const indices = try internal.allocator.alloc(RawInputJoystick.DataIndex, data_len);
                errdefer internal.allocator.free(indices);
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

                const axes = try internal.allocator.alloc(u16, axis_count);
                errdefer internal.allocator.free(axes);
                @memset(axes, 0xFFFF / 2);

                const hats = try internal.allocator.alloc(wio.Hat, hat_count);
                errdefer internal.allocator.free(hats);
                @memset(hats, .{});

                const buttons = try internal.allocator.alloc(bool, button_count);
                errdefer internal.allocator.free(buttons);
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

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.get(device) orelse return error.Unexpected;
                return std.unicode.utf16LeToUtf8Alloc(allocator, info.interface[0 .. info.interface.len - 1]);
            },
            .xinput => return allocator.dupe(u8, "xinput"),
        }
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .rawinput => |device| {
                const info = joysticks.get(device) orelse return error.Unexpected;
                const collection = w.CreateFileW(info.interface.ptr, 0, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_EXISTING, 0, null) orelse return error.Unexpected;
                defer std.os.windows.CloseHandle(collection);
                var product: [2046]u16 = undefined;
                product[0] = 0;
                if (w.HidD_GetProductString(collection, &product, product.len * @sizeOf(u16)) == w.FALSE) return error.Unexpected;
                return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(&product, 0));
            },
            .xinput => return allocator.dupe(u8, "Xbox Controller"),
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
        internal.allocator.destroy(self);
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
        internal.allocator.free(self.buttons);
        internal.allocator.free(self.hats);
        internal.allocator.free(self.axes);
        internal.allocator.free(self.indices);
        internal.allocator.free(self.data);
        internal.allocator.free(self.value_caps);
        internal.allocator.free(self.preparsed);
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

        const block_align = format.channels * @sizeOf(f32);
        const waveformat = w.WAVEFORMATEX{
            .wFormatTag = w.WAVE_FORMAT_IEEE_FLOAT,
            .nChannels = format.channels,
            .nSamplesPerSec = format.sample_rate,
            .nAvgBytesPerSec = format.sample_rate * block_align,
            .nBlockAlign = block_align,
            .wBitsPerSample = @bitSizeOf(f32),
            .cbSize = 0,
        };
        try SUCCEED(client.Initialize(w.AUDCLNT_SHAREMODE_SHARED, w.AUDCLNT_STREAMFLAGS_EVENTCALLBACK | w.AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | w.AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, 0, 0, &waveformat, null), "IAudioClient::Initialize");

        const event = w.CreateEventW(null, w.FALSE, w.FALSE, null) orelse return logLastError("CreateEventW");
        errdefer std.os.windows.CloseHandle(event);
        try SUCCEED(client.SetEventHandle(event), "IAudioClient::SetEventHandle");

        var service: *w.IUnknown = undefined;
        try SUCCEED(client.GetService(guid, @ptrCast(&service)), "IAudioClient::GetService");
        errdefer _ = service.Release();

        try SUCCEED(client.Start(), "IAudioClient::Start");

        const result = try internal.allocator.create(AudioClient);
        errdefer internal.allocator.destroy(result);
        result.* = .{
            .thread = undefined,
            .client = client,
            .event = event,
            .channels = format.channels,
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
};

const AudioClient = struct {
    thread: std.Thread,
    client: *w.IAudioClient,
    service: *w.IUnknown,
    dataFn: *const fn () void,
    event: w.HANDLE,
    channels: u16,
    stop: std.atomic.Value(bool) = .init(false),

    pub fn close(self: *AudioOutput) void {
        self.stop.store(true, .unordered);
        self.thread.join();

        std.os.windows.CloseHandle(self.event.?);
        _ = self.service.Release();
        _ = self.client.Release();
        internal.allocator.destroy(self);
    }

    fn outputThread(self: *AudioClient) void {
        const render_client: *w.IAudioRenderClient = @ptrCast(self.service);
        const writeFn: *const fn ([]f32) void = @ptrCast(self.dataFn);

        var size: u32 = undefined;
        SUCCEED(self.client.GetBufferSize(&size), "IAudioClient::GetBufferSize") catch return;

        while (!self.stop.load(.unordered)) {
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

        while (!self.stop.load(.unordered)) {
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
    interface: w.IMMNotificationClient = .{ .lpVtbl = &.{
        .QueryInterface = QueryInterface,
        .AddRef = AddRef,
        .Release = Release,
        .OnDeviceStateChanged = OnDeviceStateChanged,
        .OnDeviceAdded = OnDeviceAdded,
        .OnDeviceRemoved = OnDeviceRemoved,
        .OnDefaultDeviceChanged = OnDefaultDeviceChanged,
        .OnPropertyValueChanged = OnPropertyValueChanged,
    } },
    mutex: std.Thread.Mutex = .{},
    default_output: ?*w.IMMDevice = null,
    default_input: ?*w.IMMDevice = null,

    fn QueryInterface(_: *w.IMMNotificationClient, _: [*c]const w.GUID, _: [*c]?*anyopaque) callconv(.winapi) w.HRESULT {
        return w.E_NOINTERFACE;
    }

    fn AddRef(_: *w.IMMNotificationClient) callconv(.winapi) u32 {
        return 1;
    }

    fn Release(_: *w.IMMNotificationClient) callconv(.winapi) u32 {
        return 1;
    }

    fn OnDeviceStateChanged(_: *w.IMMNotificationClient, _: [*c]const u16, _: u32) callconv(.winapi) w.HRESULT {
        return w.S_OK;
    }

    fn OnDeviceAdded(_: *w.IMMNotificationClient, _: [*c]const u16) callconv(.winapi) w.HRESULT {
        return w.S_OK;
    }

    fn OnDeviceRemoved(_: *w.IMMNotificationClient, _: [*c]const u16) callconv(.winapi) w.HRESULT {
        return w.S_OK;
    }

    fn OnDefaultDeviceChanged(_: *w.IMMNotificationClient, flow: i32, role: i32, id: [*c]const u16) callconv(.winapi) w.HRESULT {
        if (role == w.eConsole) {
            const maybe_device = if (flow == w.eRender and internal.init_options.audioDefaultOutputFn != null)
                &mm_notification_client.default_output
            else if (flow != w.eRender and internal.init_options.audioDefaultInputFn != null)
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

    fn OnPropertyValueChanged(_: *w.IMMNotificationClient, _: [*c]const u16, _: w.PROPERTYKEY) callconv(.winapi) w.HRESULT {
        return w.S_OK;
    }
};

fn isFullscreen(self: *@This()) bool {
    return (w.GetWindowLongPtrW(self.window, w.GWL_STYLE) & w.WS_OVERLAPPEDWINDOW != w.WS_OVERLAPPEDWINDOW);
}

fn clipCursor(self: *@This()) void {
    var rect: w.RECT = undefined;
    _ = w.GetClientRect(self.window, &rect);
    _ = w.MapWindowPoints(self.window, w.HWND_DESKTOP, @ptrCast(&rect), 2);
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

fn loadCursor(shape: wio.Cursor) w.HCURSOR {
    return w.LoadCursorW(null, switch (shape) {
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

fn LOSHORT(x: anytype) i16 {
    return @bitCast(LOWORD(x));
}

fn HISHORT(x: anytype) i16 {
    return @bitCast(HIWORD(x));
}

fn helperWindowProc(window: w.HWND, msg: u32, wParam: w.WPARAM, lParam: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        w.WM_INPUT_DEVICE_CHANGE => {
            const device: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(lParam)));
            switch (wParam) {
                w.GIDC_ARRIVAL => {
                    var interface_size: u32 = undefined;
                    if (w.GetRawInputDeviceInfoW(device, w.RIDI_DEVICENAME, null, &interface_size) < 0) return 0;
                    const interface = internal.allocator.alloc(u16, interface_size) catch return 0;
                    if (w.GetRawInputDeviceInfoW(device, w.RIDI_DEVICENAME, interface.ptr, &interface_size) < 0) {
                        internal.allocator.free(interface);
                        return 0;
                    }

                    if (std.mem.indexOf(u16, interface, w.L("IG_"))) |_| {
                        var iter = xinput.iterator(.{ .kind = .unset });
                        while (iter.next()) |i| {
                            var state: w.XINPUT_STATE = undefined;
                            if (w.XInputGetState(@intCast(i), &state) == w.ERROR_SUCCESS) {
                                xinput.set(i);
                                if (internal.init_options.joystickConnectedFn) |callback| callback(.{ .backend = .{ .xinput = @intCast(i) } });
                            }
                        }
                        internal.allocator.free(interface);
                        return 0;
                    }

                    joysticks.put(internal.allocator, device, .{ .interface = interface }) catch {
                        internal.allocator.free(interface);
                        return 0;
                    };

                    if (internal.init_options.joystickConnectedFn) |callback| callback(.{ .backend = .{ .rawinput = device } });
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
                        internal.allocator.free(info.interface);
                        _ = joysticks.remove(device);
                    }
                },
                else => {},
            }
            return 0;
        },
        w.WM_INPUT => {
            const handle: w.HRAWINPUT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            var size: u32 = undefined;
            if (w.GetRawInputData(handle, w.RID_INPUT, null, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
            if (size > helper_input.len) helper_input = internal.allocator.realloc(helper_input, size) catch return 0;
            if (w.GetRawInputData(handle, w.RID_INPUT, helper_input.ptr, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
            const raw: *w.RAWINPUT = @ptrCast(@alignCast(helper_input));

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
        },
        else => return w.DefWindowProcW(window, msg, wParam, lParam),
    }
}

fn windowProc(window: w.HWND, msg: u32, wParam: w.WPARAM, lParam: w.LPARAM) callconv(.winapi) w.LRESULT {
    const self = blk: {
        const userdata: usize = @bitCast(w.GetWindowLongPtrW(window, w.GWLP_USERDATA));
        const ptr: ?*@This() = @ptrFromInt(userdata);
        break :blk ptr orelse return w.DefWindowProcW(window, msg, wParam, lParam);
    };

    // when both shifts are pressed, only one keyup message is sent
    if (self.left_shift) {
        if (w.GetAsyncKeyState(w.VK_LSHIFT) == 0) {
            self.left_shift = false;
            self.events.push(.{ .button_release = .left_shift });
        }
    }
    if (self.right_shift) {
        if (w.GetAsyncKeyState(w.VK_RSHIFT) == 0) {
            self.right_shift = false;
            self.events.push(.{ .button_release = .right_shift });
        }
    }

    switch (msg) {
        w.WM_SYSCOMMAND => {
            switch (wParam & 0xFFF0) {
                w.SC_KEYMENU => return 0,
                w.SC_SCREENSAVE, w.SC_MONITORPOWER => return if (self.isFullscreen()) 0 else w.DefWindowProcW(window, msg, wParam, lParam),
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
            self.events.push(.close);
            return 0;
        },
        w.WM_SETFOCUS => {
            self.events.push(.focused);
            if (self.cursor_mode == .relative) {
                self.clipCursor();
            }
            return 0;
        },
        w.WM_KILLFOCUS => {
            self.events.push(.unfocused);
            return 0;
        },
        w.WM_PAINT => {
            self.events.push(.draw);
            _ = w.ValidateRgn(window, null);
            return 0;
        },
        w.WM_SIZE => {
            const size = wio.Size{ .width = LOWORD(lParam), .height = HIWORD(lParam) };
            if (self.cursor_mode == .relative) {
                self.clipCursor();
            }
            switch (wParam) {
                w.SIZE_RESTORED, w.SIZE_MAXIMIZED => {
                    const fullscreen = self.isFullscreen();
                    if (wParam == w.SIZE_RESTORED and !fullscreen) {
                        _ = w.GetWindowRect(window, &self.rect);
                    }
                    self.events.push(.visible);
                    self.events.push(.{ .mode = if (fullscreen) .fullscreen else if (wParam == w.SIZE_MAXIMIZED) .maximized else .normal });
                    self.events.push(.{ .size = size });
                    self.events.push(.{ .framebuffer = size });
                    self.events.push(.draw);
                },
                w.SIZE_MINIMIZED => self.events.push(.hidden),
                else => {},
            }
            return 0;
        },
        w.WM_DPICHANGED => {
            const dpi: f32 = @floatFromInt(LOWORD(wParam));
            const scale = dpi / w.USER_DEFAULT_SCREEN_DPI;
            self.events.push(.{ .scale = scale });
            return 0;
        },
        w.WM_CHAR => {
            const char: u16 = @intCast(wParam);
            const codepoint = blk: {
                if (self.surrogate != 0) {
                    defer self.surrogate = 0;
                    break :blk std.unicode.utf16DecodeSurrogatePair(&.{ self.surrogate, char }) catch return 0;
                } else if (std.unicode.utf16IsHighSurrogate(char)) {
                    self.surrogate = char;
                    return 0;
                } else {
                    break :blk char;
                }
            };
            if (codepoint >= ' ') {
                self.events.push(.{ .char = codepoint });
            }
            return 0;
        },
        w.WM_KEYDOWN, w.WM_SYSKEYDOWN, w.WM_KEYUP, w.WM_SYSKEYUP => {
            if (wParam == w.VK_PROCESSKEY) {
                return 0;
            }

            if (msg == w.WM_SYSKEYDOWN and wParam == w.VK_F4) {
                self.events.push(.close);
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
                    self.events.push(if (repeat) .{ .button_repeat = button } else .{ .button_press = button });
                } else {
                    if (modifier) |ptr| ptr.* = false;
                    self.events.push(.{ .button_release = button });
                }
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
                => self.events.push(.{ .button_press = button }),
                else => self.events.push(.{ .button_release = button }),
            }

            return if (msg == w.WM_XBUTTONDOWN or msg == w.WM_XBUTTONUP) w.TRUE else 0;
        },
        w.WM_MOUSEMOVE => {
            if (self.cursor_mode != .relative) {
                const x = LOSHORT(lParam);
                const y = HISHORT(lParam);
                if (x >= 0 and y >= 0) {
                    self.events.push(.{ .mouse = .{ .x = @intCast(x), .y = @intCast(y) } });
                }
            }
            return 0;
        },
        w.WM_INPUT => {
            if (self.cursor_mode == .relative) {
                const handle: w.HRAWINPUT = @ptrFromInt(@as(usize, @bitCast(lParam)));
                var size: u32 = undefined;
                if (w.GetRawInputData(handle, w.RID_INPUT, null, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                if (size > self.input.len) self.input = internal.allocator.realloc(self.input, size) catch return 0;
                if (w.GetRawInputData(handle, w.RID_INPUT, self.input.ptr, &size, @sizeOf(w.RAWINPUTHEADER)) == -1) return 0;
                const raw: *w.RAWINPUT = @ptrCast(@alignCast(self.input));

                if (raw.data.mouse.usFlags & w.MOUSE_MOVE_ABSOLUTE != 0) {
                    if (raw.data.mouse.lLastX != 0 or raw.data.mouse.lLastY != 0) { // prevent spurious (0,0)
                        if (raw.data.mouse.Anonymous.Anonymous.usButtonFlags == 0) { // prevent jumping on touch input
                            self.events.push(.{ .mouse_relative = .{ .x = @intCast(raw.data.mouse.lLastX - self.last_x), .y = @intCast(raw.data.mouse.lLastY - self.last_y) } });
                        }
                        self.last_x = @intCast(raw.data.mouse.lLastX);
                        self.last_y = @intCast(raw.data.mouse.lLastY);
                    }
                } else {
                    self.events.push(.{ .mouse_relative = .{ .x = @intCast(raw.data.mouse.lLastX), .y = @intCast(raw.data.mouse.lLastY) } });
                }
            }
            return 0;
        },
        w.WM_MOUSEWHEEL, w.WM_MOUSEHWHEEL => {
            const delta: f32 = @floatFromInt(HISHORT(wParam));
            const value = delta / w.WHEEL_DELTA;
            self.events.push(if (msg == w.WM_MOUSEWHEEL) .{ .scroll_vertical = -value } else .{ .scroll_horizontal = value });
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

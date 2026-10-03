const std = @import("std");
const build_options = @import("build_options");
const c = @import("c");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

const NSWindow = opaque {};
const NSOpenGLPixelFormat = opaque {};
const NSOpenGLContext = opaque {};
const CAMetalLayer = opaque {};
extern fn wioInit() void;
extern fn wioUpdate() void;
extern fn wioWait(f64) void;
extern fn wioCancelWait() void;
extern fn wioMessageBox(u8, [*]const u8, usize) void;
extern fn wioOpenUri([*]const u8, usize) void;
extern fn wioCreateWindow(*Window, u16, u16) *NSWindow;
extern fn wioDestroyWindow(*NSWindow) void;
extern fn wioEnableTextInput(*NSWindow, i16, i16) void;
extern fn wioDisableTextInput(*NSWindow) void;
extern fn wioEnableRelativeMouse(*NSWindow) void;
extern fn wioDisableRelativeMouse(*NSWindow) void;
extern fn wioSetTitle(*NSWindow, [*]const u8, usize) void;
extern fn wioSetMode(*NSWindow, u8) void;
extern fn wioSetPosition(*NSWindow, i16, i16) void;
extern fn wioSetSize(*NSWindow, u16, u16) void;
extern fn wioSetCursor(*NSWindow, u8) void;
extern fn wioMinimize(*NSWindow) void;
extern fn wioRequestAttention() void;
extern fn wioSetClipboardText([*]const u8, usize) void;
extern fn wioGetClipboardText(*usize) ?[*]u8;
extern fn wioDrawAvailable(*NSWindow) void;
extern fn wioPresentFramebuffer(*NSWindow, c.CGContextRef) void;
extern fn wioRelease(?*const anyopaque) void;
extern fn wioGlChoosePixelFormat([*]const c.CGLPixelFormatAttribute) ?*NSOpenGLPixelFormat;
extern fn wioGlCreateContext(?*NSOpenGLPixelFormat, ?*NSOpenGLContext) ?*NSOpenGLContext;
extern fn wioGlMakeContextCurrent(*NSWindow, ?*NSOpenGLContext) void;
extern fn wioGlSwapBuffers() void;
extern fn wioGlSwapInterval(i32) void;
extern fn wioGlReleaseCurrentContext() void;
extern fn wioCreateMetalLayer(*NSWindow) ?*CAMetalLayer;
extern const wioHIDDeviceUsagePageKey: c.CFStringRef;
extern const wioHIDDeviceUsageKey: c.CFStringRef;
extern const wioHIDVendorIDKey: c.CFStringRef;
extern const wioHIDProductIDKey: c.CFStringRef;
extern const wioHIDVersionNumberKey: c.CFStringRef;
extern const wioHIDSerialNumberKey: c.CFStringRef;
extern const wioHIDProductKey: c.CFStringRef;

var libvulkan: std.DynLib = undefined;

var hid: c.IOHIDManagerRef = undefined;
var removed_joysticks: std.AutoHashMapUnmanaged(c.IOHIDDeviceRef, bool) = undefined;

pub fn init(options: wio.InitOptions) !void {
    wioInit();

    if (build_options.vulkan) {
        libvulkan = blk: {
            if (c.CFBundleGetMainBundle()) |bundle| {
                if (c.CFBundleCopyPrivateFrameworksURL(bundle)) |url| {
                    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
                    if (c.CFURLGetFileSystemRepresentation(url, 1, &buf, buf.len) == 1) {
                        _ = try std.fmt.bufPrintSentinel(buf[std.mem.findScalar(u8, &buf, 0).?..], "/libvulkan.1.dylib", .{}, 0);
                        if (std.DynLib.openZ(&buf)) |lib| {
                            break :blk lib;
                        } else |err| switch (err) {
                            error.FileNotFound => {},
                            else => return err,
                        }
                    }
                }
            }
            break :blk try std.DynLib.openZ("libvulkan.1.dylib");
        };
        vkGetInstanceProcAddr = libvulkan.lookup(@TypeOf(vkGetInstanceProcAddr), "vkGetInstanceProcAddr") orelse return error.Unexpected;
    }

    if (build_options.joystick) {
        hid = c.IOHIDManagerCreate(c.kCFAllocatorDefault, c.kIOHIDOptionsTypeNone);
        errdefer c.CFRelease(hid);

        const joystick = try usageDictionary(c.kHIDPage_GenericDesktop, c.kHIDUsage_GD_Joystick);
        defer c.CFRelease(joystick);
        const gamepad = try usageDictionary(c.kHIDPage_GenericDesktop, c.kHIDUsage_GD_GamePad);
        defer c.CFRelease(gamepad);
        const matching = c.CFArrayCreate(
            c.kCFAllocatorDefault,
            @constCast(&[_]c.CFTypeRef{ joystick, gamepad }),
            2,
            &c.kCFTypeArrayCallBacks,
        );
        defer c.CFRelease(matching);
        c.IOHIDManagerSetDeviceMatchingMultiple(hid, matching);

        removed_joysticks = .empty;
        c.IOHIDManagerRegisterDeviceRemovalCallback(hid, joystickRemoved, null);
        if (options.joystickConnectedFn) |callback| {
            c.IOHIDManagerRegisterDeviceMatchingCallback(hid, joystickConnected, @constCast(callback));
        }

        c.IOHIDManagerScheduleWithRunLoop(hid, c.CFRunLoopGetMain(), c.kCFRunLoopDefaultMode);
        try succeed(c.IOHIDManagerOpen(hid, c.kIOHIDOptionsTypeNone), "IOHIDManagerOpen");
    }
    errdefer if (build_options.joystick) c.CFRelease(hid);

    if (build_options.audio) {
        if (options.audioDefaultOutputFn) |callback| {
            const address: c.AudioObjectPropertyAddress = .{
                .mSelector = c.kAudioHardwarePropertyDefaultOutputDevice,
                .mScope = c.kAudioObjectPropertyScopeGlobal,
                .mElement = c.kAudioObjectPropertyElementMain,
            };
            var id: c.AudioObjectID = undefined;
            var size: u32 = @sizeOf(c.AudioObjectID);
            try succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultOutputDevice)");
            if (id != 0) {
                callback(.{ .backend = .{ .id = id } });
            }
            try succeed(c.AudioObjectAddPropertyListener(c.kAudioObjectSystemObject, &address, defaultAudioOutputChanged, @constCast(callback)), "AddPropertyListener");
        }
        if (options.audioDefaultInputFn) |callback| {
            const address: c.AudioObjectPropertyAddress = .{
                .mSelector = c.kAudioHardwarePropertyDefaultInputDevice,
                .mScope = c.kAudioObjectPropertyScopeGlobal,
                .mElement = c.kAudioObjectPropertyElementMain,
            };
            var id: c.AudioObjectID = undefined;
            var size: u32 = @sizeOf(c.AudioObjectID);
            try succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultInputDevice)");
            if (id != 0) {
                callback(.{ .backend = .{ .id = id } });
            }
            try succeed(c.AudioObjectAddPropertyListener(c.kAudioObjectSystemObject, &address, defaultAudioInputChanged, @constCast(callback)), "AddPropertyListener");
        }
    }
}

pub fn deinit() void {
    if (build_options.joystick) {
        removed_joysticks.deinit(internal.allocator);
        c.CFRelease(hid);
    }
    if (build_options.vulkan) {
        libvulkan.close();
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        update();
    }
}

pub fn update() void {
    wioUpdate();
}

pub fn wait(options: wio.WaitOptions) void {
    internal.wait = true;
    if (options.timeout_ns) |timeout_ns| {
        var timeout = @as(f64, @floatFromInt(timeout_ns)) / std.time.ns_per_s;
        while (internal.wait and timeout > 0) {
            const start = std.Io.Clock.awake.now(internal.io).nanoseconds;
            wioWait(timeout);
            const end = std.Io.Clock.awake.now(internal.io).nanoseconds;
            timeout -= @as(f64, @floatFromInt(end - start)) / std.time.ns_per_s;
        }
    } else {
        while (internal.wait) {
            wioWait(-1);
        }
    }
}

pub fn cancelWait() void {
    internal.wait = false;
    wioCancelWait();
}

pub fn messageBox(style: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    wioMessageBox(@backingInt(style), message.ptr, message.len);
}

pub fn openUri(uri: []const u8) void {
    wioOpenUri(uri.ptr, uri.len);
}

pub const Window = struct {
    event_fn_data: ?*anyopaque,
    window: *NSWindow,
    draw_available_ns: u32 = 0,
    draw_available_thread: std.Thread = undefined,
    opengl: if (build_options.opengl) struct {
        format: ?*NSOpenGLPixelFormat = null,
    } else struct {} = .{},

    pub fn create(options: wio.CreateWindowOptions) !*Window {
        const self = try internal.allocator.create(Window);
        errdefer internal.allocator.destroy(self);

        self.* = .{
            .event_fn_data = options.event_fn_data,
            .window = undefined,
        };
        self.window = wioCreateWindow(self, options.size.width, options.size.height);

        self.setTitle(options.title);
        self.setMode(options.mode);
        if (options.position) |position| self.setPosition(position);

        if (build_options.opengl) {
            if (options.gl_options) |gl| {
                const profile: c.CGLPixelFormatAttribute = if (gl.major_version <= 2)
                    c.kCGLOGLPVersion_Legacy
                else if (gl.major_version == 3 and (gl.minor_version == 2 or gl.minor_version == 3) and gl.profile == .core)
                    c.kCGLOGLPVersion_GL3_Core
                else if (gl.major_version == 4 and gl.minor_version <= 1 and gl.profile == .core)
                    c.kCGLOGLPVersion_GL4_Core
                else
                    return error.UnsupportedContextOptions;

                self.opengl.format = wioGlChoosePixelFormat(&.{
                    c.kCGLPFAOpenGLProfile, profile,
                    c.kCGLPFAColorSize,     gl.red_bits + gl.green_bits + gl.blue_bits,
                    c.kCGLPFAAlphaSize,     gl.alpha_bits,
                    c.kCGLPFADepthSize,     gl.depth_bits,
                    c.kCGLPFAStencilSize,   gl.stencil_bits,
                    c.kCGLPFASampleBuffers, if (gl.samples == 0) 0 else 1,
                    c.kCGLPFASamples,       gl.samples,
                    if (gl.doublebuffer)
                        c.kCGLPFADoubleBuffer
                    else
                        0,
                    0,
                });
            }
        }

        return self;
    }

    pub fn destroy(self: *Window) void {
        self.disableDrawAvailableEvents();
        if (build_options.opengl) wioRelease(self.opengl.format);
        wioDestroyWindow(self.window);
        internal.allocator.destroy(self);
    }

    pub fn enableTextInput(self: *Window, options: wio.TextInputOptions) void {
        wioEnableTextInput(
            self.window,
            if (options.cursor) |cursor| cursor.x else 0,
            if (options.cursor) |cursor| cursor.y else 0,
        );
    }

    pub fn disableTextInput(self: *Window) void {
        wioDisableTextInput(self.window);
    }

    pub fn enableRelativeMouse(self: *Window, _: wio.RelativeMouseOptions) void {
        wioEnableRelativeMouse(self.window);
    }

    pub fn disableRelativeMouse(self: *Window) void {
        wioDisableRelativeMouse(self.window);
    }

    pub fn enableDrawAvailableEvents(self: *Window) void {
        if (self.draw_available_ns == 0) {
            log.warn("enableDrawAvailableEvents unimplemented for macos, falling back to 60 Hz", .{});
            self.draw_available_ns = std.time.ns_per_s / 60;
            self.draw_available_thread = std.Thread.spawn(.{}, drawAvailableThread, .{self}) catch {
                self.draw_available_ns = 0;
                return;
            };
        }
    }

    pub fn disableDrawAvailableEvents(self: *Window) void {
        if (self.draw_available_ns != 0) {
            self.draw_available_ns = 0;
            self.draw_available_thread.join();
        }
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        wioSetTitle(self.window, title.ptr, title.len);
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        wioSetMode(self.window, @backingInt(mode));
    }

    pub fn setPosition(self: *Window, position: wio.Position) void {
        wioSetPosition(self.window, position.x, position.y);
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        wioSetSize(self.window, size.width, size.height);
    }

    pub fn setParent(self: *Window, parent: usize) void {
        _ = self;
        _ = parent;
    }

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        wioSetCursor(self.window, @backingInt(shape));
    }

    pub fn minimize(self: *Window) void {
        wioMinimize(self.window);
    }

    pub fn requestAttention(_: *Window) void {
        wioRequestAttention();
    }

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        wioSetClipboardText(text.ptr, text.len);
    }

    pub fn getClipboardText(_: *Window, clipboardTextFn: *const fn (?*anyopaque, []const u8) void, clipboard_text_fn_data: ?*anyopaque) void {
        var len: usize = undefined;
        if (wioGetClipboardText(&len)) |ptr| {
            const text = ptr[0..len];
            defer internal.allocator.free(text);
            clipboardTextFn(clipboard_text_fn_data, text);
        }
    }

    pub fn getDropData(_: *Window, _: std.mem.Allocator) wio.DropData {
        return .{ .files = &.{}, .text = null };
    }

    pub fn createFramebuffer(_: *Window, size: wio.Size) !Framebuffer {
        const pixels = try internal.allocator.alloc(u32, @as(usize, size.width) * size.height);
        errdefer internal.allocator.free(pixels);

        const colorspace = c.CGColorSpaceCreateDeviceRGB() orelse return error.Unexpected;
        defer c.CGColorSpaceRelease(colorspace);

        const byte_order: u32 = if (@import("builtin").cpu.arch.endian() == .little) c.kCGImageByteOrder32Little else c.kCGImageByteOrder32Big;

        const bitmap = c.CGBitmapContextCreate(
            pixels.ptr,
            size.width,
            size.height,
            8,
            size.width * @sizeOf(u32),
            colorspace,
            byte_order | c.kCGImageAlphaNoneSkipFirst,
        ) orelse return error.Unexpected;

        return .{
            .pixels = pixels,
            .bitmap = bitmap,
            .width = size.width,
        };
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        wioPresentFramebuffer(self.window, framebuffer.bitmap);
    }

    pub fn glCreateContext(self: *Window, options: wio.GlCreateContextOptions) !GlContext {
        return .{
            .context = wioGlCreateContext(
                self.opengl.format,
                if (options.share) |share| share.backend.context else null,
            ),
        };
    }

    pub fn glMakeContextCurrent(self: *Window, context: GlContext) void {
        wioGlMakeContextCurrent(self.window, context.context);
    }

    pub fn glSwapBuffers(_: *Window) void {
        wioGlSwapBuffers();
    }

    pub fn glSwapInterval(_: *Window, interval: i32) void {
        wioGlSwapInterval(interval);
    }

    pub fn vkCreateSurface(self: Window, instance: usize, allocation_callbacks: ?*const anyopaque, surface: *u64) i32 {
        const VkMetalSurfaceCreateInfoEXT = extern struct {
            sType: i32 = 1000217000,
            pNext: ?*const anyopaque = null,
            flags: u32 = 0,
            pLayer: ?*const CAMetalLayer,
        };

        const vkCreateMetalSurfaceEXT: *const fn (usize, *const VkMetalSurfaceCreateInfoEXT, ?*const anyopaque, *u64) callconv(.c) i32 =
            @ptrCast(vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT"));

        return vkCreateMetalSurfaceEXT(
            instance,
            &.{ .pLayer = wioCreateMetalLayer(self.window) },
            allocation_callbacks,
            surface,
        );
    }
};

pub const Framebuffer = struct {
    pixels: []u32,
    bitmap: c.CGContextRef,
    width: u16,

    pub fn destroy(self: *Framebuffer) void {
        c.CGContextRelease(self.bitmap);
        internal.allocator.free(self.pixels);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        self.pixels[y * self.width + x] = rgb;
    }
};

pub const GlContext = struct {
    context: ?*NSOpenGLContext,

    pub fn destroy(self: GlContext) void {
        wioRelease(self.context);
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return c.dlsym(c.RTLD_DEFAULT, name);
}

pub fn glReleaseCurrentContext() void {
    wioGlReleaseCurrentContext();
}

pub var vkGetInstanceProcAddr: *const fn (usize, [*:0]const u8) callconv(.c) ?*const fn () void = undefined;

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_EXT_metal_surface" };
}

pub const JoystickDeviceIterator = struct {
    devices: []c.IOHIDDeviceRef = &.{},
    index: usize = 0,

    pub fn init() JoystickDeviceIterator {
        const set = c.IOHIDManagerCopyDevices(hid) orelse return .{};
        defer c.CFRelease(set);
        const len: usize = @intCast(c.CFSetGetCount(set));
        const devices = internal.allocator.alloc(c.IOHIDDeviceRef, len) catch return .{};
        c.CFSetGetValues(set, @ptrCast(devices.ptr));
        return .{ .devices = devices };
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        internal.allocator.free(self.devices);
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.index == self.devices.len) return null;
        defer self.index += 1;
        return .{ .device = self.devices[self.index] };
    }
};

pub const JoystickDevice = struct {
    device: c.IOHIDDeviceRef,

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !Joystick {
        const elements = c.IOHIDDeviceCopyMatchingElements(self.device, null, c.kIOHIDOptionsTypeNone) orelse return error.Unexpected;
        defer c.CFRelease(elements);

        var axis_elements: std.ArrayList(c.IOHIDElementRef) = .empty;
        errdefer axis_elements.deinit(internal.allocator);
        var hat_elements: std.ArrayList(c.IOHIDElementRef) = .empty;
        errdefer hat_elements.deinit(internal.allocator);
        var button_elements: std.ArrayList(c.IOHIDElementRef) = .empty;
        errdefer button_elements.deinit(internal.allocator);

        const count = c.CFArrayGetCount(elements);
        var i: c.CFIndex = 0;
        while (i < count) : (i += 1) {
            const element: c.IOHIDElementRef = @ptrCast(@constCast(c.CFArrayGetValueAtIndex(elements, i)));
            if (c.IOHIDElementGetType(element) == c.kIOHIDElementTypeInput_Button) {
                try button_elements.append(internal.allocator, element);
            } else {
                const page = c.IOHIDElementGetUsagePage(element);
                const usage = c.IOHIDElementGetUsage(element);
                switch (page) {
                    c.kHIDPage_GenericDesktop => {
                        switch (usage) {
                            c.kHIDUsage_GD_Hatswitch => try hat_elements.append(internal.allocator, element),
                            c.kHIDUsage_GD_X,
                            c.kHIDUsage_GD_Y,
                            c.kHIDUsage_GD_Z,
                            c.kHIDUsage_GD_Rx,
                            c.kHIDUsage_GD_Ry,
                            c.kHIDUsage_GD_Rz,
                            c.kHIDUsage_GD_Slider,
                            c.kHIDUsage_GD_Dial,
                            c.kHIDUsage_GD_Wheel,
                            => try axis_elements.append(internal.allocator, element),
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }

        const axes = try internal.allocator.alloc(u16, axis_elements.items.len);
        errdefer internal.allocator.free(axes);
        const hats = try internal.allocator.alloc(wio.Hat, hat_elements.items.len);
        errdefer internal.allocator.free(hats);
        const buttons = try internal.allocator.alloc(bool, button_elements.items.len);
        errdefer internal.allocator.free(buttons);

        const axis_elements_slice = try axis_elements.toOwnedSlice(internal.allocator);
        errdefer internal.allocator.free(axis_elements_slice);
        const hat_elements_slice = try hat_elements.toOwnedSlice(internal.allocator);
        errdefer internal.allocator.free(hat_elements_slice);
        const button_elements_slice = try button_elements.toOwnedSlice(internal.allocator);
        errdefer internal.allocator.free(button_elements_slice);

        try removed_joysticks.put(internal.allocator, self.device, false);

        return .{
            .device = self.device,
            .axis_elements = axis_elements_slice,
            .hat_elements = hat_elements_slice,
            .button_elements = button_elements_slice,
            .axes = axes,
            .hats = hats,
            .buttons = buttons,
        };
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        const vendor_cf = c.IOHIDDeviceGetProperty(self.device, wioHIDVendorIDKey) orelse return error.Unexpected;
        const product_cf = c.IOHIDDeviceGetProperty(self.device, wioHIDProductIDKey) orelse return error.Unexpected;
        const version_cf = c.IOHIDDeviceGetProperty(self.device, wioHIDVersionNumberKey) orelse return error.Unexpected;
        const serial_cf = c.IOHIDDeviceGetProperty(self.device, wioHIDSerialNumberKey);
        var vendor: u32 = undefined;
        _ = c.CFNumberGetValue(@ptrCast(vendor_cf), c.kCFNumberSInt32Type, &vendor);
        var product: u32 = undefined;
        _ = c.CFNumberGetValue(@ptrCast(product_cf), c.kCFNumberSInt32Type, &product);
        var version: u32 = undefined;
        _ = c.CFNumberGetValue(@ptrCast(version_cf), c.kCFNumberSInt32Type, &version);
        const serial = if (serial_cf) |_| try cfStringToUtf8(allocator, @ptrCast(serial_cf)) else "";
        defer allocator.free(serial);
        return std.fmt.allocPrint(allocator, "{x:0>4}{x:0>4}{x:0>4}{s}", .{ vendor, product, version, serial });
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        return cfStringToUtf8(allocator, @ptrCast(c.IOHIDDeviceGetProperty(self.device, wioHIDProductKey)));
    }
};

pub const Joystick = struct {
    device: c.IOHIDDeviceRef,
    axis_elements: []c.IOHIDElementRef,
    hat_elements: []c.IOHIDElementRef,
    button_elements: []c.IOHIDElementRef,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        _ = removed_joysticks.remove(self.device);
        internal.allocator.free(self.buttons);
        internal.allocator.free(self.hats);
        internal.allocator.free(self.axes);
        internal.allocator.free(self.button_elements);
        internal.allocator.free(self.hat_elements);
        internal.allocator.free(self.axis_elements);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        if (removed_joysticks.get(self.device).?) return null;
        var value: c.IOHIDValueRef = undefined;
        for (self.axis_elements, self.axes) |element, *axis| {
            const min = c.IOHIDElementGetLogicalMin(element);
            const max = c.IOHIDElementGetLogicalMax(element);
            _ = c.IOHIDDeviceGetValue(self.device, element, &value);
            var float: f32 = @floatFromInt(c.IOHIDValueGetIntegerValue(value));
            float -= @floatFromInt(min);
            float /= @floatFromInt(max - min);
            float *= 0xFFFF;
            axis.* = @trunc(float);
        }
        for (self.hat_elements, self.hats) |element, *hat| {
            _ = c.IOHIDDeviceGetValue(self.device, element, &value);
            hat.* = switch (c.IOHIDValueGetIntegerValue(value)) {
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
        }
        for (self.button_elements, self.buttons) |element, *button| {
            _ = c.IOHIDDeviceGetValue(self.device, element, &value);
            button.* = if (c.IOHIDValueGetIntegerValue(value) == 0) false else true;
        }
        return .{ .axes = self.axes, .hats = self.hats, .buttons = self.buttons };
    }
};

pub const AudioDeviceIterator = struct {
    devices: []c.AudioObjectID = &.{},
    index: usize = 0,
    mode: wio.AudioDeviceType = undefined,

    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        const address: c.AudioObjectPropertyAddress = .{
            .mSelector = c.kAudioHardwarePropertyDevices,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        };
        var size: u32 = undefined;
        succeed(c.AudioObjectGetPropertyDataSize(c.kAudioObjectSystemObject, &address, 0, null, &size), "GetPropertySize(Devices)") catch return .{};
        const devices = internal.allocator.alloc(c.AudioObjectID, size / @sizeOf(c.AudioObjectID)) catch return .{};
        succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, devices.ptr), "GetProperty(Devices)") catch {
            internal.allocator.free(devices);
            return .{};
        };
        return .{ .devices = devices, .mode = mode };
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        internal.allocator.free(self.devices);
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.index == self.devices.len) return null;

        const id = self.devices[self.index];
        self.index += 1;

        var size: u32 = undefined;
        _ = c.AudioObjectGetPropertyDataSize(id, &.{
            .mSelector = c.kAudioDevicePropertyStreams,
            .mScope = if (self.mode == .output) c.kAudioDevicePropertyScopeOutput else c.kAudioDevicePropertyScopeInput,
            .mElement = c.kAudioObjectPropertyElementMain,
        }, 0, null, &size);
        if (size == 0) return self.next();

        return .{ .id = id };
    }
};

pub const AudioDevice = struct {
    id: c.AudioObjectID,

    pub fn release(_: AudioDevice) void {}

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        const component = c.AudioComponentFindNext(null, &.{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        });
        var unit: c.AudioComponentInstance = undefined;
        try succeed(c.AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew");
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_CurrentDevice, c.kAudioUnitScope_Global, 0, &self.id, @sizeOf(c.AudioDeviceID)), "SetProperty(CurrentDevice)");

        const stream_desc: c.AudioStreamBasicDescription = .{
            .mSampleRate = @floatFromInt(format.sample_rate),
            .mFormatID = c.kAudioFormatLinearPCM,
            .mFormatFlags = c.kAudioFormatFlagIsFloat,
            .mBytesPerPacket = @sizeOf(f32) * format.channels,
            .mFramesPerPacket = 1,
            .mBytesPerFrame = @sizeOf(f32) * format.channels,
            .mChannelsPerFrame = format.channels,
            .mBitsPerChannel = @bitSizeOf(f32),
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioUnitProperty_StreamFormat, c.kAudioUnitScope_Input, 0, &stream_desc, @sizeOf(c.AudioStreamBasicDescription)), "SetProperty(StreamFormat)");

        const callback: c.AURenderCallbackStruct = .{
            .inputProc = AudioOutput.callback,
            .inputProcRefCon = @constCast(writeFn),
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioUnitProperty_SetRenderCallback, c.kAudioUnitScope_Global, 0, &callback, @sizeOf(c.AURenderCallbackStruct)), "SetProperty(RenderCallback)");
        try succeed(c.AudioUnitInitialize(unit), "AudioUnitInitialize");
        try succeed(c.AudioOutputUnitStart(unit), "AudioOutputUnitStart");
        return .{ .unit = unit };
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !*AudioInput {
        const component = c.AudioComponentFindNext(null, &.{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        });
        var unit: c.AudioComponentInstance = undefined;
        try succeed(c.AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew");

        var enable_io: u32 = 1;
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_EnableIO, c.kAudioUnitScope_Input, 1, &enable_io, @sizeOf(u32)), "SetProperty(EnableIO)");
        enable_io = 0;
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_EnableIO, c.kAudioUnitScope_Output, 0, &enable_io, @sizeOf(u32)), "SetProperty(EnableIO)");
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_CurrentDevice, c.kAudioUnitScope_Global, 0, &self.id, @sizeOf(c.AudioDeviceID)), "SetProperty(CurrentDevice)");

        var native_sample_rate: f32 = undefined;
        var size: u32 = undefined;
        try succeed(c.AudioUnitGetProperty(unit, c.kAudioUnitProperty_SampleRate, c.kAudioUnitScope_Output, 1, &native_sample_rate, &size), "GetProperty(SampleRate)");
        const source_format: c.AudioStreamBasicDescription = .{
            .mSampleRate = native_sample_rate,
            .mFormatID = c.kAudioFormatLinearPCM,
            .mFormatFlags = c.kAudioFormatFlagIsFloat,
            .mBytesPerPacket = @sizeOf(f32) * format.channels,
            .mFramesPerPacket = 1,
            .mBytesPerFrame = @sizeOf(f32) * format.channels,
            .mChannelsPerFrame = format.channels,
            .mBitsPerChannel = @bitSizeOf(f32),
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioUnitProperty_StreamFormat, c.kAudioUnitScope_Output, 1, &source_format, @sizeOf(c.AudioStreamBasicDescription)), "SetProperty(StreamFormat)");
        var dest_format = source_format;
        dest_format.mSampleRate = @floatFromInt(format.sample_rate);
        var converter: c.AudioConverterRef = undefined;
        try succeed(c.AudioConverterNew(&source_format, &dest_format, &converter), "AudioConverterNew");

        const input = try internal.allocator.create(AudioInput);
        errdefer internal.allocator.destroy(input);
        input.* = .{
            .unit = unit,
            .converter = converter,
            .readFn = readFn,
        };
        const callback: c.AURenderCallbackStruct = .{
            .inputProc = AudioInput.callback,
            .inputProcRefCon = input,
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_SetInputCallback, c.kAudioUnitScope_Global, 0, &callback, @sizeOf(c.AURenderCallbackStruct)), "SetProperty(InputCallback)");
        try succeed(c.AudioUnitInitialize(unit), "AudioUnitInitialize");
        try succeed(c.AudioOutputUnitStart(unit), "AudioOutputUnitStart");
        return input;
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        var string: c.CFStringRef = undefined;
        var size: u32 = @sizeOf(c.CFStringRef);
        try succeed(c.AudioObjectGetPropertyData(self.id, &.{
            .mSelector = c.kAudioDevicePropertyDeviceUID,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        }, 0, null, &size, @ptrCast(&string)), "GetProperty(DeviceUID)");
        defer c.CFRelease(string);
        return cfStringToUtf8(allocator, string);
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        var string: c.CFStringRef = undefined;
        var size: u32 = @sizeOf(c.CFStringRef);
        try succeed(c.AudioObjectGetPropertyData(self.id, &.{
            .mSelector = c.kAudioObjectPropertyName,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        }, 0, null, &size, @ptrCast(&string)), "GetProperty(Name)");
        defer c.CFRelease(string);
        return cfStringToUtf8(allocator, string);
    }
};

pub const AudioOutput = struct {
    unit: c.AudioUnit,

    pub fn close(self: *AudioOutput) void {
        _ = c.AudioUnitUninitialize(self.unit);
    }

    fn callback(data: ?*anyopaque, _: [*c]c.AudioUnitRenderActionFlags, _: [*c]const c.AudioTimeStamp, _: u32, _: u32, list: [*c]c.AudioBufferList) callconv(.c) c.OSStatus {
        const writeFn: *const fn ([]f32) void = @ptrCast(@alignCast(data));
        const buffer = list.*.mBuffers[0];
        const ptr: [*]f32 = @ptrCast(@alignCast(buffer.mData));
        writeFn(ptr[0 .. buffer.mDataByteSize / @sizeOf(f32)]);
        return c.noErr;
    }
};

pub const AudioInput = struct {
    unit: c.AudioUnit,
    converter: c.AudioConverterRef,
    readFn: *const fn ([]const f32) void,
    buffer: [1024]f32 = undefined,

    pub fn close(self: *AudioInput) void {
        _ = c.AudioConverterDispose(self.converter);
        _ = c.AudioUnitUninitialize(self.unit);
        internal.allocator.destroy(self);
    }

    fn callback(data: ?*anyopaque, flags: [*c]c.AudioUnitRenderActionFlags, timestamp: [*c]const c.AudioTimeStamp, bus: u32, frames: u32, _: [*c]c.AudioBufferList) callconv(.c) c.OSStatus {
        const self: *AudioInput = @ptrCast(@alignCast(data));

        var list: c.AudioBufferList = .{
            .mNumberBuffers = 1,
            .mBuffers = .{.{
                .mNumberChannels = 0,
                .mDataByteSize = 0,
                .mData = null,
            }},
        };
        succeed(c.AudioUnitRender(self.unit, flags, timestamp, bus, frames, &list), "AudioUnitRender") catch return c.noErr;

        var remaining = frames;
        while (remaining > 0) {
            var output: c.AudioBufferList = .{
                .mNumberBuffers = 1,
                .mBuffers = .{.{
                    .mNumberChannels = list.mBuffers[0].mNumberChannels,
                    .mDataByteSize = self.buffer.len * @sizeOf(f32),
                    .mData = &self.buffer,
                }},
            };
            var packets = remaining;
            succeed(c.AudioConverterFillComplexBuffer(self.converter, inputProc, &list.mBuffers[0], &packets, &output, null), "AudioConverterFillComplexBuffer") catch return c.noErr;
            self.readFn(self.buffer[0 .. packets * list.mBuffers[0].mNumberChannels]);
            remaining -= packets;
            list.mBuffers[0].mData = @ptrFromInt(@intFromPtr(list.mBuffers[0].mData) + output.mBuffers[0].mDataByteSize);
            list.mBuffers[0].mDataByteSize -= output.mBuffers[0].mDataByteSize;
        }

        return c.noErr;
    }

    fn inputProc(_: c.AudioConverterRef, packets: [*c]u32, list: [*c]c.AudioBufferList, _: [*c][*c]c.AudioStreamPacketDescription, data: ?*anyopaque) callconv(.c) c.OSStatus {
        const buffer: *c.AudioBuffer = @ptrCast(@alignCast(data));
        list.*.mBuffers[0] = buffer.*;
        packets.* = buffer.mDataByteSize / buffer.mNumberChannels / @sizeOf(f32);
        return c.noErr;
    }
};

export fn wioClose(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .close);
}

export fn wioFocused(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .focused);
}

export fn wioUnfocused(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .unfocused);
}

export fn wioVisible(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .visible);
}

export fn wioHidden(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .hidden);
}

export fn wioDraw(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .draw);
}

export fn wioPosition(self: *Window, x: i16, y: i16) void {
    internal.sendEvent(self.event_fn_data, .{ .position = .{ .x = x, .y = y } });
}

export fn wioSizeLogical(self: *Window, mode: u8, width: u16, height: u16) void {
    internal.sendEvent(self.event_fn_data, .{ .mode = @fromBackingInt(@intCast(mode)) });
    internal.sendEvent(self.event_fn_data, .{ .size_logical = .{ .width = width, .height = height } });
}

export fn wioSizePhysical(self: *Window, width: u16, height: u16) void {
    internal.sendEvent(self.event_fn_data, .{ .size_physical = .{ .width = width, .height = height } });
    internal.sendEvent(self.event_fn_data, .draw);
}

export fn wioScale(self: *Window, scale: f32) void {
    internal.sendEvent(self.event_fn_data, .{ .scale = scale });
}

export fn wioModifiers(self: *Window, modifiers: u32) void {
    internal.sendEvent(self.event_fn_data, .{
        .modifiers = .{
            .control = (modifiers & (1 << 18) != 0),
            .shift = (modifiers & (1 << 17) != 0),
            .alt = (modifiers & (1 << 19) != 0),
            .gui = (modifiers & (1 << 20) != 0),
        },
    });
}

export fn wioChars(self: *Window, buf: [*:0]const u8) void {
    const view = std.unicode.Utf8View.init(std.mem.sliceTo(buf, 0)) catch return;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |char| {
        internal.sendEvent(self.event_fn_data, .{ .char = char });
    }
}

export fn wioPreviewChars(self: *Window, buf: [*:0]const u8, cursor_start: u16, cursor_length: u16) void {
    const view = std.unicode.Utf8View.init(std.mem.sliceTo(buf, 0)) catch return;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |char| {
        internal.sendEvent(self.event_fn_data, .{ .preview_char = char });
    }
    internal.sendEvent(self.event_fn_data, .{ .preview_cursor = .{ cursor_start, cursor_start + cursor_length } });
}

export fn wioPreviewReset(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .preview_reset);
}

export fn wioKey(self: *Window, key: u16, event: u8) void {
    if (keycodeToButton(key)) |button| {
        switch (event) {
            0 => internal.sendEvent(self.event_fn_data, .{ .button_press = button }),
            1 => internal.sendEvent(self.event_fn_data, .{ .button_repeat = button }),
            2 => internal.sendEvent(self.event_fn_data, .{ .button_release = button }),
            else => unreachable,
        }
    }
}

export fn wioButtonPress(self: *Window, button: u8) void {
    internal.sendEvent(self.event_fn_data, .{ .button_press = @fromBackingInt(@intCast(button)) });
}

export fn wioButtonRelease(self: *Window, button: u8) void {
    internal.sendEvent(self.event_fn_data, .{ .button_release = @fromBackingInt(@intCast(button)) });
}

export fn wioMouse(self: *Window, x: i16, y: i16) void {
    internal.sendEvent(self.event_fn_data, .{ .mouse = .{ .x = x, .y = y } });
}

export fn wioMouseRelative(self: *Window, x: i16, y: i16) void {
    internal.sendEvent(self.event_fn_data, .{ .mouse_relative = .{ .x = x, .y = y } });
}

export fn wioMouseLeave(self: *Window) void {
    internal.sendEvent(self.event_fn_data, .mouse_leave);
}

export fn wioScroll(self: *Window, x: f32, y: f32) void {
    if (x != 0) internal.sendEvent(self.event_fn_data, .{ .scroll_horizontal = -x });
    if (y != 0) internal.sendEvent(self.event_fn_data, .{ .scroll_vertical = -y });
}

export fn wioGestureZoom(self: *Window, value: f32) void {
    internal.sendEvent(self.event_fn_data, .{ .gesture_zoom = value + 1 });
}

export fn wioGestureRotate(self: *Window, value: f32) void {
    internal.sendEvent(self.event_fn_data, .{ .gesture_rotate = -value });
}

export fn wioDupeClipboardText(bytes: [*:0]const u8, len: *usize) ?[*]u8 {
    const slice = std.mem.sliceTo(bytes, 0);
    if (internal.allocator.dupe(u8, slice)) |dupe| {
        len.* = dupe.len;
        return dupe.ptr;
    } else |_| {
        return null;
    }
}

fn drawAvailableThread(window: *Window) void {
    while (window.draw_available_ns > 0) {
        wioDrawAvailable(window.window);
        std.Io.sleep(internal.io, .{ .nanoseconds = window.draw_available_ns }, .awake) catch {};
    }
}

fn usageDictionary(page: i32, usage: i32) !c.CFDictionaryRef {
    const page_cf = c.CFNumberCreate(c.kCFAllocatorDefault, c.kCFNumberSInt32Type, &page) orelse return error.Unexpected;
    defer c.CFRelease(page_cf);
    const usage_cf = c.CFNumberCreate(c.kCFAllocatorDefault, c.kCFNumberSInt32Type, &usage) orelse return error.Unexpected;
    defer c.CFRelease(usage_cf);
    return c.CFDictionaryCreate(
        c.kCFAllocatorDefault,
        @constCast(&[_]c.CFTypeRef{ wioHIDDeviceUsagePageKey, wioHIDDeviceUsageKey }),
        @constCast(&[_]c.CFTypeRef{ page_cf, usage_cf }),
        2,
        &c.kCFTypeDictionaryKeyCallBacks,
        &c.kCFTypeDictionaryValueCallBacks,
    ) orelse error.Unexpected;
}

fn joystickConnected(data: ?*anyopaque, _: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    const callback: *const fn (wio.JoystickDevice) void = @ptrCast(@alignCast(data));
    callback(.{ .backend = .{ .device = device } });
}

fn joystickRemoved(_: ?*anyopaque, _: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    if (removed_joysticks.getPtr(device)) |removed| removed.* = true;
}

fn defaultAudioOutputChanged(_: c.AudioObjectID, _: u32, _: [*c]const c.AudioObjectPropertyAddress, data: ?*anyopaque) callconv(.c) c.OSStatus {
    var id: c.AudioObjectID = undefined;
    var size: u32 = @sizeOf(c.AudioObjectID);
    succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &.{
        .mSelector = c.kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    }, 0, null, &size, &id), "GetProperty(DefaultOutputDevice)") catch return c.noErr;

    const callback: *const fn (wio.AudioDevice) void = @ptrCast(@alignCast(data));
    callback(.{ .backend = .{ .id = id } });
    return c.noErr;
}

fn defaultAudioInputChanged(_: c.AudioObjectID, _: u32, _: [*c]const c.AudioObjectPropertyAddress, data: ?*anyopaque) callconv(.c) c.OSStatus {
    var id: c.AudioObjectID = undefined;
    var size: u32 = @sizeOf(c.AudioObjectID);
    succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &.{
        .mSelector = c.kAudioHardwarePropertyDefaultInputDevice,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    }, 0, null, &size, &id), "GetProperty(DefaultInputDevice)") catch return c.noErr;

    const callback: *const fn (wio.AudioDevice) void = @ptrCast(@alignCast(data));
    callback(.{ .backend = .{ .id = id } });
    return c.noErr;
}

fn succeed(status: c.OSStatus, name: []const u8) !void {
    if (status != c.noErr) {
        log.err("{s}: {}", .{ name, status });
        return error.Unexpected;
    }
}

fn cfStringToUtf8(allocator: std.mem.Allocator, string: c.CFStringRef) ![]u8 {
    const range = c.CFRangeMake(0, c.CFStringGetLength(string));
    var len: c.CFIndex = undefined;
    _ = c.CFStringGetBytes(string, range, c.kCFStringEncodingUTF8, 0, 0, null, 0, &len);
    const utf8 = try allocator.alloc(u8, @intCast(len));
    _ = c.CFStringGetBytes(string, range, c.kCFStringEncodingUTF8, 0, 0, utf8.ptr, len, &len);
    return utf8;
}

fn keycodeToButton(keycode: u16) ?wio.Button {
    comptime var table: [0x7F]wio.Button = undefined;
    comptime for (&table, 0..) |*ptr, i| {
        ptr.* = switch (i) {
            0x00 => .a,
            0x01 => .s,
            0x02 => .d,
            0x03 => .f,
            0x04 => .h,
            0x05 => .g,
            0x06 => .z,
            0x07 => .x,
            0x08 => .c,
            0x09 => .v,
            0x0A => .iso_backslash,
            0x0B => .b,
            0x0C => .q,
            0x0D => .w,
            0x0E => .e,
            0x0F => .r,
            0x10 => .y,
            0x11 => .t,
            0x12 => .@"1",
            0x13 => .@"2",
            0x14 => .@"3",
            0x15 => .@"4",
            0x16 => .@"6",
            0x17 => .@"5",
            0x18 => .equals,
            0x19 => .@"9",
            0x1A => .@"7",
            0x1B => .minus,
            0x1C => .@"8",
            0x1D => .@"0",
            0x1E => .right_bracket,
            0x1F => .o,
            0x20 => .u,
            0x21 => .left_bracket,
            0x22 => .i,
            0x23 => .p,
            0x24 => .enter,
            0x25 => .l,
            0x26 => .j,
            0x27 => .apostrophe,
            0x28 => .k,
            0x29 => .semicolon,
            0x2A => .backslash,
            0x2B => .comma,
            0x2C => .slash,
            0x2D => .n,
            0x2E => .m,
            0x2F => .dot,
            0x30 => .tab,
            0x31 => .space,
            0x32 => .grave,
            0x33 => .backspace,
            0x35 => .escape,
            0x36 => .right_gui,
            0x37 => .left_gui,
            0x38 => .left_shift,
            0x39 => .caps_lock,
            0x3A => .left_alt,
            0x3B => .left_control,
            0x3C => .right_shift,
            0x3D => .right_alt,
            0x3E => .right_control,
            0x40 => .f17,
            0x41 => .kp_dot,
            0x43 => .kp_star,
            0x45 => .kp_plus,
            0x47 => .num_lock,
            0x4B => .kp_slash,
            0x4C => .kp_enter,
            0x4E => .kp_minus,
            0x4F => .f18,
            0x50 => .f19,
            0x51 => .kp_equals,
            0x52 => .kp_0,
            0x53 => .kp_1,
            0x54 => .kp_2,
            0x55 => .kp_3,
            0x56 => .kp_4,
            0x57 => .kp_5,
            0x58 => .kp_6,
            0x59 => .kp_7,
            0x5A => .f20,
            0x5B => .kp_8,
            0x5C => .kp_9,
            0x5D => .international3,
            0x5E => .international1,
            0x5F => .kp_comma,
            0x60 => .f5,
            0x61 => .f6,
            0x62 => .f7,
            0x63 => .f3,
            0x64 => .f8,
            0x65 => .f9,
            0x66 => .lang2,
            0x67 => .f11,
            0x68 => .lang1,
            0x69 => .f13,
            0x6A => .f16,
            0x6B => .f14,
            0x6D => .f10,
            0x6E => .application,
            0x6F => .f12,
            0x71 => .f15,
            0x72 => .insert,
            0x73 => .home,
            0x74 => .page_up,
            0x75 => .delete,
            0x76 => .f4,
            0x77 => .end,
            0x78 => .f2,
            0x79 => .page_down,
            0x7A => .f1,
            0x7B => .left,
            0x7C => .right,
            0x7D => .down,
            0x7E => .up,
            else => .mouse_left,
        };
    };
    return if (keycode < table.len and table[keycode] != .mouse_left) table[keycode] else null;
}

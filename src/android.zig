const std = @import("std");
const build_options = @import("build_options");
const android = @import("android");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);
const c = @cImport({
    @cInclude("jni.h");
    @cInclude("android/input.h");
    @cInclude("android/native_window_jni.h");
    @cInclude("EGL/egl.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_android.h");
});

pub const logFn = android.logFn;

var events: internal.EventQueue = .{};
var events_mutex: std.Io.Mutex = .init;
var wait_event: std.Io.Event = .unset;

var window: ?*c.ANativeWindow = null;

var modifiers: wio.Modifiers = .{};
var cursor: c.jint = @intFromEnum(wio.Cursor.arrow);
var cursor_mode: wio.CursorMode = .normal;

var egl_display: c.EGLDisplay = undefined;
var egl_config: c.EGLConfig = null;
var egl_surface: c.EGLSurface = null;
var egl_surface_mutex: std.Io.Mutex = .init;

pub fn init() !void {
    if (build_options.opengl) {
        egl_display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY) orelse return logUnexpectedEgl("eglGetDisplay");
        if (c.eglInitialize(egl_display, null, null) == c.EGL_FALSE) return logUnexpectedEgl("eglInitialize");
    }
}

pub fn deinit() void {
    if (build_options.opengl) {
        _ = c.eglTerminate(egl_display);
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        update();
    }
}

pub fn update() void {}

pub fn wait(options: wio.WaitOptions) void {
    wait_event.reset();
    if (options.timeout_ns) |timeout_ns| {
        wait_event.waitTimeout(internal.io, .{ .duration = .{ .clock = std.Io.Clock.awake, .raw = .{ .nanoseconds = timeout_ns } } }) catch {};
    } else {
        wait_event.waitUncancelable(internal.io);
    }
}

pub fn cancelWait() void {
    wait_event.set(internal.io);
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = style;
    _ = title;
    _ = message;
}

pub fn openUri(uri: []const u8) void {
    _ = uri;
}

pub fn getModifiers() wio.Modifiers {
    return modifiers;
}

var created = false;

pub fn createWindow(options: wio.CreateWindowOptions) !Window {
    if (created) return error.AlreadyCreated;
    created = true;

    if (build_options.opengl) {
        if (options.gl_options) |gl| {
            var count: i32 = undefined;
            if (c.eglChooseConfig(egl_display, &[_]i32{
                c.EGL_RED_SIZE,       gl.red_bits,
                c.EGL_GREEN_SIZE,     gl.green_bits,
                c.EGL_BLUE_SIZE,      gl.blue_bits,
                c.EGL_ALPHA_SIZE,     gl.alpha_bits,
                c.EGL_DEPTH_SIZE,     gl.depth_bits,
                c.EGL_STENCIL_SIZE,   gl.stencil_bits,
                c.EGL_SAMPLE_BUFFERS, if (gl.samples != 0) 1 else 0,
                c.EGL_SAMPLES,        gl.samples,
                c.EGL_NONE,
            }, &egl_config, 1, &count) == c.EGL_FALSE) return logUnexpectedEgl("eglChooseConfig");
        }
    }

    return .{};
}

pub const Window = struct {
    pub fn destroy(_: *Window) void {
        events.deinit();
    }

    pub fn getEvent(_: *Window) ?wio.Event {
        events_mutex.lockUncancelable(internal.io);
        defer events_mutex.unlock(internal.io);
        return events.pop();
    }

    pub fn enableTextInput(_: *Window, _: wio.TextInputOptions) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.enableTextInput);
    }

    pub fn disableTextInput(_: *Window) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.disableTextInput);
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setMode(_: *Window, _: wio.WindowMode) void {}

    pub fn setSize(_: *Window, _: wio.Size) void {}

    pub fn setParent(_: *Window, _: usize) void {}

    pub fn setCursor(_: *Window, shape: wio.Cursor) void {
        cursor = @intFromEnum(shape);
        if (cursor_mode == .normal) {
            java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.setCursor, cursor);
        }
    }

    pub fn setCursorMode(_: *Window, mode: wio.CursorMode) void {
        cursor_mode = mode;
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.setCursorMode, @as(c.jint, @intFromEnum(mode)));
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.setCursor, if (mode == .normal) cursor else -1);
    }

    pub fn requestAttention(_: *Window) void {}

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        const text_z = internal.allocator.dupeZ(u8, text) catch return;
        defer internal.allocator.free(text_z);

        const text_j = java.env.*.*.NewStringUTF.?(java.env, text_z) orelse return;
        defer java.env.*.*.DeleteLocalRef.?(java.env, text_j);

        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.setClipboardText, text_j);
    }

    pub fn getClipboardText(_: *Window, allocator: std.mem.Allocator) ?[]u8 {
        const text_j = java.env.*.*.CallObjectMethod.?(java.env, java.activity, java.getClipboardText) orelse return null;
        defer java.env.*.*.DeleteLocalRef.?(java.env, text_j);

        const text_z = java.env.*.*.GetStringUTFChars.?(java.env, text_j, null) orelse return null;
        defer java.env.*.*.ReleaseStringUTFChars.?(java.env, text_j, text_z);

        return allocator.dupe(u8, std.mem.sliceTo(text_z, 0)) catch null;
    }

    pub fn getDropData(_: *Window, _: std.mem.Allocator) wio.DropData {
        return .{ .files = &.{}, .text = null };
    }

    pub fn createFramebuffer(_: *Window, size: wio.Size) !Framebuffer {
        const pixels = try internal.allocator.alloc(u32, @as(usize, size.width) * size.height);
        return .{
            .pixels = pixels,
            .size = size,
        };
    }

    pub fn presentFramebuffer(_: *Window, framebuffer: *Framebuffer) void {
        if (window == null) return;

        const width = framebuffer.size.width;
        const height = framebuffer.size.height;
        if (c.ANativeWindow_setBuffersGeometry(window, width, height, c.AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM) != 0) return;

        var buffer: c.ANativeWindow_Buffer = undefined;
        if (c.ANativeWindow_lock(window, &buffer, null) != 0) return;
        defer _ = c.ANativeWindow_unlockAndPost(window);

        const bitmap: [*]u32 = @ptrCast(@alignCast(buffer.bits));
        const stride: u32 = @bitCast(buffer.stride);
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            @memcpy(bitmap[y * stride .. y * stride + width], framebuffer.pixels[y * width .. (y + 1) * width]);
        }
    }

    pub fn glCreateContext(_: *Window, options: wio.GlCreateContextOptions) !GlContext {
        return .{
            .context = c.eglCreateContext(egl_display, egl_config, c.EGL_NO_CONTEXT, &[_]i32{
                c.EGL_CONTEXT_MAJOR_VERSION, options.options.major_version,
                c.EGL_CONTEXT_MINOR_VERSION, options.options.minor_version,
                c.EGL_NONE,
            }) orelse return logUnexpectedEgl("eglCreateContext"),
        };
    }

    pub fn glMakeContextCurrent(_: *Window, context: *GlContext) void {
        egl_surface_mutex.lockUncancelable(internal.io);
        defer egl_surface_mutex.unlock(internal.io);
        _ = c.eglMakeCurrent(egl_display, egl_surface, egl_surface, context.context);
    }

    pub fn glSwapBuffers(_: *Window) void {
        egl_surface_mutex.lockUncancelable(internal.io);
        defer egl_surface_mutex.unlock(internal.io);
        _ = c.eglSwapBuffers(egl_display, egl_surface);
    }

    pub fn glSwapInterval(_: *Window, interval: i32) void {
        _ = c.eglSwapInterval(egl_display, interval);
    }

    pub fn vkCreateSurface(_: *Window, instance: usize, allocation_callbacks: ?*const anyopaque, surface: *u64) i32 {
        return c.vkCreateAndroidSurfaceKHR(
            @ptrFromInt(instance),
            &.{
                .sType = c.VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR,
                .pNext = null,
                .flags = 0,
                .window = window,
            },
            @ptrCast(@alignCast(allocation_callbacks)),
            @ptrCast(surface),
        );
    }
};

pub const Framebuffer = struct {
    pixels: []u32,
    size: wio.Size,

    pub fn destroy(self: *Framebuffer) void {
        internal.allocator.free(self.pixels);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        self.pixels[y * self.size.width + x] = ((rgb & 0xFF0000) >> 16) | (rgb & 0xFF00) | ((rgb & 0xFF) << 16);
    }
};

pub const GlContext = struct {
    context: c.EGLContext,

    pub fn destroy(self: *GlContext) void {
        _ = c.eglDestroyContext(egl_display, self.context);
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

pub fn vkGetInstanceProcAddr(instance: usize, name: [*:0]const u8) ?*const fn () void {
    return @ptrCast(c.vkGetInstanceProcAddr(@ptrFromInt(instance), name));
}

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_android_surface" };
}

pub const JoystickDeviceIterator = struct {
    pub fn init() JoystickDeviceIterator {
        return .{};
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        _ = self;
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        _ = self;
        return null;
    }
};

pub const JoystickDevice = struct {
    pub fn release(self: JoystickDevice) void {
        _ = self;
    }

    pub fn open(self: JoystickDevice) !Joystick {
        _ = self;
        return error.Unexpected;
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }
};

pub const Joystick = struct {
    pub fn close(self: *Joystick) void {
        _ = self;
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        _ = self;
        return null;
    }
};

pub const AudioDeviceIterator = struct {
    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        _ = mode;
        return .{};
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        _ = self;
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        _ = self;
        return null;
    }
};

pub const AudioDevice = struct {
    pub fn release(self: AudioDevice) void {
        _ = self;
    }

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        _ = self;
        _ = writeFn;
        _ = format;
        return error.Unexpected;
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !AudioInput {
        _ = self;
        _ = readFn;
        _ = format;
        return error.Unexpected;
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.Unexpected;
    }
};

pub const AudioOutput = struct {
    pub fn close(self: *AudioOutput) void {
        _ = self;
    }
};

pub const AudioInput = struct {
    pub fn close(self: *AudioInput) void {
        _ = self;
    }
};

export fn JNI_OnLoad(vm: *c.JavaVM, _: ?*anyopaque) c.jint {
    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) != c.JNI_OK) return c.JNI_ERR;

    const class = env.*.*.FindClass.?(env, "net/tiredsleepy/wio/WioActivity") orelse return c.JNI_ERR;
    if (env.*.*.RegisterNatives.?(env, class, &native.methods, native.methods.len) != c.JNI_OK) return c.JNI_ERR;

    java.vm = vm;
    java.enableTextInput = env.*.*.GetMethodID.?(env, class, "enableTextInput", "()V") orelse return c.JNI_ERR;
    java.disableTextInput = env.*.*.GetMethodID.?(env, class, "disableTextInput", "()V") orelse return c.JNI_ERR;
    java.setCursor = env.*.*.GetMethodID.?(env, class, "setCursor", "(I)V") orelse return c.JNI_ERR;
    java.setCursorMode = env.*.*.GetMethodID.?(env, class, "setCursorMode", "(I)V") orelse return c.JNI_ERR;
    java.setClipboardText = env.*.*.GetMethodID.?(env, class, "setClipboardText", "(Ljava/lang/String;)V") orelse return c.JNI_ERR;
    java.getClipboardText = env.*.*.GetMethodID.?(env, class, "getClipboardText", "()Ljava/lang/String;") orelse return c.JNI_ERR;

    return c.JNI_VERSION_1_6;
}

fn main() void {
    if (java.vm.*.*.AttachCurrentThread.?(java.vm, @ptrCast(&java.env), null) != c.JNI_OK) {
        log.err("AttachCurrentThread failed", .{});
        return;
    }

    @import("root").main() catch |err| {
        std.log.err("{s}", .{@errorName(err)});
    };

    std.process.exit(0);
}

const java = struct {
    var vm: *c.JavaVM = undefined;
    var env: *c.JNIEnv = undefined;

    var activity: c.jobject = undefined;

    var enableTextInput: c.jmethodID = undefined;
    var disableTextInput: c.jmethodID = undefined;
    var setCursor: c.jmethodID = undefined;
    var setCursorMode: c.jmethodID = undefined;
    var setClipboardText: c.jmethodID = undefined;
    var getClipboardText: c.jmethodID = undefined;
};

const native = struct {
    const methods = [_]c.JNINativeMethod{
        .{ .name = "onCreateNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onCreate)) },
        .{ .name = "onDestroyNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onDestroy)) },
        .{ .name = "onWindowFocusChangedNative", .signature = "(Z)V", .fnPtr = @ptrCast(@constCast(&onWindowFocusChanged)) },
        .{ .name = "onTouchEventNative", .signature = "(IIII)V", .fnPtr = @ptrCast(@constCast(&onTouchEvent)) },
        .{ .name = "pushMouseEventNative", .signature = "(III)V", .fnPtr = @ptrCast(@constCast(&pushMouseEvent)) },
        .{ .name = "pushScrollEventNative", .signature = "(FF)V", .fnPtr = @ptrCast(@constCast(&pushScrollEvent)) },
        .{ .name = "onKeyDownNative", .signature = "(II)Z", .fnPtr = @ptrCast(@constCast(&onKeyDown)) },
        .{ .name = "onKeyUpNative", .signature = "(I)Z", .fnPtr = @ptrCast(@constCast(&onKeyUp)) },
        .{ .name = "surfaceCreatedNative", .signature = "(Landroid/view/Surface;)V", .fnPtr = @ptrCast(@constCast(&surfaceCreated)) },
        .{ .name = "surfaceChangedNative", .signature = "(FII)V", .fnPtr = @ptrCast(@constCast(&surfaceChanged)) },
        .{ .name = "surfaceDestroyedNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&surfaceDestroyed)) },
        .{ .name = "onGlobalLayoutNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onGlobalLayout)) },
        .{ .name = "onCapturedPointerEventNative", .signature = "(II)V", .fnPtr = @ptrCast(@constCast(&onCapturedPointerEvent)) },
        .{ .name = "pushCharEventNative", .signature = "(I)V", .fnPtr = @ptrCast(@constCast(&pushCharEvent)) },
    };

    fn onCreate(env: *c.JNIEnv, instance: c.jobject) callconv(.c) void {
        java.activity = env.*.*.NewGlobalRef.?(env, instance);

        const thread = std.Thread.spawn(.{}, main, .{}) catch |err| {
            std.log.err("{s}", .{@errorName(err)});
            return;
        };
        thread.detach();
    }

    fn onDestroy(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        pushEvent(.close);
    }

    fn onWindowFocusChanged(env: *c.JNIEnv, instance: c.jobject, focused: c.jboolean) callconv(.c) void {
        pushEvent(if (focused == c.JNI_TRUE) .focused else .unfocused);

        if (focused == c.JNI_TRUE and cursor_mode == .relative) {
            env.*.*.CallVoidMethod.?(env, instance, java.setCursorMode, @as(c.jint, @intFromEnum(cursor_mode)));
        }

        modifiers = .{};
    }

    fn onTouchEvent(_: *c.JNIEnv, _: c.jobject, action: c.jint, id_j: c.jint, x: c.jint, y: c.jint) callconv(.c) void {
        const id = std.math.cast(u8, id_j) orelse return;
        switch (action) {
            c.AMOTION_EVENT_ACTION_DOWN,
            c.AMOTION_EVENT_ACTION_MOVE,
            c.AMOTION_EVENT_ACTION_POINTER_DOWN,
            => pushEvent(.{ .touch = .{ .id = id, .x = std.math.cast(u16, x) orelse return, .y = std.math.cast(u16, y) orelse return } }),

            c.AMOTION_EVENT_ACTION_UP,
            c.AMOTION_EVENT_ACTION_POINTER_UP,
            => pushEvent(.{ .touch_end = .{ .id = id, .ignore = false } }),

            c.AMOTION_EVENT_ACTION_CANCEL,
            => pushEvent(.{ .touch_end = .{ .id = id, .ignore = true } }),

            else => {},
        }
    }

    var last_buttons: c.jint = 0;

    fn pushMouseEvent(_: *c.JNIEnv, _: c.jobject, x: c.jint, y: c.jint, buttons: c.jint) callconv(.c) void {
        pushEvent(.{ .mouse = .{ .x = std.math.cast(u16, x) orelse return, .y = std.math.cast(u16, y) orelse return } });

        const changes = last_buttons ^ buttons;
        if (changes != 0) {
            last_buttons = buttons;
            var i = c.AMOTION_EVENT_BUTTON_PRIMARY;
            while (i <= c.AMOTION_EVENT_BUTTON_FORWARD) : (i <<= 1) {
                if (changes & i != 0) {
                    const button: wio.Button = switch (i) {
                        c.AMOTION_EVENT_BUTTON_PRIMARY => .mouse_left,
                        c.AMOTION_EVENT_BUTTON_SECONDARY => .mouse_right,
                        c.AMOTION_EVENT_BUTTON_TERTIARY => .mouse_middle,
                        c.AMOTION_EVENT_BUTTON_BACK => .mouse_back,
                        c.AMOTION_EVENT_BUTTON_FORWARD => .mouse_forward,
                        else => unreachable,
                    };
                    if (buttons & i != 0) {
                        pushEvent(.{ .button_press = button });
                    } else {
                        pushEvent(.{ .button_release = button });
                    }
                }
            }
        }
    }

    fn pushScrollEvent(_: *c.JNIEnv, _: c.jobject, vertical: c.jfloat, horizontal: c.jfloat) callconv(.c) void {
        if (vertical != 0) pushEvent(.{ .scroll_vertical = -vertical });
        if (horizontal != 0) pushEvent(.{ .scroll_horizontal = -horizontal });
    }

    fn onKeyDown(_: *c.JNIEnv, _: c.jobject, keycode: c.jint, repeat: c.jint) callconv(.c) c.jboolean {
        const button = keycodeToButton(keycode) orelse return c.JNI_FALSE;
        pushEvent(if (repeat == 0) .{ .button_press = button } else .{ .button_repeat = button });
        switch (button) {
            .left_control, .right_control => modifiers.control = true,
            .left_shift, .right_shift => modifiers.shift = true,
            .left_alt, .right_alt => modifiers.alt = true,
            else => {},
        }
        return c.JNI_TRUE;
    }

    fn onKeyUp(_: *c.JNIEnv, _: c.jobject, keycode: c.jint) callconv(.c) c.jboolean {
        const button = keycodeToButton(keycode) orelse return c.JNI_FALSE;
        pushEvent(.{ .button_release = button });
        switch (button) {
            .left_control, .right_control => modifiers.control = false,
            .left_shift, .right_shift => modifiers.shift = false,
            .left_alt, .right_alt => modifiers.alt = false,
            else => {},
        }
        return c.JNI_TRUE;
    }

    fn surfaceCreated(env: *c.JNIEnv, _: c.jobject, surface: c.jobject) callconv(.c) void {
        window = c.ANativeWindow_fromSurface(env, surface);
        pushEvent(.visible);

        if (build_options.opengl) {
            if (egl_config != null) {
                egl_surface_mutex.lockUncancelable(internal.io);
                defer egl_surface_mutex.unlock(internal.io);
                egl_surface = c.eglCreateWindowSurface(egl_display, egl_config, window, null) orelse {
                    logEglError("eglCreateWindowSurface");
                    return;
                };
            }
        }
    }

    fn surfaceChanged(_: *c.JNIEnv, _: c.jobject, density: c.jfloat, width: c.jint, height: c.jint) callconv(.c) void {
        const size: wio.Size = .{ .width = std.math.lossyCast(u16, width), .height = std.math.lossyCast(u16, height) };
        pushEvent(.{ .scale = density });
        pushEvent(.{ .size_logical = size });
        pushEvent(.{ .size_physical = size });
    }

    fn surfaceDestroyed(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        c.ANativeWindow_release(window);
        window = null;
        pushEvent(.hidden);

        if (build_options.opengl) {
            if (egl_surface) |_| {
                egl_surface_mutex.lockUncancelable(internal.io);
                defer egl_surface_mutex.unlock(internal.io);
                _ = c.eglDestroySurface(egl_display, egl_surface);
                egl_surface = null;
            }
        }
    }

    fn onGlobalLayout(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        pushEvent(.draw);
    }

    fn onCapturedPointerEvent(_: *c.JNIEnv, _: c.jobject, x: c.jint, y: c.jint) callconv(.c) void {
        pushEvent(.{ .mouse_relative = .{ .x = std.math.cast(i16, x) orelse return, .y = std.math.cast(i16, y) orelse return } });
    }

    fn pushCharEvent(_: *c.JNIEnv, _: c.jobject, codepoint: c.jint) callconv(.c) void {
        pushEvent(.{ .char = std.math.cast(u21, codepoint) orelse return });
    }
};

fn pushEvent(event: wio.Event) void {
    events_mutex.lockUncancelable(internal.io);
    defer events_mutex.unlock(internal.io);
    events.push(event);
    wait_event.set(internal.io);
}

fn logUnexpectedEgl(name: []const u8) error{Unexpected} {
    logEglError(name);
    return error.Unexpected;
}

fn logEglError(name: []const u8) void {
    log.err("{s} failed, error 0x{X}", .{ name, c.eglGetError() });
}

fn keycodeToButton(keycode: i32) ?wio.Button {
    const start = c.AKEYCODE_0;
    const end = c.AKEYCODE_RO;
    comptime var table: [end - start + 1]wio.Button = undefined;
    comptime for (&table, start..) |*ptr, i| {
        ptr.* = switch (i) {
            c.AKEYCODE_0 => .@"0",
            c.AKEYCODE_1 => .@"1",
            c.AKEYCODE_2 => .@"2",
            c.AKEYCODE_3 => .@"3",
            c.AKEYCODE_4 => .@"4",
            c.AKEYCODE_5 => .@"5",
            c.AKEYCODE_6 => .@"6",
            c.AKEYCODE_7 => .@"7",
            c.AKEYCODE_8 => .@"8",
            c.AKEYCODE_9 => .@"9",
            c.AKEYCODE_DPAD_UP => .up,
            c.AKEYCODE_DPAD_DOWN => .down,
            c.AKEYCODE_DPAD_LEFT => .left,
            c.AKEYCODE_DPAD_RIGHT => .right,
            c.AKEYCODE_A => .a,
            c.AKEYCODE_B => .b,
            c.AKEYCODE_C => .c,
            c.AKEYCODE_D => .d,
            c.AKEYCODE_E => .e,
            c.AKEYCODE_F => .f,
            c.AKEYCODE_G => .g,
            c.AKEYCODE_H => .h,
            c.AKEYCODE_I => .i,
            c.AKEYCODE_J => .j,
            c.AKEYCODE_K => .k,
            c.AKEYCODE_L => .l,
            c.AKEYCODE_M => .m,
            c.AKEYCODE_N => .n,
            c.AKEYCODE_O => .o,
            c.AKEYCODE_P => .p,
            c.AKEYCODE_Q => .q,
            c.AKEYCODE_R => .r,
            c.AKEYCODE_S => .s,
            c.AKEYCODE_T => .t,
            c.AKEYCODE_U => .u,
            c.AKEYCODE_V => .v,
            c.AKEYCODE_W => .w,
            c.AKEYCODE_X => .x,
            c.AKEYCODE_Y => .y,
            c.AKEYCODE_Z => .z,
            c.AKEYCODE_COMMA => .comma,
            c.AKEYCODE_PERIOD => .dot,
            c.AKEYCODE_ALT_LEFT => .left_alt,
            c.AKEYCODE_ALT_RIGHT => .right_alt,
            c.AKEYCODE_SHIFT_LEFT => .left_shift,
            c.AKEYCODE_SHIFT_RIGHT => .right_shift,
            c.AKEYCODE_TAB => .tab,
            c.AKEYCODE_SPACE => .space,
            c.AKEYCODE_ENTER => .enter,
            c.AKEYCODE_DEL => .backspace,
            c.AKEYCODE_GRAVE => .grave,
            c.AKEYCODE_MINUS => .minus,
            c.AKEYCODE_EQUALS => .equals,
            c.AKEYCODE_LEFT_BRACKET => .left_bracket,
            c.AKEYCODE_RIGHT_BRACKET => .right_bracket,
            c.AKEYCODE_BACKSLASH => .backslash,
            c.AKEYCODE_SEMICOLON => .semicolon,
            c.AKEYCODE_APOSTROPHE => .apostrophe,
            c.AKEYCODE_SLASH => .slash,
            c.AKEYCODE_MENU => .application,
            c.AKEYCODE_PAGE_UP => .page_up,
            c.AKEYCODE_PAGE_DOWN => .page_down,
            c.AKEYCODE_ESCAPE => .escape,
            c.AKEYCODE_FORWARD_DEL => .delete,
            c.AKEYCODE_CTRL_LEFT => .left_control,
            c.AKEYCODE_CTRL_RIGHT => .right_control,
            c.AKEYCODE_CAPS_LOCK => .caps_lock,
            c.AKEYCODE_SCROLL_LOCK => .scroll_lock,
            c.AKEYCODE_META_LEFT => .left_gui,
            c.AKEYCODE_META_RIGHT => .right_gui,
            c.AKEYCODE_SYSRQ => .print_screen,
            c.AKEYCODE_BREAK => .pause,
            c.AKEYCODE_MOVE_HOME => .home,
            c.AKEYCODE_MOVE_END => .end,
            c.AKEYCODE_INSERT => .insert,
            c.AKEYCODE_F1 => .f1,
            c.AKEYCODE_F2 => .f2,
            c.AKEYCODE_F3 => .f3,
            c.AKEYCODE_F4 => .f4,
            c.AKEYCODE_F5 => .f5,
            c.AKEYCODE_F6 => .f6,
            c.AKEYCODE_F7 => .f7,
            c.AKEYCODE_F8 => .f8,
            c.AKEYCODE_F9 => .f9,
            c.AKEYCODE_F10 => .f10,
            c.AKEYCODE_F11 => .f11,
            c.AKEYCODE_F12 => .f12,
            c.AKEYCODE_NUM_LOCK => .num_lock,
            c.AKEYCODE_NUMPAD_0 => .kp_0,
            c.AKEYCODE_NUMPAD_1 => .kp_1,
            c.AKEYCODE_NUMPAD_2 => .kp_2,
            c.AKEYCODE_NUMPAD_3 => .kp_3,
            c.AKEYCODE_NUMPAD_4 => .kp_4,
            c.AKEYCODE_NUMPAD_5 => .kp_5,
            c.AKEYCODE_NUMPAD_6 => .kp_6,
            c.AKEYCODE_NUMPAD_7 => .kp_7,
            c.AKEYCODE_NUMPAD_8 => .kp_8,
            c.AKEYCODE_NUMPAD_9 => .kp_9,
            c.AKEYCODE_NUMPAD_DIVIDE => .kp_slash,
            c.AKEYCODE_NUMPAD_MULTIPLY => .kp_star,
            c.AKEYCODE_NUMPAD_SUBTRACT => .kp_minus,
            c.AKEYCODE_NUMPAD_ADD => .kp_plus,
            c.AKEYCODE_NUMPAD_DOT => .kp_dot,
            c.AKEYCODE_NUMPAD_COMMA => .kp_comma,
            c.AKEYCODE_NUMPAD_ENTER => .kp_enter,
            c.AKEYCODE_NUMPAD_EQUALS => .kp_equals,
            c.AKEYCODE_MUHENKAN => .international5,
            c.AKEYCODE_HENKAN => .international4,
            c.AKEYCODE_KATAKANA_HIRAGANA => .international2,
            c.AKEYCODE_YEN => .international3,
            c.AKEYCODE_RO => .international1,
            else => .mouse_left,
        };
    };
    return if (keycode >= start and keycode <= end and table[@intCast(keycode - start)] != .mouse_left) table[@intCast(keycode - start)] else null;
}

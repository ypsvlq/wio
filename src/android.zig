const std = @import("std");
const build_options = @import("build_options");
const c = @import("c");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

const LogWriter = struct {
    prio: c_int,
    interface: std.Io.Writer,

    pub fn init(prio: c_int, buffer: *[1023]u8) LogWriter {
        return .{
            .prio = prio,
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                    .flush = flush,
                },
                .buffer = buffer,
            },
        };
    }

    fn drain(writer: *std.Io.Writer, data: []const []const u8, _: usize) !usize {
        const empty = writer.unusedCapacitySlice();
        const n = @min(empty.len, data[0].len);
        @memcpy(empty[0..n], data[0][0..n]);
        writer.end += n;
        if (n == empty.len) {
            try writer.flush();
        }
        return n;
    }

    fn flush(writer: *std.Io.Writer) !void {
        const self: *LogWriter = @fieldParentPtr("interface", writer);
        const text = writer.buffered();
        _ = c.__android_log_print(self.prio, null, "%.*s", text.len, text.ptr);
        writer.end = 0;
    }
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    const prio = switch (level) {
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };

    const prefix = if (scope == .default) "" else @tagName(scope) ++ ": ";

    var buffer: [1023]u8 = undefined;
    var writer: LogWriter = .init(prio, &buffer);
    writer.interface.print(prefix ++ format, args) catch return;
    writer.interface.flush() catch return;
}

const egl = internal.egl(c, c);

var window: ?*c.ANativeWindow = null;
var window_mutex: std.Io.Mutex = .init;

var wait_event: std.Io.Event = .unset;
var event_fn_data: ?*anyopaque = undefined;
var modifiers: wio.Modifiers = .{};
var relative_mouse: bool = false;

var egl_config: c.EGLConfig = null;
var egl_surface: c.EGLSurface = null; // protected by `window_mutex`

var joystickConnectedFn: ?*const fn (wio.JoystickDevice) void = null;
var joystick_map: std.AutoHashMapUnmanaged(c.jint, JoystickInfo) = .empty;
var joystick_map_mutex: std.Io.Mutex = .init;
var new_joysticks: std.ArrayList(c.jint) = .empty;
var new_joysticks_mutex: std.Io.Mutex = .init;

var audioDefaultInputFn: ?*const fn (wio.AudioDevice) void = null;
var audio_input_available = false;

pub fn init(options: wio.InitOptions) !void {
    if (build_options.opengl) {
        try egl.init(c.EGL_DEFAULT_DISPLAY);
    }

    if (build_options.joystick) {
        joystickConnectedFn = options.joystickConnectedFn;
    }

    if (build_options.audio) {
        if (options.audioDefaultOutputFn) |callback| callback(.{ .backend = .{} });
        if (options.audioDefaultInputFn) |callback| callback(.{ .backend = .{} });
        audioDefaultInputFn = options.audioDefaultInputFn;
    }
}

pub fn deinit() void {
    if (build_options.joystick) {
        new_joysticks_mutex.lockUncancelable(internal.io);
        defer new_joysticks_mutex.unlock(internal.io);

        new_joysticks.clearAndFree(internal.allocator);

        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        var iter = joystick_map.valueIterator();
        while (iter.next()) |info| {
            info.deinit();
        }
        joystick_map.clearAndFree(internal.allocator);
    }

    if (build_options.opengl) {
        _ = c.eglTerminate(egl.display);
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {
        update();
    }
}

pub fn update() void {
    if (build_options.joystick) {
        if (joystickConnectedFn) |callback| {
            new_joysticks_mutex.lockUncancelable(internal.io);
            defer new_joysticks_mutex.unlock(internal.io);

            while (new_joysticks.pop()) |id| {
                callback(.{ .backend = .{ .id = id } });
            }
        }
    }

    if (build_options.audio) {
        if (audio_input_available) {
            if (audioDefaultInputFn) |callback| {
                callback(.{ .backend = .{} });
            }
            audio_input_available = false;
        }
    }
}

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

pub const Window = struct {
    var created_event: std.Io.Event = .unset;

    pub fn create(options: wio.CreateWindowOptions) !Window {
        event_fn_data = options.event_fn_data;

        internal.eventFn(event_fn_data, .{ .position = .{ .x = 0, .y = 0 } });

        if (build_options.opengl) {
            if (options.gl_options) |gl| {
                egl_config = try egl.chooseConfig(gl);
            }
        }

        created_event.set(std.Io.Threaded.global_single_threaded.io());

        return .{};
    }

    pub fn destroy(self: *Window) void {
        self.disableDrawAvailableEvents();
    }

    pub fn enableTextInput(_: *Window, _: wio.TextInputOptions) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.enableTextInput);
    }

    pub fn disableTextInput(_: *Window) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.disableTextInput);
    }

    pub fn enableRelativeMouse(_: *Window, _: wio.RelativeMouseOptions) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.enableRelativeMouse);
        relative_mouse = true;
    }

    pub fn disableRelativeMouse(_: *Window) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.disableRelativeMouse);
        relative_mouse = false;
    }

    pub fn enableDrawAvailableEvents(_: *Window) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.enableDrawAvailableEvents);
    }

    pub fn disableDrawAvailableEvents(_: *Window) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.disbleDrawAvailableEvents);
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setMode(_: *Window, _: wio.WindowMode) void {}

    pub fn setPosition(_: *Window, _: wio.RelativePosition) void {}

    pub fn setSize(_: *Window, _: wio.Size) void {}

    pub fn setParent(_: *Window, _: usize) void {}

    pub fn setCursor(_: *Window, shape: wio.Cursor) void {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.setCursor, @as(c.jint, @intFromEnum(shape)));
    }

    pub fn requestAttention(_: *Window) void {}

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        const text_z = internal.allocator.dupeSentinel(u8, text, 0) catch return;
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
        window_mutex.lockUncancelable(internal.io);
        defer window_mutex.unlock(internal.io);

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
            .context = try egl.createContext(
                egl_config,
                options.options,
                if (options.share) |share| share.backend.context else c.EGL_NO_CONTEXT,
            ),
        };
    }

    pub fn glMakeContextCurrent(_: *Window, context: GlContext) void {
        window_mutex.lockUncancelable(internal.io);
        defer window_mutex.unlock(internal.io);
        _ = c.eglMakeCurrent(egl.display, egl_surface, egl_surface, context.context);
    }

    pub fn glSwapBuffers(_: *Window) void {
        window_mutex.lockUncancelable(internal.io);
        defer window_mutex.unlock(internal.io);
        _ = c.eglSwapBuffers(egl.display, egl_surface);
    }

    pub fn glSwapInterval(_: *Window, interval: i32) void {
        _ = c.eglSwapInterval(egl.display, interval);
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

    pub fn destroy(self: GlContext) void {
        _ = c.eglDestroyContext(egl.display, self.context);
    }
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return c.eglGetProcAddress(name);
}

pub fn glReleaseCurrentContext() void {
    _ = c.eglMakeCurrent(egl.display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT);
}

pub fn vkGetInstanceProcAddr(instance: usize, name: [*:0]const u8) ?*const fn () void {
    return @ptrCast(c.vkGetInstanceProcAddr(@ptrFromInt(instance), name));
}

pub fn getRequiredVulkanInstanceExtensions() []const [*:0]const u8 {
    return &.{ "VK_KHR_surface", "VK_KHR_android_surface" };
}

pub const JoystickDeviceIterator = struct {
    list: []JoystickDevice,
    index: usize = 0,

    pub fn init() JoystickDeviceIterator {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        const list = internal.allocator.alloc(JoystickDevice, joystick_map.count()) catch return .{ .list = &.{} };
        var iter = joystick_map.keyIterator();
        var i: usize = 0;
        while (iter.next()) |key_ptr| : (i += 1) {
            list[i] = .{ .id = key_ptr.* };
        }
        return .{ .list = list };
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        internal.allocator.free(self.list);
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.index == self.list.len) return null;
        defer self.index += 1;
        return self.list[self.index];
    }
};

pub const JoystickDevice = struct {
    id: c.jint,

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !*Joystick {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        const info = joystick_map.getPtr(self.id) orelse return error.Unexpected;
        if (info.joystick != null) return error.Unexpected;

        const joystick = try internal.allocator.create(Joystick);
        errdefer internal.allocator.destroy(joystick);

        const axes = try internal.allocator.alloc(u16, info.axes.len);
        errdefer internal.allocator.free(axes);
        @memset(axes, 0xFFFF / 2);

        const buttons = try internal.allocator.alloc(bool, info.buttons.len);
        errdefer internal.allocator.free(buttons);
        @memset(buttons, false);

        const axes_copy = try internal.allocator.alloc(u16, axes.len);
        errdefer internal.allocator.free(axes_copy);

        const buttons_copy = try internal.allocator.alloc(bool, buttons.len);
        errdefer internal.allocator.free(buttons_copy);

        joystick.* = .{
            .axes = axes,
            .buttons = buttons,
            .axes_copy = axes_copy,
            .buttons_copy = buttons_copy,
        };
        info.joystick = joystick;
        return joystick;
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        const info = joystick_map.get(self.id) orelse return error.Unexpected;
        return allocator.dupe(u8, info.descriptor);
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        const info = joystick_map.get(self.id) orelse return error.Unexpected;
        return allocator.dupe(u8, info.name);
    }
};

pub const Joystick = struct {
    axes: []u16,
    buttons: []bool,
    axes_copy: []u16,
    buttons_copy: []bool,
    mutex: std.Io.Mutex = .init,
    removed: bool = false,

    pub fn close(self: *Joystick) void {
        internal.allocator.free(self.buttons);
        internal.allocator.destroy(self);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        if (self.removed) return null;

        self.mutex.lockUncancelable(internal.io);
        defer self.mutex.unlock(internal.io);

        @memcpy(self.axes_copy, self.axes);
        @memcpy(self.buttons_copy, self.buttons);

        return .{ .axes = self.axes_copy, .hats = &.{}, .buttons = self.buttons_copy };
    }
};

pub const AudioDeviceIterator = struct {
    used: bool = false,

    pub fn init(_: wio.AudioDeviceType) AudioDeviceIterator {
        return .{};
    }

    pub fn deinit(_: *AudioDeviceIterator) void {}

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.used) return null;
        self.used = true;
        return .{};
    }
};

pub const AudioDevice = struct {
    pub fn release(_: AudioDevice) void {}

    pub fn openOutput(_: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        var builder: ?*c.AAudioStreamBuilder = undefined;
        try checkAAudioResult(c.AAudio_createStreamBuilder(&builder), "AAudio_createStreamBuilder");
        defer _ = c.AAudioStreamBuilder_delete(builder);
        c.AAudioStreamBuilder_setSampleRate(builder, @bitCast(format.sample_rate));
        c.AAudioStreamBuilder_setChannelCount(builder, format.channels);
        c.AAudioStreamBuilder_setFormat(builder, c.AAUDIO_FORMAT_PCM_FLOAT);
        c.AAudioStreamBuilder_setPerformanceMode(builder, c.AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
        c.AAudioStreamBuilder_setDataCallback(builder, AudioStream.outputCallback, @constCast(writeFn));

        var stream: ?*c.AAudioStream = undefined;
        try checkAAudioResult(c.AAudioStreamBuilder_openStream(builder, &stream), "AAudioStreamBuilder_openStream");
        try checkAAudioResult(c.AAudioStream_requestStart(stream), "AAudioStream_requestStart");
        return .{ .stream = stream.? };
    }

    pub fn openInput(_: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !AudioInput {
        java.env.*.*.CallVoidMethod.?(java.env, java.activity, java.requestRecordAudioPermission);

        var builder: ?*c.AAudioStreamBuilder = undefined;
        try checkAAudioResult(c.AAudio_createStreamBuilder(&builder), "AAudio_createStreamBuilder");
        defer _ = c.AAudioStreamBuilder_delete(builder);
        c.AAudioStreamBuilder_setSampleRate(builder, @bitCast(format.sample_rate));
        c.AAudioStreamBuilder_setChannelCount(builder, format.channels);
        c.AAudioStreamBuilder_setFormat(builder, c.AAUDIO_FORMAT_PCM_FLOAT);
        c.AAudioStreamBuilder_setDirection(builder, c.AAUDIO_DIRECTION_INPUT);
        c.AAudioStreamBuilder_setDataCallback(builder, AudioStream.inputCallback, @constCast(readFn));

        var stream: ?*c.AAudioStream = undefined;
        try checkAAudioResult(c.AAudioStreamBuilder_openStream(builder, &stream), "AAudioStreamBuilder_openStream");
        try checkAAudioResult(c.AAudioStream_requestStart(stream), "AAudioStream_requestStart");
        return .{ .stream = stream.? };
    }

    pub fn getId(_: AudioDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }

    pub fn getName(_: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, "AAudio");
    }
};

const AudioStream = struct {
    stream: *c.AAudioStream,

    pub fn close(self: *AudioStream) void {
        _ = c.AAudioStream_close(self.stream);
    }

    fn outputCallback(stream: ?*c.AAudioStream, user_data: ?*anyopaque, audio_data: ?*anyopaque, num_frames: i32) callconv(.c) c.aaudio_data_callback_result_t {
        const writeFn: *const fn ([]f32) void = @ptrCast(@alignCast(user_data));
        const buffer: [*]f32 = @ptrCast(@alignCast(audio_data));
        const channels = c.AAudioStream_getChannelCount(stream);
        writeFn(buffer[0..@as(u32, @bitCast(num_frames * channels))]);
        return c.AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    fn inputCallback(stream: ?*c.AAudioStream, user_data: ?*anyopaque, audio_data: ?*anyopaque, num_frames: i32) callconv(.c) c.aaudio_data_callback_result_t {
        const readFn: *const fn ([]const f32) void = @ptrCast(@alignCast(user_data));
        const buffer: [*]f32 = @ptrCast(@alignCast(audio_data));
        const channels = c.AAudioStream_getChannelCount(stream);
        readFn(buffer[0..@as(u32, @bitCast(num_frames * channels))]);
        return c.AAUDIO_CALLBACK_RESULT_CONTINUE;
    }
};

pub const AudioOutput = AudioStream;
pub const AudioInput = AudioStream;

fn checkAAudioResult(result: c.aaudio_result_t, name: []const u8) !void {
    if (result < 0) {
        log.err("{s} failed, error {}", .{ name, result });
        return error.Unexpected;
    }
}

export fn JNI_OnLoad(vm: *c.JavaVM, _: ?*anyopaque) c.jint {
    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) != c.JNI_OK) return c.JNI_ERR;

    const class = env.*.*.FindClass.?(env, "net/tiredsleepy/wio/WioActivity") orelse return c.JNI_ERR;
    if (env.*.*.RegisterNatives.?(env, class, &native.methods, native.methods.len) != c.JNI_OK) return c.JNI_ERR;

    java.vm = vm;
    java.enableTextInput = env.*.*.GetMethodID.?(env, class, "enableTextInput", "()V") orelse return c.JNI_ERR;
    java.disableTextInput = env.*.*.GetMethodID.?(env, class, "disableTextInput", "()V") orelse return c.JNI_ERR;
    java.enableRelativeMouse = env.*.*.GetMethodID.?(env, class, "enableRelativeMouse", "()V") orelse return c.JNI_ERR;
    java.disableRelativeMouse = env.*.*.GetMethodID.?(env, class, "disableRelativeMouse", "()V") orelse return c.JNI_ERR;
    java.enableDrawAvailableEvents = env.*.*.GetMethodID.?(env, class, "enableDrawAvailableEvents", "()V") orelse return c.JNI_ERR;
    java.disbleDrawAvailableEvents = env.*.*.GetMethodID.?(env, class, "disableDrawAvailableEvents", "()V") orelse return c.JNI_ERR;
    java.setCursor = env.*.*.GetMethodID.?(env, class, "setCursor", "(I)V") orelse return c.JNI_ERR;
    java.setClipboardText = env.*.*.GetMethodID.?(env, class, "setClipboardText", "(Ljava/lang/String;)V") orelse return c.JNI_ERR;
    java.getClipboardText = env.*.*.GetMethodID.?(env, class, "getClipboardText", "()Ljava/lang/String;") orelse return c.JNI_ERR;
    if (build_options.joystick) {
        java.initJoystick = env.*.*.GetMethodID.?(env, class, "initJoystick", "()V") orelse return c.JNI_ERR;
    }
    if (build_options.audio) {
        java.requestRecordAudioPermission = env.*.*.GetMethodID.?(env, class, "requestRecordAudioPermission", "()V") orelse return c.JNI_ERR;
    }

    return c.JNI_VERSION_1_6;
}

fn threadMain() void {
    if (java.vm.*.*.AttachCurrentThread.?(java.vm, @ptrCast(&java.env), null) != c.JNI_OK) {
        log.err("AttachCurrentThread failed", .{});
        return;
    }

    const main = @import("root").main;
    const info = @typeInfo(@TypeOf(main)).@"fn";
    const args = if (info.params.len == 0)
        .{}
    else if (info.params[0].type.? == std.process.Init.Minimal)
        .{std.process.Init.Minimal{ .args = .{ .vector = &.{} }, .environ = .{ .block = .{ .slice = &.{} } } }};

    @call(.auto, main, args) catch |err| {
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
    var enableRelativeMouse: c.jmethodID = undefined;
    var disableRelativeMouse: c.jmethodID = undefined;
    var enableDrawAvailableEvents: c.jmethodID = undefined;
    var disbleDrawAvailableEvents: c.jmethodID = undefined;
    var setCursor: c.jmethodID = undefined;
    var setClipboardText: c.jmethodID = undefined;
    var getClipboardText: c.jmethodID = undefined;
    var initJoystick: c.jmethodID = undefined;
    var requestRecordAudioPermission: c.jmethodID = undefined;
};

const native = struct {
    const methods = [_]c.JNINativeMethod{
        .{ .name = "onCreateNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onCreate)) },
        .{ .name = "onDestroyNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onDestroy)) },
        .{ .name = "onWindowFocusChangedNative", .signature = "(Z)V", .fnPtr = @ptrCast(@constCast(&onWindowFocusChanged)) },
        .{ .name = "onTouchEventNative", .signature = "(IIII)V", .fnPtr = @ptrCast(@constCast(&onTouchEvent)) },
        .{ .name = "pushMouseEventNative", .signature = "(III)V", .fnPtr = @ptrCast(@constCast(&pushMouseEvent)) },
        .{ .name = "pushScrollEventNative", .signature = "(FF)V", .fnPtr = @ptrCast(@constCast(&pushScrollEvent)) },
        .{ .name = "onKeyDownNative", .signature = "(III)Z", .fnPtr = @ptrCast(@constCast(&onKeyDown)) },
        .{ .name = "onKeyUpNative", .signature = "(II)Z", .fnPtr = @ptrCast(@constCast(&onKeyUp)) },
        .{ .name = "surfaceCreatedNative", .signature = "(Landroid/view/Surface;)V", .fnPtr = @ptrCast(@constCast(&surfaceCreated)) },
        .{ .name = "surfaceChangedNative", .signature = "(FII)V", .fnPtr = @ptrCast(@constCast(&surfaceChanged)) },
        .{ .name = "surfaceDestroyedNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&surfaceDestroyed)) },
        .{ .name = "pushDrawEventNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&pushDrawEvent)) },
        .{ .name = "onCapturedPointerEventNative", .signature = "(II)V", .fnPtr = @ptrCast(@constCast(&onCapturedPointerEvent)) },
        .{ .name = "pushCharEventNative", .signature = "(I)V", .fnPtr = @ptrCast(@constCast(&pushCharEvent)) },
        .{ .name = "pushPreviewResetEventNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&pushPreviewResetEvent)) },
        .{ .name = "pushPreviewCharEventNative", .signature = "(I)V", .fnPtr = @ptrCast(@constCast(&pushPreviewCharEvent)) },
    } ++ if (build_options.joystick) [_]c.JNINativeMethod{
        .{ .name = "onInputDeviceAddedNative", .signature = "(ILjava/lang/String;Ljava/lang/String;[I[I)V", .fnPtr = @ptrCast(@constCast(&onInputDeviceAdded)) },
        .{ .name = "onInputDeviceRemovedNative", .signature = "(I)V", .fnPtr = @ptrCast(@constCast(&onInputDeviceRemoved)) },
        .{ .name = "onJoystickMotionEventNative", .signature = "(IIFFF)V", .fnPtr = @ptrCast(@constCast(&onJoystickMotionEvent)) },
    } else .{} ++ if (build_options.audio) [_]c.JNINativeMethod{
        .{ .name = "onPermissionGrantedNative", .signature = "()V", .fnPtr = @ptrCast(@constCast(&onPermissionGranted)) },
    } else .{};

    fn onCreate(env: *c.JNIEnv, instance: c.jobject) callconv(.c) void {
        java.activity = env.*.*.NewGlobalRef.?(env, instance);

        const thread = std.Thread.spawn(.{}, threadMain, .{}) catch |err| {
            std.log.err("{s}", .{@errorName(err)});
            return;
        };
        thread.detach();

        Window.created_event.waitUncancelable(std.Io.Threaded.global_single_threaded.io());

        if (build_options.joystick) {
            env.*.*.CallVoidMethod.?(env, instance, java.initJoystick);
        }
    }

    fn onDestroy(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        internal.eventFn(event_fn_data, .close);
    }

    fn onWindowFocusChanged(env: *c.JNIEnv, instance: c.jobject, focused: c.jboolean) callconv(.c) void {
        if (focused == c.JNI_FALSE) {
            internal.eventFn(event_fn_data, .unfocused);
            modifiers = .{};
        } else {
            internal.eventFn(event_fn_data, .focused);
            internal.eventFn(event_fn_data, .draw);
            if (relative_mouse) {
                env.*.*.CallVoidMethod.?(env, instance, java.enableRelativeMouse);
            }
        }
    }

    fn onTouchEvent(_: *c.JNIEnv, _: c.jobject, action: c.jint, id_j: c.jint, x: c.jint, y: c.jint) callconv(.c) void {
        const id = std.math.cast(u8, id_j) orelse return;
        switch (action) {
            c.AMOTION_EVENT_ACTION_DOWN,
            c.AMOTION_EVENT_ACTION_MOVE,
            c.AMOTION_EVENT_ACTION_POINTER_DOWN,
            => internal.eventFn(event_fn_data, .{ .touch = .{ .id = id, .x = std.math.cast(u16, x) orelse return, .y = std.math.cast(u16, y) orelse return } }),

            c.AMOTION_EVENT_ACTION_UP,
            c.AMOTION_EVENT_ACTION_POINTER_UP,
            => internal.eventFn(event_fn_data, .{ .touch_end = .{ .id = id, .ignore = false } }),

            c.AMOTION_EVENT_ACTION_CANCEL,
            => internal.eventFn(event_fn_data, .{ .touch_end = .{ .id = id, .ignore = true } }),

            else => {},
        }
    }

    var last_buttons: c.jint = 0;

    fn pushMouseEvent(_: *c.JNIEnv, _: c.jobject, x: c.jint, y: c.jint, buttons: c.jint) callconv(.c) void {
        internal.eventFn(event_fn_data, .{ .mouse = .{ .x = std.math.cast(u16, x) orelse return, .y = std.math.cast(u16, y) orelse return } });

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
                        internal.eventFn(event_fn_data, .{ .button_press = button });
                    } else {
                        internal.eventFn(event_fn_data, .{ .button_release = button });
                    }
                }
            }
        }
    }

    fn pushScrollEvent(_: *c.JNIEnv, _: c.jobject, vertical: c.jfloat, horizontal: c.jfloat) callconv(.c) void {
        if (vertical != 0) internal.eventFn(event_fn_data, .{ .scroll_vertical = -vertical });
        if (horizontal != 0) internal.eventFn(event_fn_data, .{ .scroll_horizontal = -horizontal });
    }

    fn onKeyDown(_: *c.JNIEnv, _: c.jobject, id: c.jint, keycode: c.jint, repeat: c.jint) callconv(.c) c.jboolean {
        if (build_options.joystick) {
            joystick_map_mutex.lockUncancelable(internal.io);
            defer joystick_map_mutex.unlock(internal.io);

            if (joystick_map.getPtr(id)) |info| {
                if (info.joystick) |joystick| {
                    if (std.sort.binarySearch(c.jint, info.buttons, keycode, compareInt)) |index| {
                        joystick.buttons[index] = true;
                        wio.cancelWait();
                    }
                }
                return c.JNI_TRUE;
            }
        }

        const button = keycodeToButton(keycode) orelse return c.JNI_FALSE;
        internal.eventFn(event_fn_data, if (repeat == 0) .{ .button_press = button } else .{ .button_repeat = button });
        updateModifiers(button, true);
        return c.JNI_TRUE;
    }

    fn onKeyUp(_: *c.JNIEnv, _: c.jobject, id: c.jint, keycode: c.jint) callconv(.c) c.jboolean {
        if (build_options.joystick) {
            joystick_map_mutex.lockUncancelable(internal.io);
            defer joystick_map_mutex.unlock(internal.io);

            if (joystick_map.getPtr(id)) |info| {
                if (info.joystick) |joystick| {
                    if (std.sort.binarySearch(c.jint, info.buttons, keycode, compareInt)) |index| {
                        joystick.buttons[index] = false;
                        wio.cancelWait();
                    }
                }
                return c.JNI_TRUE;
            }
        }

        const button = keycodeToButton(keycode) orelse return c.JNI_FALSE;
        internal.eventFn(event_fn_data, .{ .button_release = button });
        updateModifiers(button, false);
        return c.JNI_TRUE;
    }

    fn surfaceCreated(env: *c.JNIEnv, _: c.jobject, surface: c.jobject) callconv(.c) void {
        window_mutex.lockUncancelable(internal.io);
        defer window_mutex.unlock(internal.io);

        window = c.ANativeWindow_fromSurface(env, surface);
        internal.eventFn(event_fn_data, .visible);

        if (build_options.opengl) {
            if (egl_config != null) {
                egl_surface = c.eglCreateWindowSurface(egl.display, egl_config, window, null) orelse {
                    logEglError("eglCreateWindowSurface");
                    return;
                };
            }
        }
    }

    fn surfaceChanged(_: *c.JNIEnv, _: c.jobject, density: c.jfloat, width: c.jint, height: c.jint) callconv(.c) void {
        const size: wio.Size = .{ .width = std.math.lossyCast(u16, width), .height = std.math.lossyCast(u16, height) };
        internal.eventFn(event_fn_data, .{ .scale = density });
        internal.eventFn(event_fn_data, .{ .size_logical = size });
        internal.eventFn(event_fn_data, .{ .size_physical = size });
    }

    fn surfaceDestroyed(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        window_mutex.lockUncancelable(internal.io);
        defer window_mutex.unlock(internal.io);

        c.ANativeWindow_release(window);
        window = null;
        internal.eventFn(event_fn_data, .hidden);

        if (build_options.opengl) {
            if (egl_surface) |_| {
                _ = c.eglDestroySurface(egl.display, egl_surface);
                egl_surface = null;
            }
        }
    }

    fn pushDrawEvent(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        internal.eventFn(event_fn_data, .draw);
    }

    fn onCapturedPointerEvent(_: *c.JNIEnv, _: c.jobject, x: c.jint, y: c.jint) callconv(.c) void {
        internal.eventFn(event_fn_data, .{ .mouse_relative = .{ .x = std.math.cast(i16, x) orelse return, .y = std.math.cast(i16, y) orelse return } });
    }

    fn pushCharEvent(_: *c.JNIEnv, _: c.jobject, codepoint: c.jint) callconv(.c) void {
        internal.eventFn(event_fn_data, .{ .char = std.math.cast(u21, codepoint) orelse return });
    }

    fn pushPreviewResetEvent(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        internal.eventFn(event_fn_data, .preview_reset);
    }

    fn pushPreviewCharEvent(_: *c.JNIEnv, _: c.jobject, codepoint: c.jint) callconv(.c) void {
        internal.eventFn(event_fn_data, .{ .preview_char = std.math.cast(u21, codepoint) orelse return });
    }

    fn onInputDeviceAdded(env: *c.JNIEnv, _: c.jobject, id: c.jint, descriptor: c.jstring, name: c.jstring, axes: c.jintArray, buttons: c.jintArray) callconv(.c) void {
        const info = JoystickInfo.init(env, descriptor, name, axes, buttons) catch return;

        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);
        joystick_map.put(internal.allocator, id, info) catch {
            info.deinit();
            return;
        };

        new_joysticks_mutex.lockUncancelable(internal.io);
        defer new_joysticks_mutex.unlock(internal.io);
        new_joysticks.append(internal.allocator, id) catch {};
    }

    fn onInputDeviceRemoved(_: *c.JNIEnv, _: c.jobject, id: c.jint) callconv(.c) void {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        if (joystick_map.fetchRemove(id)) |entry| {
            if (entry.value.joystick) |joystick| {
                joystick.mutex.lockUncancelable(internal.io);
                defer joystick.mutex.unlock(internal.io);

                joystick.removed = true;
            }
            entry.value.deinit();
            wio.cancelWait();
        }
    }

    fn onJoystickMotionEvent(_: *c.JNIEnv, _: c.jobject, id: c.jint, axis: c.jint, value: c.jfloat, min: c.jfloat, max: c.jfloat) callconv(.c) void {
        joystick_map_mutex.lockUncancelable(internal.io);
        defer joystick_map_mutex.unlock(internal.io);

        if (joystick_map.get(id)) |info| {
            if (info.joystick) |joystick| {
                joystick.mutex.lockUncancelable(internal.io);
                defer joystick.mutex.unlock(internal.io);

                if (std.sort.binarySearch(c.jint, info.axes, axis, compareInt)) |index| {
                    joystick.axes[index] = @trunc((value - min) / (max - min) * 0xFFFF);
                }

                wio.cancelWait();
            }
        }
    }

    fn onPermissionGranted(_: *c.JNIEnv, _: c.jobject) callconv(.c) void {
        audio_input_available = true;
    }
};

fn updateModifiers(button: wio.Button, value: bool) void {
    const modifier = switch (button) {
        .left_control, .right_control => &modifiers.control,
        .left_shift, .right_shift => &modifiers.shift,
        .left_alt, .right_alt => &modifiers.alt,
        else => return,
    };
    if (modifier.* != value) {
        modifier.* = value;
        internal.eventFn(event_fn_data, .{ .modifiers = modifiers });
    }
}

fn logUnexpectedEgl(name: []const u8) error{Unexpected} {
    logEglError(name);
    return error.Unexpected;
}

fn logEglError(name: []const u8) void {
    log.err("{s} failed, error 0x{X}", .{ name, c.eglGetError() });
}

const JoystickInfo = struct {
    descriptor: []const u8,
    name: []const u8,
    axes: []const c.jint,
    buttons: []const c.jint,
    joystick: ?*Joystick = null,

    fn init(env: *c.JNIEnv, descriptor_j: c.jstring, name_j: c.jstring, axes_j: c.jintArray, buttons_j: c.jintArray) !JoystickInfo {
        const descriptor_z = env.*.*.GetStringUTFChars.?(env, descriptor_j, null) orelse return error.Unexpected;
        defer env.*.*.ReleaseStringUTFChars.?(env, descriptor_j, descriptor_z);

        const name_z = env.*.*.GetStringUTFChars.?(env, name_j, null) orelse return error.Unexpected;
        defer env.*.*.ReleaseStringUTFChars.?(env, name_j, name_z);

        const axes_len = env.*.*.GetArrayLength.?(env, axes_j);
        if (axes_len < 0) return error.Unexpected;
        const axes_ptr = env.*.*.GetIntArrayElements.?(env, axes_j, null) orelse return error.Unexpected;
        defer env.*.*.ReleaseIntArrayElements.?(env, axes_j, axes_ptr, c.JNI_ABORT);

        var buttons_len = env.*.*.GetArrayLength.?(env, buttons_j);
        if (buttons_len < 0) return error.Unexpected;
        const buttons_ptr = env.*.*.GetIntArrayElements.?(env, buttons_j, null) orelse return error.Unexpected;
        defer env.*.*.ReleaseIntArrayElements.?(env, buttons_j, buttons_ptr, c.JNI_ABORT);
        if (std.mem.findScalar(c.jint, buttons_ptr[0..@intCast(buttons_len)], 0)) |index| {
            buttons_len = @intCast(index);
        }

        const descriptor = try internal.allocator.dupe(u8, std.mem.sliceTo(descriptor_z, 0));
        errdefer internal.allocator.free(descriptor);

        const name = try internal.allocator.dupe(u8, std.mem.sliceTo(name_z, 0));
        errdefer internal.allocator.free(name);

        const axes = try internal.allocator.dupe(c.jint, axes_ptr[0..@intCast(axes_len)]);
        errdefer internal.allocator.free(axes);
        std.mem.sortUnstable(c.jint, axes, {}, lessThanInt);

        const buttons = try internal.allocator.dupe(c.jint, buttons_ptr[0..@intCast(buttons_len)]);
        errdefer internal.allocator.free(buttons);

        return .{
            .descriptor = descriptor,
            .name = name,
            .axes = axes,
            .buttons = buttons,
        };
    }

    fn deinit(self: JoystickInfo) void {
        internal.allocator.free(self.buttons);
        internal.allocator.free(self.axes);
        internal.allocator.free(self.name);
        internal.allocator.free(self.descriptor);
    }
};

fn lessThanInt(_: void, lhs: c.jint, rhs: c.jint) bool {
    return lhs < rhs;
}

fn compareInt(lhs: c.jint, rhs: c.jint) std.math.Order {
    if (lhs > rhs) return .gt;
    if (lhs < rhs) return .lt;
    return .eq;
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

const std = @import("std");
const wio = @import("wio.zig");
const c = @cImport({
    @cInclude("IOKit/hid/IOHIDLib.h");
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioUnit/AudioUnit.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("OpenGL/OpenGL.h");
    @cInclude("mach-o/dyld.h");
});
const log = std.log.scoped(.wio);

extern fn wioInit() void;
extern fn wioRun() void;
extern fn wioLoop() void;
extern fn wioMessageBox(u8, [*]const u8, usize) void;
extern fn wioCreateWindow(*anyopaque, u16, u16) *anyopaque;
extern fn wioDestroyWindow(*anyopaque, ?*anyopaque) void;
extern fn wioSetTitle(*anyopaque, [*]const u8, usize) void;
extern fn wioSetMode(*anyopaque, u8) void;
extern fn wioSetCursor(*anyopaque, u8) void;
extern fn wioSetCursorMode(*anyopaque, u8) void;
extern fn wioRequestAttention() void;
extern fn wioSetClipboardText([*]const u8, usize) void;
extern fn wioGetClipboardText(*const anyopaque, *usize) ?[*]u8;
extern fn wioCreateContext(*anyopaque, [*]const c.CGLPixelFormatAttribute) ?*anyopaque;
extern fn wioMakeContextCurrent(?*anyopaque) void;
extern fn wioSwapBuffers(*anyopaque, ?*anyopaque) void;
extern fn wioSwapInterval(?*anyopaque, i32) void;
extern const wioHIDDeviceUsagePageKey: c.CFStringRef;
extern const wioHIDDeviceUsageKey: c.CFStringRef;
extern const wioHIDVendorIDKey: c.CFStringRef;
extern const wioHIDProductIDKey: c.CFStringRef;
extern const wioHIDVersionNumberKey: c.CFStringRef;
extern const wioHIDSerialNumberKey: c.CFStringRef;
extern const wioHIDProductKey: c.CFStringRef;

var hid: c.IOHIDManagerRef = undefined;
var removed_joysticks: std.AutoHashMap(c.IOHIDDeviceRef, bool) = undefined;

pub fn init(options: wio.InitOptions) !void {
    wioInit();

    if (options.joystick) {
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

        removed_joysticks = .init(wio.allocator);
        c.IOHIDManagerRegisterDeviceRemovalCallback(hid, joystickRemoved, null);
        if (wio.init_options.joystickConnectedFn != null) {
            c.IOHIDManagerRegisterDeviceMatchingCallback(hid, joystickConnected, null);
        }

        c.IOHIDManagerScheduleWithRunLoop(hid, c.CFRunLoopGetMain(), c.kCFRunLoopDefaultMode);
        try succeed(c.IOHIDManagerOpen(hid, c.kIOHIDOptionsTypeNone), "IOHIDManagerOpen");
    }
    errdefer if (options.joystick) c.CFRelease(hid);

    if (options.audio) {
        if (options.audioDefaultOutputFn) |callback| {
            const address = c.AudioObjectPropertyAddress{
                .mSelector = c.kAudioHardwarePropertyDefaultOutputDevice,
                .mScope = c.kAudioObjectPropertyScopeGlobal,
                .mElement = c.kAudioObjectPropertyElementMain,
            };
            var id: c.AudioObjectID = undefined;
            var size: u32 = @sizeOf(c.AudioObjectID);
            try succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultOutputDevice)");
            callback(.{ .backend = .{ .id = id } });
            try succeed(c.AudioObjectAddPropertyListener(c.kAudioObjectSystemObject, &address, defaultOutputChanged, null), "AddPropertyListener");
        }
        if (options.audioDefaultInputFn) |callback| {
            const address = c.AudioObjectPropertyAddress{
                .mSelector = c.kAudioHardwarePropertyDefaultInputDevice,
                .mScope = c.kAudioObjectPropertyScopeGlobal,
                .mElement = c.kAudioObjectPropertyElementMain,
            };
            var id: c.AudioObjectID = undefined;
            var size: u32 = @sizeOf(c.AudioObjectID);
            try succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultInputDevice)");
            callback(.{ .backend = .{ .id = id } });
            try succeed(c.AudioObjectAddPropertyListener(c.kAudioObjectSystemObject, &address, defaultInputChanged, null), "AddPropertyListener");
        }
    }
}

pub fn deinit() void {
    if (wio.init_options.joystick) {
        removed_joysticks.deinit();
        c.CFRelease(hid);
    }
}

pub fn run(func: fn () anyerror!bool) !void {
    wioRun();
    while (try func()) {
        wioLoop();
    }
}

pub fn messageBox(style: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    wioMessageBox(@intFromEnum(style), message.ptr, message.len);
}

events: std.fifo.LinearFifo(wio.Event, .Dynamic),
window: *anyopaque,
context: ?*anyopaque = null,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    self.events = .init(wio.allocator); // must be valid in wioCreateWindow
    self.* = .{
        .events = self.events,
        .window = wioCreateWindow(self, options.size.width, options.size.height),
    };
    self.setTitle(options.title);
    self.setMode(options.mode);
    self.setCursor(options.cursor);
    if (options.cursor_mode != .normal) self.setCursorMode(options.cursor_mode);
    return self;
}

pub fn destroy(self: *@This()) void {
    wioDestroyWindow(self.window, self.context);
    self.events.deinit();
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    wioSetTitle(self.window, title.ptr, title.len);
}

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    wioSetMode(self.window, @intFromEnum(mode));
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    wioSetCursor(self.window, @intFromEnum(shape));
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    wioSetCursorMode(self.window, @intFromEnum(mode));
}

pub fn requestAttention(_: *@This()) void {
    wioRequestAttention();
}

pub fn setClipboardText(_: *@This(), text: []const u8) void {
    wioSetClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(_: *@This(), allocator: std.mem.Allocator) ?[]u8 {
    var len: usize = undefined;
    const text = wioGetClipboardText(&allocator, &len) orelse return null;
    return text[0..len];
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    self.context = wioCreateContext(self.window, &.{
        c.kCGLPFAColorSize,     options.red_bits + options.green_bits + options.blue_bits,
        c.kCGLPFAAlphaSize,     options.alpha_bits,
        c.kCGLPFADepthSize,     options.depth_bits,
        c.kCGLPFAStencilSize,   options.stencil_bits,
        c.kCGLPFASampleBuffers, if (options.samples == 0) 0 else 1,
        c.kCGLPFASamples,       options.samples,
        if (options.doublebuffer)
            c.kCGLPFADoubleBuffer
        else
            0,
        0,
    });
}

pub fn makeContextCurrent(self: *@This()) void {
    wioMakeContextCurrent(self.context);
}

pub fn swapBuffers(self: *@This()) void {
    wioSwapBuffers(self.window, self.context);
}

pub fn swapInterval(self: *@This(), interval: i32) void {
    wioSwapInterval(self.context, interval);
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return if (c.NSLookupAndBindSymbol("_" ++ name)) |symbol| c.NSAddressOfSymbol(symbol) else null;
}

pub const JoystickDeviceIterator = struct {
    devices: []c.IOHIDDeviceRef = &.{},
    index: usize = 0,

    pub fn init() JoystickDeviceIterator {
        const set = c.IOHIDManagerCopyDevices(hid) orelse return .{};
        defer c.CFRelease(set);
        const len: usize = @intCast(c.CFSetGetCount(set));
        const devices = wio.allocator.alloc(c.IOHIDDeviceRef, len) catch return .{};
        c.CFSetGetValues(set, @ptrCast(devices.ptr));
        return .{ .devices = devices };
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        wio.allocator.free(self.devices);
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

        var axis_elements = std.ArrayList(c.IOHIDElementRef).init(wio.allocator);
        errdefer axis_elements.deinit();
        var hat_elements = std.ArrayList(c.IOHIDElementRef).init(wio.allocator);
        errdefer hat_elements.deinit();
        var button_elements = std.ArrayList(c.IOHIDElementRef).init(wio.allocator);
        errdefer button_elements.deinit();

        const count = c.CFArrayGetCount(elements);
        var i: c.CFIndex = 0;
        while (i < count) : (i += 1) {
            const element: c.IOHIDElementRef = @constCast(@ptrCast(c.CFArrayGetValueAtIndex(elements, i)));
            if (c.IOHIDElementGetType(element) == c.kIOHIDElementTypeInput_Button) {
                try button_elements.append(element);
            } else {
                const page = c.IOHIDElementGetUsagePage(element);
                const usage = c.IOHIDElementGetUsage(element);
                switch (page) {
                    c.kHIDPage_GenericDesktop => {
                        switch (usage) {
                            c.kHIDUsage_GD_Hatswitch => try hat_elements.append(element),
                            c.kHIDUsage_GD_X,
                            c.kHIDUsage_GD_Y,
                            c.kHIDUsage_GD_Z,
                            c.kHIDUsage_GD_Rx,
                            c.kHIDUsage_GD_Ry,
                            c.kHIDUsage_GD_Rz,
                            c.kHIDUsage_GD_Slider,
                            c.kHIDUsage_GD_Dial,
                            c.kHIDUsage_GD_Wheel,
                            => try axis_elements.append(element),
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }

        const axes = try wio.allocator.alloc(u16, axis_elements.items.len);
        errdefer wio.allocator.free(axes);
        const hats = try wio.allocator.alloc(wio.Hat, hat_elements.items.len);
        errdefer wio.allocator.free(hats);
        const buttons = try wio.allocator.alloc(bool, button_elements.items.len);
        errdefer wio.allocator.free(buttons);

        const axis_elements_slice = try axis_elements.toOwnedSlice();
        errdefer wio.allocator.free(axis_elements_slice);
        const hat_elements_slice = try hat_elements.toOwnedSlice();
        errdefer wio.allocator.free(hat_elements_slice);
        const button_elements_slice = try button_elements.toOwnedSlice();
        errdefer wio.allocator.free(button_elements_slice);

        try removed_joysticks.put(self.device, false);

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
        wio.allocator.free(self.buttons);
        wio.allocator.free(self.hats);
        wio.allocator.free(self.axes);
        wio.allocator.free(self.button_elements);
        wio.allocator.free(self.hat_elements);
        wio.allocator.free(self.axis_elements);
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
            axis.* = @intFromFloat(float);
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
        const address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioHardwarePropertyDevices,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        };
        var size: u32 = undefined;
        succeed(c.AudioObjectGetPropertyDataSize(c.kAudioObjectSystemObject, &address, 0, null, &size), "GetPropertySize(Devices)") catch return .{};
        const devices = wio.allocator.alloc(c.AudioObjectID, size / @sizeOf(c.AudioObjectID)) catch return .{};
        succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, devices.ptr), "GetProperty(Devices)") catch return .{};
        return .{ .devices = devices, .mode = mode };
    }

    pub fn deinit(self: *AudioDeviceIterator) void {
        wio.allocator.free(self.devices);
    }

    pub fn next(self: *AudioDeviceIterator) ?AudioDevice {
        if (self.index == self.devices.len) return null;

        const id = self.devices[self.index];
        self.index += 1;

        var address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioDevicePropertyStreams,
            .mScope = if (self.mode == .output) c.kAudioDevicePropertyScopeOutput else c.kAudioDevicePropertyScopeInput,
            .mElement = c.kAudioObjectPropertyElementMain,
        };
        var size: u32 = undefined;
        _ = c.AudioObjectGetPropertyDataSize(id, &address, 0, null, &size);
        if (size == 0) return self.next();

        return .{ .id = id };
    }
};

pub const AudioDevice = struct {
    id: c.AudioObjectID,

    pub fn release(_: AudioDevice) void {}

    pub fn openOutput(self: AudioDevice, writeFn: *const fn ([]f32) void, format: wio.AudioFormat) !AudioOutput {
        const component_desc = c.AudioComponentDescription{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        };
        const component = c.AudioComponentFindNext(null, &component_desc);
        var unit: c.AudioComponentInstance = undefined;
        try succeed(c.AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew");
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_CurrentDevice, c.kAudioUnitScope_Global, 0, &self.id, @sizeOf(c.AudioDeviceID)), "SetProperty(CurrentDevice)");

        const stream_desc = c.AudioStreamBasicDescription{
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

        const callback = c.AURenderCallbackStruct{
            .inputProc = AudioOutput.callback,
            .inputProcRefCon = @constCast(writeFn),
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioUnitProperty_SetRenderCallback, c.kAudioUnitScope_Global, 0, &callback, @sizeOf(c.AURenderCallbackStruct)), "SetProperty(RenderCallback)");
        try succeed(c.AudioUnitInitialize(unit), "AudioUnitInitialize");
        try succeed(c.AudioOutputUnitStart(unit), "AudioOutputUnitStart");
        return .{ .unit = unit };
    }

    pub fn openInput(self: AudioDevice, readFn: *const fn ([]const f32) void, format: wio.AudioFormat) !*AudioInput {
        const component_desc = c.AudioComponentDescription{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        };
        const component = c.AudioComponentFindNext(null, &component_desc);
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
        var source_format = c.AudioStreamBasicDescription{
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

        const input = try wio.allocator.create(AudioInput);
        errdefer wio.allocator.destroy(input);
        input.* = .{
            .unit = unit,
            .converter = converter,
            .readFn = readFn,
        };
        const callback = c.AURenderCallbackStruct{
            .inputProc = AudioInput.callback,
            .inputProcRefCon = input,
        };
        try succeed(c.AudioUnitSetProperty(unit, c.kAudioOutputUnitProperty_SetInputCallback, c.kAudioUnitScope_Global, 0, &callback, @sizeOf(c.AURenderCallbackStruct)), "SetProperty(InputCallback)");
        try succeed(c.AudioUnitInitialize(unit), "AudioUnitInitialize");
        try succeed(c.AudioOutputUnitStart(unit), "AudioOutputUnitStart");
        return input;
    }

    pub fn getId(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        const address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioDevicePropertyDeviceUID,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        };
        var string: c.CFStringRef = undefined;
        var size: u32 = @sizeOf(c.CFStringRef);
        try succeed(c.AudioObjectGetPropertyData(self.id, &address, 0, null, &size, @ptrCast(&string)), "GetProperty(DeviceUID)");
        defer c.CFRelease(string);
        return cfStringToUtf8(allocator, string);
    }

    pub fn getName(self: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        const address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioObjectPropertyName,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        };
        var string: c.CFStringRef = undefined;
        var size: u32 = @sizeOf(c.CFStringRef);
        try succeed(c.AudioObjectGetPropertyData(self.id, &address, 0, null, &size, @ptrCast(&string)), "GetProperty(Name)");
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
        const writeFn: *const fn ([]f32) void = @alignCast(@ptrCast(data));
        const buffer = list.*.mBuffers[0];
        const ptr: [*]f32 = @alignCast(@ptrCast(buffer.mData));
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
        wio.allocator.destroy(self);
    }

    fn callback(data: ?*anyopaque, flags: [*c]c.AudioUnitRenderActionFlags, timestamp: [*c]const c.AudioTimeStamp, bus: u32, frames: u32, _: [*c]c.AudioBufferList) callconv(.c) c.OSStatus {
        const self: *AudioInput = @alignCast(@ptrCast(data));

        var list = c.AudioBufferList{
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
            var output = c.AudioBufferList{
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
        const buffer: *c.AudioBuffer = @alignCast(@ptrCast(data));
        list.*.mBuffers[0] = buffer.*;
        packets.* = buffer.mDataByteSize / buffer.mNumberChannels / @sizeOf(f32);
        return c.noErr;
    }
};

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch {};
}

export fn wioClose(self: *@This()) void {
    self.pushEvent(.close);
}

export fn wioFocus(self: *@This()) void {
    self.pushEvent(.focused);
}

export fn wioUnfocus(self: *@This()) void {
    self.pushEvent(.unfocused);
}

export fn wioSize(self: *@This(), mode: u8, width: u16, height: u16, fb_width: u16, fb_height: u16) void {
    self.pushEvent(.{ .mode = @enumFromInt(mode) });
    self.pushEvent(.{ .size = .{ .width = width, .height = height } });
    self.pushEvent(.{ .framebuffer = .{ .width = fb_width, .height = fb_height } });
}

export fn wioScale(self: *@This(), scale: f32) void {
    self.pushEvent(.{ .scale = scale });
}

export fn wioChars(self: *@This(), buf: [*:0]const u8) void {
    const view = std.unicode.Utf8View.init(std.mem.sliceTo(buf, 0)) catch return;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        if (codepoint >= ' ' and codepoint != 0x7F and (codepoint < 0xF700 or codepoint > 0xF7FF)) {
            self.pushEvent(.{ .char = codepoint });
        }
    }
}

export fn wioKey(self: *@This(), key: u16, event: u8) void {
    if (keycodeToButton(key)) |button| {
        switch (event) {
            0 => self.pushEvent(.{ .button_press = button }),
            1 => self.pushEvent(.{ .button_repeat = button }),
            2 => self.pushEvent(.{ .button_release = button }),
            else => unreachable,
        }
    }
}

export fn wioButtonPress(self: *@This(), button: u8) void {
    self.pushEvent(.{ .button_press = @enumFromInt(button) });
}

export fn wioButtonRelease(self: *@This(), button: u8) void {
    self.pushEvent(.{ .button_release = @enumFromInt(button) });
}

export fn wioMouse(self: *@This(), x: u16, y: u16) void {
    self.pushEvent(.{ .mouse = .{ .x = x, .y = y } });
}

export fn wioMouseRelative(self: *@This(), x: i16, y: i16) void {
    self.pushEvent(.{ .mouse_relative = .{ .x = x, .y = y } });
}

export fn wioScroll(self: *@This(), x: f32, y: f32) void {
    if (x != 0) self.pushEvent(.{ .scroll_horizontal = x });
    if (y != 0) self.pushEvent(.{ .scroll_vertical = -y });
}

export fn wioDupeClipboardText(allocator: *const std.mem.Allocator, bytes: [*:0]const u8, len: *usize) ?[*]u8 {
    const slice = std.mem.sliceTo(bytes, 0);
    if (allocator.dupe(u8, slice)) |dupe| {
        len.* = dupe.len;
        return dupe.ptr;
    } else |_| {
        return null;
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

fn joystickConnected(_: ?*anyopaque, _: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    wio.init_options.joystickConnectedFn.?(.{ .backend = .{ .device = device } });
}

fn joystickRemoved(_: ?*anyopaque, _: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    if (removed_joysticks.getPtr(device)) |removed| removed.* = true;
}

fn defaultOutputChanged(_: c.AudioObjectID, _: u32, _: [*c]const c.AudioObjectPropertyAddress, _: ?*anyopaque) callconv(.c) c.OSStatus {
    const address = c.AudioObjectPropertyAddress{
        .mSelector = c.kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    };
    var id: c.AudioObjectID = undefined;
    var size: u32 = @sizeOf(c.AudioObjectID);
    succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultOutputDevice)") catch return c.noErr;
    wio.init_options.audioDefaultOutputFn.?(.{ .backend = .{ .id = id } });
    return c.noErr;
}

fn defaultInputChanged(_: c.AudioObjectID, _: u32, _: [*c]const c.AudioObjectPropertyAddress, _: ?*anyopaque) callconv(.c) c.OSStatus {
    const address = c.AudioObjectPropertyAddress{
        .mSelector = c.kAudioHardwarePropertyDefaultInputDevice,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    };
    var id: c.AudioObjectID = undefined;
    var size: u32 = @sizeOf(c.AudioObjectID);
    succeed(c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &id), "GetProperty(DefaultInputDevice)") catch return c.noErr;
    wio.init_options.audioDefaultInputFn.?(.{ .backend = .{ .id = id } });
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

const std = @import("std");
const build_options = @import("build_options");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

extern "root" fn get_image_symbol(u32, [*:0]const u8, i32, *?*const anyopaque) std.c.status_t;

const BWindow = opaque {};
const BBitmap = opaque {};
const BGLView = opaque {};
const BJoystick = opaque {};
const BSoundPlayer = opaque {};
extern fn wioInit() void;
extern fn wioMessageBox(u8, [*:0]const u8, [*:0]const u8) void;
extern fn wioOpenUri([*:0]const u8) void;
extern fn wioGetModifiers() u32;
extern fn wioCreateWindow(*Window, [*:0]const u8, u16, u16) *BWindow;
extern fn wioDestroyWindow(*BWindow) void;
extern fn wioSetTitle(*BWindow, [*:0]const u8) void;
extern fn wioSetSize(*BWindow, f32, f32) void;
extern fn wioSetCursor(u8) void;
extern fn wioSetClipboardText([*]const u8, usize) void;
extern fn wioGetClipboardText(*usize) ?[*]const u8;
extern fn wioCreateFramebuffer(u16, u16) Framebuffer;
extern fn wioFramebufferDestroy(*BBitmap) void;
extern fn wioPresentFramebuffer(*BWindow, *BBitmap) void;
extern fn wioGlCreateContext(*BWindow, bool, bool, bool, bool) *BGLView;
extern fn wioGlMakeContextCurrent(*BGLView) void;
extern fn wioGlSwapBuffers(bool) void;
extern fn wioJoystickIteratorInit(*i32) *BJoystick;
extern fn wioJoystickIteratorDeinit(*BJoystick) void;
extern fn wioJoystickIteratorNext(*BJoystick, i32, [*]u8) void;
extern fn wioJoystickOpen([*]const u8, *i32, *i32, *i32) ?*BJoystick;
extern fn wioJoystickClose(*BJoystick) void;
extern fn wioJoystickPoll(*BJoystick, [*]u16, [*]wio.Hat, *u32) bool;
extern fn wioAudioOutputOpen(u32, u8, *const anyopaque) ?*BSoundPlayer;
extern fn wioAudioOutputClose(*BSoundPlayer) void;

export var wio_scale: f32 = undefined;

var libGL: u32 = undefined;

pub fn init() !void {
    wioInit();

    if (build_options.opengl) blk: {
        var info: std.c.image_info = undefined;
        var cookie: i32 = 0;
        while (std.c._get_next_image_info(0, &cookie, &info, @sizeOf(std.c.image_info)) == 0) {
            const name = std.mem.sliceTo(&info.name, 0);
            if (std.mem.indexOf(u8, name, "/libGL.so") != null) {
                libGL = info.id;
                break :blk;
            }
        }
        return error.Unexpected;
    }

    if (build_options.joystick) {
        if (internal.init_options.joystickConnectedFn) |callback| {
            var iter = wio.JoystickDeviceIterator.init();
            defer iter.deinit();
            while (iter.next()) |device| callback(device);
        }
    }

    if (build_options.audio) {
        if (internal.init_options.audioDefaultOutputFn) |callback| {
            callback(.{ .backend = .{} });
        }
    }
}

pub fn deinit() void {}

pub fn run(func: fn () anyerror!bool) !void {
    while (try func()) {}
}

pub fn update() void {}

var wait_event: std.Io.Event = .unset;

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
    const title_z = internal.allocator.dupeZ(u8, title) catch return;
    defer internal.allocator.free(title_z);
    const message_z = internal.allocator.dupeZ(u8, message) catch return;
    defer internal.allocator.free(message_z);
    wioMessageBox(@intFromEnum(style), title_z, message_z);
}

pub fn openUri(uri: []const u8) void {
    const uri_z = internal.allocator.dupeZ(u8, uri) catch return;
    defer internal.allocator.free(uri_z);
    wioOpenUri(uri_z);
}

pub fn getModifiers() wio.Modifiers {
    const modifiers = wioGetModifiers();
    return .{
        .control = (modifiers & (1 << 2) != 0),
        .shift = (modifiers & (1 << 0) != 0),
        .alt = (modifiers & (1 << 1) != 0),
        .gui = (modifiers & (1 << 6) != 0),
    };
}

pub fn createWindow(options: wio.CreateWindowOptions) !*Window {
    const self = try internal.allocator.create(Window);
    errdefer internal.allocator.destroy(self);
    self.* = .{
        .window = undefined,
        .events = .init(),
    };

    const size = if (options.scale) |base| options.size.multiply(wio_scale / base) else options.size;

    self.events.push(.visible);
    self.events.push(.{ .scale = wio_scale });
    self.events.push(.{ .mode = .normal });
    self.events.push(.{ .size_logical = size });
    self.events.push(.{ .size_physical = size });
    self.events.push(.draw);

    const title = try internal.allocator.dupeZ(u8, options.title);
    defer internal.allocator.free(title);
    self.window = wioCreateWindow(self, title, size.width, size.height);

    return self;
}

pub const Window = struct {
    window: *BWindow,
    events: internal.EventQueue,
    events_mutex: std.Io.Mutex = .init,
    buttons: std.StaticBitSet(5) = .initEmpty(),
    text: bool = false,
    cursor: wio.Cursor = .default,
    drop: if (build_options.drop) struct {
        files: std.ArrayList([]const u8) = .empty,
        text: ?[]const u8 = null,
    } else struct {} = .{},
    opengl: if (build_options.opengl) struct {
        vsync: bool = false,
    } else struct {} = .{},

    pub fn destroy(self: *Window) void {
        if (build_options.drop) {
            for (self.drop.files.items) |file| internal.allocator.free(file);
            self.drop.files.deinit(internal.allocator);
            if (self.drop.text) |text| internal.allocator.free(text);
        }
        wioDestroyWindow(self.window);
        self.events.deinit();
        internal.allocator.destroy(self);
    }

    pub fn getEvent(self: *Window) ?wio.Event {
        self.events_mutex.lockUncancelable(internal.io);
        defer self.events_mutex.unlock(internal.io);
        return self.events.pop();
    }

    pub fn enableTextInput(self: *Window, _: wio.TextInputOptions) void {
        self.text = true;
    }

    pub fn disableTextInput(self: *Window) void {
        self.text = false;
    }

    pub fn enableRelativeMouse(self: *Window) void {
        _ = self;
    }

    pub fn disableRelativeMouse(self: *Window) void {
        _ = self;
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        const title_z = internal.allocator.dupeZ(u8, title) catch return;
        defer internal.allocator.free(title_z);
        wioSetTitle(self.window, title_z);
    }

    pub fn setMode(self: *Window, mode: wio.WindowMode) void {
        _ = self;
        _ = mode;
    }

    pub fn setSize(self: *Window, size: wio.Size) void {
        wioSetSize(self.window, @floatFromInt(size.width), @floatFromInt(size.height));
    }

    pub fn setParent(_: *Window, _: usize) void {}

    pub fn setCursor(self: *Window, shape: wio.Cursor) void {
        self.cursor = shape;
        wioSetCursor(@intFromEnum(shape));
    }

    pub fn requestAttention(_: *Window) void {}

    pub fn setClipboardText(_: *Window, text: []const u8) void {
        wioSetClipboardText(text.ptr, text.len);
    }

    pub fn getClipboardText(_: *Window, allocator: std.mem.Allocator) ?[]u8 {
        var len: usize = undefined;
        const ptr = wioGetClipboardText(&len) orelse return null;
        return allocator.dupe(u8, ptr[0..len]) catch return null;
    }

    pub fn getDropData(self: *Window, allocator: std.mem.Allocator) wio.DropData {
        return wio.DropData.dupe(allocator, self.drop.files.items, self.drop.text) catch .{ .files = &.{}, .text = null };
    }

    pub fn createFramebuffer(_: *Window, size: wio.Size) !Framebuffer {
        return wioCreateFramebuffer(size.width, size.height);
    }

    pub fn presentFramebuffer(self: *Window, framebuffer: *Framebuffer) void {
        wioPresentFramebuffer(self.window, framebuffer.bitmap);
    }

    pub fn glCreateContext(self: *Window, options: wio.GlCreateContextOptions) !GlContext {
        return .{
            .view = if (options.share == null)
                wioGlCreateContext(self.window, options.options.doublebuffer, (options.options.alpha_bits > 0), (options.options.depth_bits > 0), (options.options.stencil_bits > 0))
            else
                return error.UnsupportedContextOptions,
        };
    }

    pub fn glMakeContextCurrent(_: *Window, context: GlContext) void {
        wioGlMakeContextCurrent(context.view);
    }

    pub fn glSwapBuffers(self: *Window) void {
        wioGlSwapBuffers(self.opengl.vsync);
    }

    pub fn glSwapInterval(self: *Window, interval: i32) void {
        self.opengl.vsync = (interval > 0);
    }

    fn pushEvent(self: *Window, event: wio.Event) void {
        self.events_mutex.lockUncancelable(internal.io);
        defer self.events_mutex.unlock(internal.io);
        self.events.push(event);
        wait_event.set(internal.io);
    }
};

pub const Framebuffer = extern struct {
    bitmap: *BBitmap,
    bits: [*]u8,
    bytes_per_row: u32,

    pub fn destroy(self: *Framebuffer) void {
        wioFramebufferDestroy(self.bitmap);
    }

    pub fn setPixel(self: *Framebuffer, x: usize, y: usize, rgb: u32) void {
        const index = (y * self.bytes_per_row) + (x * @sizeOf(u32));
        std.mem.writeInt(u32, self.bits[index..][0..4], rgb, .little);
    }
};

pub const GlContext = struct {
    view: *BGLView,

    pub fn destroy(_: GlContext) void {}
};

pub fn glGetProcAddress(name: [*:0]const u8) ?*const anyopaque {
    var location: ?*const anyopaque = undefined;
    return if (get_image_symbol(libGL, name, 0x2, &location) == 0)
        location
    else
        null;
}

pub const JoystickDeviceIterator = struct {
    handle: *BJoystick,
    count: i32,
    index: i32 = 0,

    pub fn init() JoystickDeviceIterator {
        var count: i32 = undefined;
        const handle = wioJoystickIteratorInit(&count);
        return .{ .handle = handle, .count = count };
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        wioJoystickIteratorDeinit(self.handle);
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.index == self.count) return null;
        defer self.index += 1;

        var device = JoystickDevice{ .name = undefined };
        wioJoystickIteratorNext(self.handle, self.index, &device.name);
        return device;
    }
};

pub const JoystickDevice = struct {
    name: [32]u8, // B_OS_NAME_LENGTH

    pub fn release(_: JoystickDevice) void {}

    pub fn open(self: JoystickDevice) !Joystick {
        var axis_count: i32 = undefined;
        var hat_count: i32 = undefined;
        var button_count: i32 = undefined;
        const handle = wioJoystickOpen(&self.name, &axis_count, &hat_count, &button_count) orelse return error.Unexpected;
        errdefer wioJoystickClose(handle);
        const axes = try internal.allocator.alloc(u16, @intCast(axis_count));
        errdefer internal.allocator.free(axes);
        const hats = try internal.allocator.alloc(wio.Hat, @intCast(hat_count));
        errdefer internal.allocator.free(hats);
        const buttons = try internal.allocator.alloc(bool, @intCast(button_count));
        errdefer internal.allocator.free(buttons);
        return .{ .handle = handle, .axes = axes, .hats = hats, .buttons = buttons };
    }

    pub fn getId(_: JoystickDevice, _: std.mem.Allocator) ![]u8 {
        return error.Unexpected;
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, std.mem.sliceTo(&self.name, 0));
    }
};

pub const Joystick = struct {
    handle: *BJoystick,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        internal.allocator.free(self.buttons);
        internal.allocator.free(self.hats);
        internal.allocator.free(self.axes);
        wioJoystickClose(self.handle);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        var buttons: u32 = undefined;
        if (!wioJoystickPoll(self.handle, self.axes.ptr, self.hats.ptr, &buttons)) return null;
        for (self.hats) |*hat| {
            const value: *u8 = @ptrCast(hat);
            hat.* = switch (value.*) {
                0 => .{},
                1 => .{ .up = true },
                2 => .{ .up = true, .right = true },
                3 => .{ .right = true },
                4 => .{ .right = true, .down = true },
                5 => .{ .down = true },
                6 => .{ .down = true, .left = true },
                7 => .{ .left = true },
                8 => .{ .left = true, .up = true },
                else => .{},
            };
        }
        for (self.buttons, 0..) |*button, i| {
            const mask = @as(u32, 1) << @intCast(i);
            button.* = (buttons & mask != 0);
        }
        return .{ .axes = self.axes, .hats = self.hats, .buttons = self.buttons };
    }
};

pub const AudioDeviceIterator = struct {
    used: bool,

    pub fn init(mode: wio.AudioDeviceType) AudioDeviceIterator {
        return if (mode == .output)
            .{ .used = false }
        else
            .{ .used = true };
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
        return .{ .handle = wioAudioOutputOpen(format.sample_rate, format.channels, writeFn) orelse return error.Unexpected };
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

    pub fn getName(_: AudioDevice, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, "BSoundPlayer");
    }
};

pub const AudioOutput = struct {
    handle: *BSoundPlayer,

    pub fn close(self: *AudioOutput) void {
        wioAudioOutputClose(self.handle);
    }
};

pub const AudioInput = struct {
    pub fn close(self: *AudioInput) void {
        _ = self;
    }
};

export fn wioClose(self: *Window) void {
    self.pushEvent(.close);
}

export fn wioFocused(self: *Window) void {
    self.pushEvent(.focused);
    wioSetCursor(@intFromEnum(self.cursor));
}

export fn wioUnfocused(self: *Window) void {
    self.pushEvent(.unfocused);
}

export fn wioVisible(self: *Window) void {
    self.pushEvent(.visible);
}

export fn wioHidden(self: *Window) void {
    self.pushEvent(.hidden);
}

export fn wioSize(self: *Window, width: u16, height: u16) void {
    self.pushEvent(.{ .size_logical = .{ .width = width, .height = height } });
    self.pushEvent(.{ .size_physical = .{ .width = width, .height = height } });
    self.pushEvent(.draw);
}

export fn wioChars(self: *Window, chars: [*:0]const u8) void {
    if (self.text) {
        const view = std.unicode.Utf8View.init(std.mem.sliceTo(chars, 0)) catch return;
        var iter = view.iterator();
        while (iter.nextCodepoint()) |char| {
            if (char >= ' ' and char != 0x7F) {
                self.pushEvent(.{ .char = char });
            }
        }
    }
}

export fn wioKey(self: *Window, key: i32, event: u8) void {
    if (keyToButton(key)) |button| {
        self.pushEvent(
            switch (event) {
                0 => .{ .button_press = button },
                1 => .{ .button_repeat = button },
                2 => .{ .button_release = button },
                else => unreachable,
            },
        );
    }
}

export fn wioButtons(self: *Window, buttons: u8) void {
    const changes = self.buttons.xorWith(.{ .mask = @truncate(buttons) });
    var iter = changes.iterator(.{});
    while (iter.next()) |i| {
        if (self.buttons.isSet(i)) {
            self.pushEvent(.{ .button_release = @enumFromInt(i) });
        } else {
            self.pushEvent(.{ .button_press = @enumFromInt(i) });
        }
    }
    self.buttons = self.buttons.xorWith(changes);
}

export fn wioMouse(self: *Window, x: u16, y: u16) void {
    self.pushEvent(.{ .mouse = .{ .x = x, .y = y } });
}

export fn wioScroll(self: *Window, vertical: f32, horizontal: f32) void {
    if (vertical != 0) self.pushEvent(.{ .scroll_vertical = vertical });
    if (horizontal != 0) self.pushEvent(.{ .scroll_horizontal = horizontal });
}

fn wioDropBegin(self: *Window) callconv(.c) void {
    for (self.drop.files.items) |f| internal.allocator.free(f);
    self.drop.files.clearRetainingCapacity();
    if (self.drop.text) |t| internal.allocator.free(t);
    self.drop.text = null;
    self.pushEvent(.drop_begin);
}

fn wioDropPosition(self: *Window, x: u16, y: u16) callconv(.c) void {
    self.pushEvent(.{ .drop_position = .{ .x = x, .y = y } });
}

fn wioDropFile(self: *Window, ptr: [*:0]const u8) callconv(.c) void {
    const path = internal.allocator.dupe(u8, std.mem.sliceTo(ptr, 0)) catch return;
    self.drop.files.append(internal.allocator, path) catch {
        internal.allocator.free(path);
    };
}

fn wioDropText(self: *Window, ptr: [*]const u8, len: usize) callconv(.c) void {
    if (self.drop.text) |t| internal.allocator.free(t);
    self.drop.text = internal.allocator.dupe(u8, ptr[0..len]) catch null;
}

fn wioDropComplete(self: *Window) callconv(.c) void {
    self.pushEvent(.drop_complete);
}

fn wioAudioOutputWrite(data: *const anyopaque, buffer: [*]f32, size: usize) callconv(.c) void {
    const writeFn: *const fn ([]f32) void = @ptrCast(@alignCast(data));
    writeFn(buffer[0 .. size / @sizeOf(f32)]);
}

comptime {
    if (build_options.drop) {
        @export(&wioDropBegin, .{ .name = "wioDropBegin" });
        @export(&wioDropPosition, .{ .name = "wioDropPosition" });
        @export(&wioDropFile, .{ .name = "wioDropFile" });
        @export(&wioDropText, .{ .name = "wioDropText" });
        @export(&wioDropComplete, .{ .name = "wioDropComplete" });
    }
    if (build_options.audio) {
        @export(&wioAudioOutputWrite, .{ .name = "wioAudioOutputWrite" });
    }
}

fn keyToButton(key: i32) ?wio.Button {
    comptime var table: [0x7F]wio.Button = undefined;
    comptime for (&table, 1..) |*ptr, i| {
        ptr.* = switch (i) {
            0x1 => .escape,
            0x2 => .f1,
            0x3 => .f2,
            0x4 => .f3,
            0x5 => .f4,
            0x6 => .f5,
            0x7 => .f6,
            0x8 => .f7,
            0x9 => .f8,
            0xA => .f9,
            0xB => .f10,
            0xC => .f11,
            0xD => .f12,
            0xE => .print_screen,
            0xF => .scroll_lock,
            0x10 => .pause,
            0x11 => .grave,
            0x12 => .@"1",
            0x13 => .@"2",
            0x14 => .@"3",
            0x15 => .@"4",
            0x16 => .@"5",
            0x17 => .@"6",
            0x18 => .@"7",
            0x19 => .@"8",
            0x1A => .@"9",
            0x1B => .@"0",
            0x1C => .minus,
            0x1D => .equals,
            0x1E => .backspace,
            0x1F => .insert,
            0x20 => .home,
            0x21 => .page_up,
            0x22 => .num_lock,
            0x23 => .kp_slash,
            0x24 => .kp_star,
            0x25 => .kp_minus,
            0x26 => .tab,
            0x27 => .q,
            0x28 => .w,
            0x29 => .e,
            0x2A => .r,
            0x2B => .t,
            0x2C => .y,
            0x2D => .u,
            0x2E => .i,
            0x2F => .o,
            0x30 => .p,
            0x31 => .left_bracket,
            0x32 => .right_bracket,
            0x33 => .backslash,
            0x34 => .delete,
            0x35 => .end,
            0x36 => .page_down,
            0x37 => .kp_7,
            0x38 => .kp_8,
            0x39 => .kp_9,
            0x3A => .kp_plus,
            0x3B => .caps_lock,
            0x3C => .a,
            0x3D => .s,
            0x3E => .d,
            0x3F => .f,
            0x40 => .g,
            0x41 => .h,
            0x42 => .j,
            0x43 => .k,
            0x44 => .l,
            0x45 => .semicolon,
            0x46 => .apostrophe,
            0x47 => .enter,
            0x48 => .kp_4,
            0x49 => .kp_5,
            0x4A => .kp_6,
            0x4B => .left_shift,
            0x4C => .z,
            0x4D => .x,
            0x4E => .c,
            0x4F => .v,
            0x50 => .b,
            0x51 => .n,
            0x52 => .m,
            0x53 => .comma,
            0x54 => .dot,
            0x55 => .slash,
            0x56 => .right_shift,
            0x57 => .up,
            0x58 => .kp_1,
            0x59 => .kp_2,
            0x5A => .kp_3,
            0x5B => .kp_enter,
            0x5C => .left_control,
            0x5D => .left_alt,
            0x5E => .space,
            0x5F => .right_alt,
            0x60 => .right_control,
            0x61 => .left,
            0x62 => .down,
            0x63 => .right,
            0x64 => .kp_0,
            0x65 => .kp_dot,
            0x66 => .left_gui,
            0x67 => .right_gui,
            0x68 => .application,
            0x69 => .iso_backslash,
            0x6A => .kp_equals,
            0x7E => .print_screen, // sysrq
            0x7F => .pause, // break
            else => .mouse_left,
        };
    };
    return if (key > 0 and key <= table.len and table[@intCast(key - 1)] != .mouse_left) table[@intCast(key - 1)] else null;
}

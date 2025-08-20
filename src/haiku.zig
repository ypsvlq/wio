const std = @import("std");
const build_options = @import("build_options");
const wio = @import("wio.zig");
const internal = @import("wio.internal.zig");
const log = std.log.scoped(.wio);

extern "root" fn get_image_symbol(u32, [*:0]const u8, i32, *?*const anyopaque) std.c.status_t;

const BWindow = opaque {};
const BGLView = opaque {};
const BJoystick = opaque {};
const BSoundPlayer = opaque {};
extern fn wioInit() void;
extern fn wioMessageBox(u8, [*:0]const u8, [*:0]const u8) void;
extern fn wioCreateWindow(*@This(), [*:0]const u8, u16, u16) *BWindow;
extern fn wioDestroyWindow(*BWindow) void;
extern fn wioSetTitle(*BWindow, [*:0]const u8) void;
extern fn wioSetSize(*BWindow, f32, f32) void;
extern fn wioSetClipboardText([*]const u8, usize) void;
extern fn wioGetClipboardText(*usize) ?[*]const u8;
extern fn wioCreateContext(*BWindow, bool, bool, bool, bool) *BGLView;
extern fn wioMakeContextCurrent(*BGLView) void;
extern fn wioSwapBuffers(bool) void;
extern fn wioJoystickIteratorInit(*i32) *BJoystick;
extern fn wioJoystickIteratorDeinit(*BJoystick) void;
extern fn wioJoystickIteratorNext(*BJoystick, i32, [*]u8) void;
extern fn wioJoystickOpen([*]const u8, *i32, *i32, *i32) ?*BJoystick;
extern fn wioJoystickClose(*BJoystick) void;
extern fn wioJoystickPoll(*BJoystick, [*]u16, [*]wio.Hat, *u32) bool;
extern fn wioAudioOutputOpen(u32, u8, *const anyopaque) ?*BSoundPlayer;
extern fn wioAudioOutputClose(*BSoundPlayer) void;

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

var wait_event: std.Thread.ResetEvent = .{};

pub fn wait() void {
    wait_event.reset();
    wait_event.wait();
}

pub fn messageBox(style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    const title_z = internal.allocator.dupeZ(u8, title) catch return;
    defer internal.allocator.free(title_z);
    const message_z = internal.allocator.dupeZ(u8, message) catch return;
    defer internal.allocator.free(message_z);
    wioMessageBox(@intFromEnum(style), title_z, message_z);
}

window: *BWindow,
events: internal.EventQueue,
events_mutex: std.Thread.Mutex = .{},
buttons: std.StaticBitSet(5) = .initEmpty(),
opengl: if (build_options.opengl) struct { context: ?*BGLView = null, vsync: bool = false } else struct {} = .{},

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try internal.allocator.create(@This());
    self.* = .{
        .window = undefined,
        .events = .init(),
    };

    self.events.push(.visible);
    self.events.push(.{ .scale = 1 });
    self.events.push(.{ .mode = .normal });
    self.events.push(.{ .size = options.size });
    self.events.push(.{ .framebuffer = options.size });
    self.events.push(.draw);

    const title = try internal.allocator.dupeZ(u8, options.title);
    defer internal.allocator.free(title);
    self.window = wioCreateWindow(self, title, options.size.width, options.size.height);

    if (build_options.opengl) {
        if (options.opengl) |opengl| {
            self.opengl.context = wioCreateContext(self.window, opengl.doublebuffer, (opengl.alpha_bits > 0), (opengl.depth_bits > 0), (opengl.stencil_bits > 0));
        }
    }

    return self;
}

pub fn destroy(self: *@This()) void {
    wioDestroyWindow(self.window);
    self.events.deinit();
    internal.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    self.events_mutex.lock();
    defer self.events_mutex.unlock();
    return self.events.pop();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_z = internal.allocator.dupeZ(u8, title) catch return;
    defer internal.allocator.free(title_z);
    wioSetTitle(self.window, title_z);
}

pub fn setMode(self: *@This(), mode: wio.WindowMode) void {
    _ = self;
    _ = mode;
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    _ = self;
    _ = shape;
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    _ = self;
    _ = mode;
}

pub fn setSize(self: *@This(), size: wio.Size) void {
    wioSetSize(self.window, @floatFromInt(size.width), @floatFromInt(size.height));
}

pub fn setParent(_: *@This(), _: usize) void {}

pub fn requestAttention(_: *@This()) void {}

pub fn setClipboardText(_: *@This(), text: []const u8) void {
    wioSetClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(_: *@This(), allocator: std.mem.Allocator) ?[]u8 {
    var len: usize = undefined;
    const ptr = wioGetClipboardText(&len) orelse return null;
    return allocator.dupe(u8, ptr[0..len]) catch return null;
}

pub fn makeContextCurrent(self: *@This()) void {
    wioMakeContextCurrent(self.opengl.context.?);
}

pub fn swapBuffers(self: *@This()) void {
    wioSwapBuffers(self.opengl.vsync);
}

pub fn swapInterval(self: *@This(), interval: i32) void {
    self.opengl.vsync = (interval > 0);
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
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

        var device: JoystickDevice = .{ .name = undefined };
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

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events_mutex.lock();
    defer self.events_mutex.unlock();
    self.events.push(event);
    wait_event.set();
}

export fn wioClose(self: *@This()) void {
    self.pushEvent(.close);
}

export fn wioFocused(self: *@This()) void {
    self.pushEvent(.focused);
}

export fn wioUnfocused(self: *@This()) void {
    self.pushEvent(.unfocused);
}

export fn wioVisible(self: *@This()) void {
    self.pushEvent(.visible);
}

export fn wioHidden(self: *@This()) void {
    self.pushEvent(.hidden);
}

export fn wioSize(self: *@This(), width: u16, height: u16) void {
    self.pushEvent(.{ .size = .{ .width = width, .height = height } });
    self.pushEvent(.{ .framebuffer = .{ .width = width, .height = height } });
    self.pushEvent(.draw);
}

export fn wioChars(self: *@This(), chars: [*:0]const u8) void {
    const view = std.unicode.Utf8View.init(std.mem.sliceTo(chars, 0)) catch return;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |char| {
        if (char >= ' ' and char != 0x7F) {
            self.pushEvent(.{ .char = char });
        }
    }
}

export fn wioKey(self: *@This(), key: i32, event: u8) void {
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

export fn wioButtons(self: *@This(), buttons: u8) void {
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

export fn wioMouse(self: *@This(), x: u16, y: u16) void {
    self.pushEvent(.{ .mouse = .{ .x = x, .y = y } });
}

export fn wioScroll(self: *@This(), vertical: f32, horizontal: f32) void {
    if (vertical != 0) self.pushEvent(.{ .scroll_vertical = vertical });
    if (horizontal != 0) self.pushEvent(.{ .scroll_horizontal = horizontal });
}

fn wioAudioOutputWrite(data: *const anyopaque, buffer: [*]f32, size: usize) callconv(.c) void {
    const writeFn: *const fn ([]f32) void = @ptrCast(@alignCast(data));
    writeFn(buffer[0 .. size / @sizeOf(f32)]);
}

comptime {
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

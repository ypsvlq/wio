const std = @import("std");
const wio = @import("wio.zig");
const c = @cImport(@cInclude("mach-o/dyld.h"));
const log = std.log.scoped(.wio);

extern fn wioInit() void;
extern fn wioRun() void;
extern fn wioLoop() void;
extern fn wioCreateWindow(*anyopaque, u16, u16) *anyopaque;
extern fn wioDestroyWindow(*anyopaque, ?*anyopaque) void;
extern fn wioSetTitle(*anyopaque, [*]const u8, usize) void;
extern fn wioSetSize(*anyopaque, u16, u16) void;
extern fn wioSetMode(*anyopaque, u8) void;
extern fn wioSetCursor(*anyopaque, u8) void;
extern fn wioSetCursorMode(*anyopaque, u8) void;
extern fn wioCreateContext(*anyopaque) ?*anyopaque;
extern fn wioMakeContextCurrent(?*anyopaque) void;
extern fn wioSwapBuffers(?*anyopaque) void;
extern fn wioSwapInterval(?*anyopaque, i32) void;
extern fn wioMessageBox(u8, [*]const u8, usize) void;
extern fn wioSetClipboardText([*]const u8, usize) void;
extern fn wioGetClipboardText(*const anyopaque, *usize) ?[*]u8;

const EventQueue = std.fifo.LinearFifo(wio.Event, .Dynamic);

pub fn init(options: wio.InitOptions) !void {
    _ = options;
    wioInit();
}

pub fn deinit() void {}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions) !void {
    _ = options;
    wioRun();
    while (try func()) {
        wioLoop();
    }
}

events: EventQueue,
window: *anyopaque,
context: ?*anyopaque = null,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const self = try wio.allocator.create(@This());
    self.events = EventQueue.init(wio.allocator); // must be valid in wioCreateWindow
    self.* = .{
        .events = self.events,
        .window = wioCreateWindow(self, options.size.width, options.size.height),
    };
    self.setTitle(options.title);
    self.setMode(options.mode);
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);
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

pub fn setSize(self: *@This(), size: wio.Size) void {
    wioSetSize(self.window, size.width, size.height);
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

pub fn requestAttention(self: *@This()) void {
    _ = self;
}

pub fn createContext(self: *@This(), options: wio.CreateContextOptions) !void {
    _ = options;
    self.context = wioCreateContext(self.window);
}

pub fn makeContextCurrent(self: *@This()) void {
    wioMakeContextCurrent(self.context);
}

pub fn swapBuffers(self: *@This()) void {
    wioSwapBuffers(self.context);
}

pub fn swapInterval(self: *@This(), interval: i32) void {
    wioSwapInterval(self.context, interval);
}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    return allocator.alloc(wio.JoystickInfo, 0);
}

pub fn freeJoysticks(allocator: std.mem.Allocator, list: []wio.JoystickInfo) void {
    allocator.free(list);
}

pub fn resolveJoystickId(id: []const u8) ?usize {
    _ = id;
    return null;
}

pub fn openJoystick(handle: usize) !Joystick {
    _ = handle;
    return error.Unavailable;
}

pub const Joystick = struct {
    pub fn close(self: *Joystick) void {
        _ = self;
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        _ = self;
        return null;
    }
};

pub fn messageBox(_: ?*@This(), style: wio.MessageBoxStyle, _: []const u8, message: []const u8) void {
    wioMessageBox(@intFromEnum(style), message.ptr, message.len);
}

pub fn setClipboardText(text: []const u8) void {
    wioSetClipboardText(text.ptr, text.len);
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    var len: usize = undefined;
    const text = wioGetClipboardText(&allocator, &len) orelse return null;
    return text[0..len];
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

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return if (c.NSLookupAndBindSymbol("_" ++ name)) |symbol| c.NSAddressOfSymbol(symbol) else null;
}

fn pushEvent(self: *@This(), event: wio.Event) void {
    self.events.writeItem(event) catch {};
}

export fn wioClose(self: *@This()) void {
    self.pushEvent(.close);
}

export fn wioCreate(self: *@This()) void {
    self.pushEvent(.create);
}

export fn wioFocus(self: *@This()) void {
    self.pushEvent(.focused);
}

export fn wioUnfocus(self: *@This()) void {
    self.pushEvent(.unfocused);
}

export fn wioSize(self: *@This(), maximized: bool, width: u16, height: u16, fb_width: u16, fb_height: u16) void {
    self.pushEvent(.{ .mode = if (maximized) .maximized else .normal });
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

export fn wioKeyDown(self: *@This(), key: u16) void {
    if (keycodeToButton(key)) |button| {
        self.pushEvent(.{ .button_press = button });
    }
}

export fn wioKeyUp(self: *@This(), key: u16) void {
    if (keycodeToButton(key)) |button| self.pushEvent(.{ .button_release = button });
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

export fn wioScroll(self: *@This(), x: f32, y: f32) void {
    if (x != 0) self.pushEvent(.{ .scroll_horizontal = x });
    if (y != 0) self.pushEvent(.{ .scroll_vertical = -y });
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

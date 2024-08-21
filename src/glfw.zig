const std = @import("std");
const wio = @import("wio.zig");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});
const log = std.log.scoped(.wio);

const EventQueue = std.fifo.LinearFifo(wio.Event, .Dynamic);

var windows: std.ArrayList(*@This()) = undefined;

pub fn init(options: wio.InitOptions) !void {
    _ = c.glfwSetErrorCallback(errorCallback);
    _ = c.glfwInitHint(c.GLFW_JOYSTICK_HAT_BUTTONS, c.GLFW_FALSE);
    if (c.glfwInit() == 0) return error.Unexpected;
    if (options.joystick) _ = c.glfwSetJoystickCallback(joystickCallback);
    windows = std.ArrayList(*@This()).init(wio.allocator);
}

pub fn deinit() void {
    windows.deinit();
    _ = c.glfwTerminate();
}

pub fn run(func: fn () anyerror!bool, options: wio.RunOptions) !void {
    while (true) {
        if (options.wait) {
            c.glfwWaitEvents();
        } else {
            c.glfwPollEvents();
        }
        if (!try func()) return;
    }
}

events: EventQueue,
window: *c.GLFWwindow,

pub fn createWindow(options: wio.CreateWindowOptions) !*@This() {
    const title = try wio.allocator.dupeZ(u8, options.title);
    defer wio.allocator.free(title);
    const self = try wio.allocator.create(@This());
    errdefer wio.allocator.destroy(self);
    self.* = .{
        .events = EventQueue.init(wio.allocator),
        .window = c.glfwCreateWindow(options.size.width, options.size.height, title, null, null) orelse return error.Unexpected,
    };
    errdefer self.destroy();
    c.glfwSetWindowUserPointer(self.window, &self.events);
    try windows.append(self);

    self.setDisplayMode(options.display_mode);
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);

    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetWindowSize(self.window, &width, &height);
    sizeCallback(self.window, width, height);
    c.glfwGetFramebufferSize(self.window, &width, &height);
    framebufferSizeCallback(self.window, width, height);
    var scale: f32 = undefined;
    c.glfwGetWindowContentScale(self.window, null, &scale);
    contentScaleCallback(self.window, 0, scale);
    try self.events.writeItem(.create);

    _ = c.glfwSetWindowCloseCallback(self.window, closeCallback);
    _ = c.glfwSetWindowFocusCallback(self.window, focusCallback);
    _ = c.glfwSetWindowRefreshCallback(self.window, refreshCallback);
    _ = c.glfwSetWindowSizeCallback(self.window, sizeCallback);
    _ = c.glfwSetFramebufferSizeCallback(self.window, framebufferSizeCallback);
    _ = c.glfwSetWindowContentScaleCallback(self.window, contentScaleCallback);
    _ = c.glfwSetCharCallback(self.window, charCallback);
    _ = c.glfwSetKeyCallback(self.window, keyCallback);
    _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
    _ = c.glfwSetCursorPosCallback(self.window, cursorPosCallback);
    _ = c.glfwSetScrollCallback(self.window, scrollCallback);

    return self;
}

pub fn destroy(self: *@This()) void {
    for (windows.items, 0..) |window, i| {
        if (window == self) {
            _ = windows.swapRemove(i);
            break;
        }
    }
    c.glfwDestroyWindow(self.window);
    self.events.deinit();
    wio.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?wio.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: []const u8) void {
    const title_z = wio.allocator.dupeZ(u8, title) catch return;
    defer wio.allocator.free(title_z);
    c.glfwSetWindowTitle(self.window, title_z);
}

pub fn setSize(self: *@This(), size: wio.Size) void {
    c.glfwSetWindowSize(self.window, size.width, size.height);
}

pub fn setDisplayMode(self: *@This(), mode: wio.DisplayMode) void {
    switch (mode) {
        .windowed => {
            c.glfwRestoreWindow(self.window);
            c.glfwSetWindowAttrib(self.window, c.GLFW_DECORATED, 1);
        },
        .maximized => {
            c.glfwMaximizeWindow(self.window);
            c.glfwSetWindowAttrib(self.window, c.GLFW_DECORATED, 1);
        },
        .borderless => {
            c.glfwSetWindowAttrib(self.window, c.GLFW_DECORATED, 0);
        },
        .hidden => {
            c.glfwHideWindow(self.window);
            return;
        },
    }
    c.glfwShowWindow(self.window);
}

pub fn setCursor(self: *@This(), shape: wio.Cursor) void {
    _ = self;
    _ = shape;
}

pub fn setCursorMode(self: *@This(), mode: wio.CursorMode) void {
    switch (mode) {
        .normal => c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL),
        .hidden => c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_HIDDEN),
    }
}

pub fn makeContextCurrent(self: *@This()) void {
    c.glfwMakeContextCurrent(self.window);
}

pub fn swapBuffers(self: *@This()) void {
    c.glfwSwapBuffers(self.window);
}

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    var list = try std.ArrayList(wio.JoystickInfo).initCapacity(allocator, c.GLFW_JOYSTICK_LAST + 1);
    errdefer {
        for (list.items) |item| {
            allocator.free(item.id);
            allocator.free(item.name);
        }
        list.deinit();
    }
    var index: u8 = 0;
    while (index <= c.GLFW_JOYSTICK_LAST) : (index += 1) {
        const guid = c.glfwGetJoystickGUID(index) orelse continue;
        const name_z = c.glfwGetJoystickName(index) orelse continue;
        const id = try std.fmt.allocPrint(allocator, "{x}{s}", .{ index, guid });
        errdefer allocator.free(id);
        const name = try allocator.dupe(u8, std.mem.sliceTo(name_z, 0));
        errdefer allocator.free(name);
        list.appendAssumeCapacity(.{ .id = id, .name = name });
    }
    return list.toOwnedSlice();
}

var joysticks = std.StaticBitSet(c.GLFW_JOYSTICK_LAST + 1).initEmpty();

pub fn openJoystick(id: []const u8) !?Joystick {
    const index: u8 = blk: {
        var index = std.fmt.charToDigit(id[0], 16) catch return null;
        if (c.glfwGetJoystickGUID(index)) |guid| {
            if (!joysticks.isSet(index) and std.mem.eql(u8, std.mem.sliceTo(guid, 0), id[1..])) {
                joysticks.set(index);
                break :blk index;
            }
        }

        index = 0;
        while (index <= c.GLFW_JOYSTICK_LAST) : (index += 1) {
            if (c.glfwGetJoystickGUID(index)) |guid| {
                if (!joysticks.isSet(index) and std.mem.eql(u8, std.mem.sliceTo(guid, 0), id[1..])) {
                    joysticks.set(index);
                    break :blk index;
                }
            }
        }

        return null;
    };

    var axes_count: c_int = undefined;
    _ = c.glfwGetJoystickAxes(index, &axes_count) orelse return null;
    return .{
        .id = index,
        .axes = try wio.allocator.alloc(u16, @intCast(axes_count)),
    };
}

pub const Joystick = struct {
    id: u8,
    axes: []u16,

    pub fn close(self: *Joystick) void {
        joysticks.unset(self.id);
        wio.allocator.free(self.axes);
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        var axes_count: c_int = undefined;
        var hats_count: c_int = undefined;
        var buttons_count: c_int = undefined;
        const axes = c.glfwGetJoystickAxes(self.id, &axes_count) orelse return null;
        const hats = c.glfwGetJoystickHats(self.id, &hats_count) orelse return null;
        const buttons = c.glfwGetJoystickButtons(self.id, &buttons_count) orelse return null;
        for (self.axes, 0..) |*axis, i| {
            axis.* = if (i < axes_count) @intFromFloat((axes[i] + 1) * 0xFFFF.0 / 2) else 0;
        }
        return .{
            .axes = self.axes,
            .hats = @constCast(@ptrCast(hats[0..@intCast(hats_count)])),
            .buttons = @constCast(@ptrCast(buttons[0..@intCast(buttons_count)])),
        };
    }
};

pub fn messageBox(backend: ?*@This(), style: wio.MessageBoxStyle, title: []const u8, message: []const u8) void {
    _ = backend;
    _ = title;
    switch (style) {
        .info => std.log.info("{s}", .{message}),
        .warn => std.log.warn("{s}", .{message}),
        .err => std.log.err("{s}", .{message}),
    }
}

pub fn setClipboardText(text: []const u8) void {
    const text_z = wio.allocator.dupeZ(u8, text) catch return;
    defer wio.allocator.free(text_z);
    c.glfwSetClipboardString(null, text_z);
}

pub fn getClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    const text = c.glfwGetClipboardString(null) orelse return null;
    return allocator.dupe(u8, std.mem.sliceTo(text, 0)) catch null;
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const anyopaque {
    return c.glfwGetProcAddress(name);
}

pub fn swapInterval(interval: i32) void {
    c.glfwSwapInterval(interval);
}

fn errorCallback(_: c_int, description: [*c]const u8) callconv(.C) void {
    log.err("{s}", .{description});
}

fn joystickCallback(_: c_int, _: c_int) callconv(.C) void {
    for (windows.items) |window| {
        window.events.writeItem(.joystick) catch {};
    }
}

fn pushEvent(window: ?*c.GLFWwindow, event: wio.Event) void {
    const events: *EventQueue = @alignCast(@ptrCast(c.glfwGetWindowUserPointer(window).?));
    events.writeItem(event) catch {};
}

fn closeCallback(window: ?*c.GLFWwindow) callconv(.C) void {
    pushEvent(window, .close);
}

fn focusCallback(window: ?*c.GLFWwindow, focused: c_int) callconv(.C) void {
    pushEvent(window, if (focused == 1) .focused else .unfocused);
}

fn refreshCallback(window: ?*c.GLFWwindow) callconv(.C) void {
    pushEvent(window, .draw);
}

fn sizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    const size = wio.Size{ .width = @intCast(width), .height = @intCast(height) };
    if (c.glfwGetWindowAttrib(window, c.GLFW_MAXIMIZED) == 1) {
        pushEvent(window, .{ .maximized = size });
    } else {
        pushEvent(window, .{ .size = size });
    }
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    pushEvent(window, .{ .framebuffer = .{ .width = @intCast(width), .height = @intCast(height) } });
}

fn contentScaleCallback(window: ?*c.GLFWwindow, _: f32, y_scale: f32) callconv(.C) void {
    pushEvent(window, .{ .scale = y_scale });
}

fn charCallback(window: ?*c.GLFWwindow, codepoint: u32) callconv(.C) void {
    pushEvent(window, .{ .char = @intCast(codepoint) });
}

fn keyCallback(window: ?*c.GLFWwindow, key: c_int, _: c_int, event: c_int, _: c_int) callconv(.C) void {
    const button = keyToButton(key) orelse return;
    switch (event) {
        c.GLFW_PRESS => pushEvent(window, .{ .button_press = button }),
        c.GLFW_REPEAT => pushEvent(window, .{ .button_repeat = button }),
        c.GLFW_RELEASE => pushEvent(window, .{ .button_release = button }),
        else => {},
    }
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, _: c_int) callconv(.C) void {
    const wio_button: wio.Button = switch (button) {
        c.GLFW_MOUSE_BUTTON_LEFT => .mouse_left,
        c.GLFW_MOUSE_BUTTON_RIGHT => .mouse_right,
        c.GLFW_MOUSE_BUTTON_MIDDLE => .mouse_middle,
        c.GLFW_MOUSE_BUTTON_4 => .mouse_back,
        c.GLFW_MOUSE_BUTTON_5 => .mouse_forward,
        else => return,
    };
    switch (action) {
        c.GLFW_PRESS => pushEvent(window, .{ .button_press = wio_button }),
        c.GLFW_RELEASE => pushEvent(window, .{ .button_release = wio_button }),
        else => {},
    }
}

fn cursorPosCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    pushEvent(window, .{ .mouse = .{
        .x = @intFromFloat(std.math.clamp(x, 0, std.math.maxInt(u16))),
        .y = @intFromFloat(std.math.clamp(y, 0, std.math.maxInt(u16))),
    } });
}

fn scrollCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    if (x != 0) pushEvent(window, .{ .scroll_horizontal = @floatCast(x) });
    if (y != 0) pushEvent(window, .{ .scroll_vertical = @floatCast(-y) });
}

fn keyToButton(key: c_int) ?wio.Button {
    return switch (key) {
        c.GLFW_KEY_SPACE => .space,
        c.GLFW_KEY_APOSTROPHE => .apostrophe,
        c.GLFW_KEY_COMMA => .comma,
        c.GLFW_KEY_MINUS => .minus,
        c.GLFW_KEY_PERIOD => .dot,
        c.GLFW_KEY_SLASH => .slash,
        c.GLFW_KEY_0 => .@"0",
        c.GLFW_KEY_1 => .@"1",
        c.GLFW_KEY_2 => .@"2",
        c.GLFW_KEY_3 => .@"3",
        c.GLFW_KEY_4 => .@"4",
        c.GLFW_KEY_5 => .@"5",
        c.GLFW_KEY_6 => .@"6",
        c.GLFW_KEY_7 => .@"7",
        c.GLFW_KEY_8 => .@"8",
        c.GLFW_KEY_9 => .@"9",
        c.GLFW_KEY_SEMICOLON => .semicolon,
        c.GLFW_KEY_EQUAL => .equals,
        c.GLFW_KEY_A => .a,
        c.GLFW_KEY_B => .b,
        c.GLFW_KEY_C => .c,
        c.GLFW_KEY_D => .d,
        c.GLFW_KEY_E => .e,
        c.GLFW_KEY_F => .f,
        c.GLFW_KEY_G => .g,
        c.GLFW_KEY_H => .h,
        c.GLFW_KEY_I => .i,
        c.GLFW_KEY_J => .j,
        c.GLFW_KEY_K => .k,
        c.GLFW_KEY_L => .l,
        c.GLFW_KEY_M => .m,
        c.GLFW_KEY_N => .n,
        c.GLFW_KEY_O => .o,
        c.GLFW_KEY_P => .p,
        c.GLFW_KEY_Q => .q,
        c.GLFW_KEY_R => .r,
        c.GLFW_KEY_S => .s,
        c.GLFW_KEY_T => .t,
        c.GLFW_KEY_U => .u,
        c.GLFW_KEY_V => .v,
        c.GLFW_KEY_W => .w,
        c.GLFW_KEY_X => .x,
        c.GLFW_KEY_Y => .y,
        c.GLFW_KEY_Z => .z,
        c.GLFW_KEY_LEFT_BRACKET => .left_bracket,
        c.GLFW_KEY_BACKSLASH => .backslash,
        c.GLFW_KEY_RIGHT_BRACKET => .right_bracket,
        c.GLFW_KEY_GRAVE_ACCENT => .grave,
        c.GLFW_KEY_WORLD_1 => .iso_backslash,
        c.GLFW_KEY_WORLD_2 => .iso_backslash,
        c.GLFW_KEY_ESCAPE => .escape,
        c.GLFW_KEY_ENTER => .enter,
        c.GLFW_KEY_TAB => .tab,
        c.GLFW_KEY_BACKSPACE => .backspace,
        c.GLFW_KEY_INSERT => .insert,
        c.GLFW_KEY_DELETE => .delete,
        c.GLFW_KEY_RIGHT => .right,
        c.GLFW_KEY_LEFT => .left,
        c.GLFW_KEY_DOWN => .down,
        c.GLFW_KEY_UP => .up,
        c.GLFW_KEY_PAGE_UP => .page_up,
        c.GLFW_KEY_PAGE_DOWN => .page_down,
        c.GLFW_KEY_HOME => .home,
        c.GLFW_KEY_END => .end,
        c.GLFW_KEY_CAPS_LOCK => .caps_lock,
        c.GLFW_KEY_SCROLL_LOCK => .scroll_lock,
        c.GLFW_KEY_NUM_LOCK => .num_lock,
        c.GLFW_KEY_PRINT_SCREEN => .print_screen,
        c.GLFW_KEY_PAUSE => .pause,
        c.GLFW_KEY_F1 => .f1,
        c.GLFW_KEY_F2 => .f2,
        c.GLFW_KEY_F3 => .f3,
        c.GLFW_KEY_F4 => .f4,
        c.GLFW_KEY_F5 => .f5,
        c.GLFW_KEY_F6 => .f6,
        c.GLFW_KEY_F7 => .f7,
        c.GLFW_KEY_F8 => .f8,
        c.GLFW_KEY_F9 => .f9,
        c.GLFW_KEY_F10 => .f10,
        c.GLFW_KEY_F11 => .f11,
        c.GLFW_KEY_F12 => .f12,
        c.GLFW_KEY_F13 => .f13,
        c.GLFW_KEY_F14 => .f14,
        c.GLFW_KEY_F15 => .f15,
        c.GLFW_KEY_F16 => .f16,
        c.GLFW_KEY_F17 => .f17,
        c.GLFW_KEY_F18 => .f18,
        c.GLFW_KEY_F19 => .f19,
        c.GLFW_KEY_F20 => .f20,
        c.GLFW_KEY_F21 => .f21,
        c.GLFW_KEY_F22 => .f22,
        c.GLFW_KEY_F23 => .f23,
        c.GLFW_KEY_F24 => .f24,
        c.GLFW_KEY_KP_0 => .kp_0,
        c.GLFW_KEY_KP_1 => .kp_1,
        c.GLFW_KEY_KP_2 => .kp_2,
        c.GLFW_KEY_KP_3 => .kp_3,
        c.GLFW_KEY_KP_4 => .kp_4,
        c.GLFW_KEY_KP_5 => .kp_5,
        c.GLFW_KEY_KP_6 => .kp_6,
        c.GLFW_KEY_KP_7 => .kp_7,
        c.GLFW_KEY_KP_8 => .kp_8,
        c.GLFW_KEY_KP_9 => .kp_9,
        c.GLFW_KEY_KP_DECIMAL => .kp_dot,
        c.GLFW_KEY_KP_DIVIDE => .kp_slash,
        c.GLFW_KEY_KP_MULTIPLY => .kp_star,
        c.GLFW_KEY_KP_SUBTRACT => .kp_minus,
        c.GLFW_KEY_KP_ADD => .kp_plus,
        c.GLFW_KEY_KP_ENTER => .kp_enter,
        c.GLFW_KEY_KP_EQUAL => .kp_equals,
        c.GLFW_KEY_LEFT_SHIFT => .left_shift,
        c.GLFW_KEY_LEFT_CONTROL => .left_control,
        c.GLFW_KEY_LEFT_ALT => .left_alt,
        c.GLFW_KEY_LEFT_SUPER => .left_gui,
        c.GLFW_KEY_RIGHT_SHIFT => .right_shift,
        c.GLFW_KEY_RIGHT_CONTROL => .right_control,
        c.GLFW_KEY_RIGHT_ALT => .right_alt,
        c.GLFW_KEY_RIGHT_SUPER => .right_gui,
        c.GLFW_KEY_MENU => .application,
        else => null,
    };
}

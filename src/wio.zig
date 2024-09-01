const std = @import("std");
const builtin = @import("builtin");
const Backend = switch (builtin.os.tag) {
    .windows => @import("win32.zig"),
    .macos => @import("glfw.zig"),
    .linux, .openbsd, .netbsd, .freebsd => @import("x11.zig"),
    else => if (builtin.target.isWasm()) @import("wasm.zig") else @compileError("unsupported platform"),
};

pub var allocator: std.mem.Allocator = undefined;

pub const logFn = if (@hasDecl(Backend, "logFn")) Backend.logFn else std.log.defaultLog;

pub const InitOptions = struct {
    joystick: bool = false,
    opengl: bool = false,
};

/// Unless otherwise noted, all calls to wio functions must be made on the same thread.
pub fn init(ally: std.mem.Allocator, options: InitOptions) !void {
    allocator = ally;
    try Backend.init(options);
}

pub fn deinit() void {
    Backend.deinit();
}

pub const RunOptions = struct {
    wait: bool = false,
};

/// Begins the main loop, which continues as long as `func` returns true.
///
/// This must be the final call on its thread, and there must be no uses of `defer` in the same scope
/// (depending on the platform, it may return immediately, never, or when the main loop exits).
pub fn run(func: fn () anyerror!bool, options: RunOptions) !void {
    return Backend.run(func, options);
}

pub const Size = struct {
    width: u16,
    height: u16,

    pub fn multiply(self: Size, scale: f32) Size {
        const width: f32 = @floatFromInt(self.width);
        const height: f32 = @floatFromInt(self.height);
        return .{
            .width = @intFromFloat(width * scale),
            .height = @intFromFloat(height * scale),
        };
    }
};

pub const Position = struct { x: u16, y: u16 };

pub const CreateWindowOptions = struct {
    title: []const u8 = "wio",
    size: Size = .{ .width = 640, .height = 480 },
    scale: f32 = 1,
    display_mode: DisplayMode = .windowed,
    cursor: Cursor = .arrow,
    cursor_mode: CursorMode = .normal,
    opengl: ?struct {} = null,
};

pub fn createWindow(options: CreateWindowOptions) !Window {
    return .{ .backend = try Backend.createWindow(options) };
}

pub const Window = struct {
    backend: @typeInfo(@typeInfo(@TypeOf(Backend.createWindow)).Fn.return_type.?).ErrorUnion.payload,

    pub fn destroy(self: *Window) void {
        self.backend.destroy();
    }

    pub fn messageBox(self: *Window, style: MessageBoxStyle, title: []const u8, message: []const u8) void {
        Backend.messageBox(self.backend, style, title, message);
    }

    pub fn getEvent(self: *Window) ?Event {
        return self.backend.getEvent();
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        self.backend.setTitle(title);
    }

    pub fn setSize(self: *Window, size: Size) void {
        self.backend.setSize(size);
    }

    pub fn setDisplayMode(self: *Window, mode: DisplayMode) void {
        self.backend.setDisplayMode(mode);
    }

    pub fn setCursor(self: *Window, cursor: Cursor) void {
        self.backend.setCursor(cursor);
    }

    pub fn setCursorMode(self: *Window, mode: CursorMode) void {
        self.backend.setCursorMode(mode);
    }

    /// May be called on any thread.
    pub fn makeContextCurrent(self: *Window) void {
        self.backend.makeContextCurrent();
    }

    pub fn swapBuffers(self: *Window) void {
        self.backend.swapBuffers();
    }
};

pub fn getJoysticks(ally: std.mem.Allocator) !JoystickList {
    return .{ .items = try Backend.getJoysticks(ally), .allocator = ally };
}

pub const JoystickList = struct {
    items: []JoystickInfo,
    allocator: std.mem.Allocator,

    pub fn deinit(self: JoystickList) void {
        for (self.items) |info| {
            self.allocator.free(info.id);
            self.allocator.free(info.name);
        }
        self.allocator.free(self.items);
    }
};

pub const JoystickInfo = struct {
    id: []const u8,
    name: []const u8,
};

pub fn openJoystick(id: []const u8) !?Joystick {
    return if (try Backend.openJoystick(id)) |backend| .{ .backend = backend } else null;
}

pub const Joystick = struct {
    backend: Backend.Joystick,

    pub fn close(self: *Joystick) void {
        self.backend.close();
    }

    pub fn poll(self: *Joystick) !?JoystickState {
        return self.backend.poll();
    }
};

pub const JoystickState = struct {
    axes: []u16,
    hats: []Hat,
    buttons: []bool,
};

pub const Hat = packed struct {
    up: bool = false,
    right: bool = false,
    down: bool = false,
    left: bool = false,
};

pub const MessageBoxStyle = enum { info, warn, err };

pub fn messageBox(style: MessageBoxStyle, title: []const u8, message: []const u8) void {
    Backend.messageBox(null, style, title, message);
}

pub fn setClipboardText(text: []const u8) void {
    Backend.setClipboardText(text);
}

pub fn getClipboardText(ally: std.mem.Allocator) ?[]u8 {
    return Backend.getClipboardText(ally);
}

pub fn glGetProcAddress(comptime name: [:0]const u8) ?*const fn () void {
    return @alignCast(@ptrCast(Backend.glGetProcAddress(name)));
}

/// May be called on any thread.
pub fn swapInterval(interval: i32) void {
    Backend.swapInterval(interval);
}

pub const Event = union(enum) {
    close: void,
    create: void,
    focused: void,
    unfocused: void,
    draw: void,
    size: Size,
    maximized: Size,
    framebuffer: Size,
    scale: f32,
    char: u21,
    button_press: Button,
    button_repeat: Button,
    button_release: Button,
    mouse: Position,
    scroll_vertical: f32,
    scroll_horizontal: f32,
    joystick: void,
};

pub const EventType = @typeInfo(Event).Union.tag_type.?;

pub const DisplayMode = enum {
    windowed,
    maximized,
    borderless,
    hidden,
};

pub const Cursor = enum {
    arrow,
    arrow_busy,
    busy,
    text,
    hand,
    crosshair,
    forbidden,
    move,
    size_ns,
    size_ew,
    size_nesw,
    size_nwse,
};

pub const CursorMode = enum {
    normal,
    hidden,
};

pub const Button = enum {
    mouse_left,
    mouse_right,
    mouse_middle,
    mouse_back,
    mouse_forward,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    enter,
    escape,
    backspace,
    tab,
    space,
    minus,
    equals,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    grave,
    comma,
    dot,
    slash,
    caps_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    print_screen,
    scroll_lock,
    pause,
    insert,
    home,
    page_up,
    delete,
    end,
    page_down,
    right,
    left,
    down,
    up,
    num_lock,
    kp_slash,
    kp_star,
    kp_minus,
    kp_plus,
    kp_enter,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_0,
    kp_dot,
    iso_backslash,
    application,
    kp_equals,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    kp_comma,
    international1,
    international2,
    international3,
    international4,
    international5,
    lang1,
    lang2,
    left_control,
    left_shift,
    left_alt,
    left_gui,
    right_control,
    right_shift,
    right_alt,
    right_gui,
};

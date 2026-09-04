const std = @import("std");
const wio = @import("wio");

extern fn metalInit(*anyopaque, [*]const u8, usize) void;
extern fn metalResize(u16, u16) void;
extern fn metalDraw() void;

pub fn main(init: std.process.Init) !void {
    try wio.init(.{
        .allocator = init.gpa,
        .io = init.io,
        .eventFn = eventFn,
    });
    defer wio.deinit();

    var close = false;

    var window = try wio.Window.create(.{
        .event_fn_data = &close,
        .title = "Metal",
        .scale = 1,
    });
    defer window.destroy();

    const shaders = @embedFile("shaders.metal");
    metalInit(window.backend.window, shaders, shaders.len);
    metalDraw();

    while (!close) {
        wio.update();
        wio.wait(.{});
    }
}

fn eventFn(data: ?*anyopaque, event: wio.Event) void {
    const close: *bool = @ptrCast(data);
    switch (event) {
        .close => close.* = true,
        .size_physical => |size| metalResize(size.width, size.height),
        .draw => metalDraw(),
        else => {},
    }
}

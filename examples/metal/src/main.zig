const std = @import("std");
const wio = @import("wio");

extern fn metalInit(*anyopaque, [*]const u8, usize) void;
extern fn metalResize(u16, u16) void;
extern fn metalDraw() void;

pub fn main(init: std.process.Init) !void {
    try wio.init(.{
        .allocator = init.gpa,
        .io = init.io,
        .eventFn = wio.EventQueue.eventFn,
    });
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    var window = try wio.Window.create(.{
        .event_fn_data = &events,
        .title = "Metal",
        .scale = 1,
    });
    defer window.destroy();

    const shaders = @embedFile("shaders.metal");
    metalInit(window.backend.window, shaders, shaders.len);

    while (true) {
        wio.update();
        while (events.pop()) |event| {
            switch (event) {
                .close => return,
                .size_physical => |size| metalResize(size.width, size.height),
                .draw => metalDraw(),
                else => {},
            }
        }
        wio.wait(.{});
    }
}

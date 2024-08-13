const std = @import("std");
const wio = @import("wio");
const joystick = @import("joystick.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();
var window: wio.Window = undefined;

pub fn main() !void {
    try wio.init(allocator, .{ .joystick = true, .opengl = true });
    window = try wio.createWindow(.{ .title = "wio example", .opengl = .{} });
    window.makeContextCurrent();
    try joystick.open();
    return wio.run(loop, .{});
}

fn loop() !bool {
    try joystick.update();
    while (window.getEvent()) |event| switch (event) {
        .close => {
            joystick.close();
            window.destroy();
            wio.deinit();
            _ = gpa.deinit();
            return false;
        },
        .size, .maximized, .framebuffer => |size| std.log.info("{s} {}x{}", .{ @tagName(event), size.width, size.height }),
        .scale => |scale| std.log.info("scale {d}", .{scale}),
        .char => |char| std.log.info("char: {u}", .{char}),
        .button_press => |button| std.log.info("+{s}", .{@tagName(button)}),
        .button_repeat => |button| std.log.info("*{s}", .{@tagName(button)}),
        .button_release => |button| std.log.info("-{s}", .{@tagName(button)}),
        .mouse => |mouse| std.log.info("({},{})", .{ mouse.x, mouse.y }),
        .scroll_vertical, .scroll_horizontal => |value| std.log.info("{s} {d}", .{ @tagName(event), value }),
        .joystick => {
            std.log.info("joystick", .{});
            try joystick.open();
        },
        else => std.log.info("{s}", .{@tagName(event)}),
    };
    window.swapBuffers();
    return true;
}

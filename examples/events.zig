const std = @import("std");
const wio = @import("wio");

pub const std_options = std.Options{
    .log_level = .info,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try wio.init(allocator, .{ .opengl = true });
    defer wio.deinit();
    const window = try wio.createWindow(.{ .title = "wio example", .opengl = .{} });
    defer window.destroy();
    window.makeContextCurrent();

    main: while (true) {
        const event = window.waitEvent();
        switch (event) {
            .close => break :main,
            .size, .maximized, .framebuffer => |size| std.log.info("{s} {}x{}", .{ @tagName(event), size.width, size.height }),
            .scale => |scale| std.log.info("scale: {d}", .{scale}),
            .char => |char| std.log.info("char: {u}", .{char}),
            .button_press => |button| std.log.info("+{s}", .{@tagName(button)}),
            .button_repeat => |button| std.log.info("*{s}", .{@tagName(button)}),
            .button_release => |button| std.log.info("-{s}", .{@tagName(button)}),
            .mouse => |mouse| std.log.info("({},{})", .{ mouse.x, mouse.y }),
            .scroll_vertical, .scroll_horizontal => |value| std.log.info("{s} {d}", .{ @tagName(event), value }),
            else => std.log.info("{s}", .{@tagName(event)}),
        }
        window.swapBuffers();
    }
}

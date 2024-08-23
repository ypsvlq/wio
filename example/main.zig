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
    while (window.getEvent()) |event| {
        switch (event) {
            .size, .maximized, .framebuffer => |size| std.log.info("{s} {}x{}", .{ @tagName(event), size.width, size.height }),
            .scale => |scale| std.log.info("scale {d}", .{scale}),
            .char => |char| std.log.info("char: {u}", .{char}),
            .button_press => |button| std.log.info("+{s}", .{@tagName(button)}),
            .button_repeat => |button| std.log.info("*{s}", .{@tagName(button)}),
            .button_release => |button| std.log.info("-{s}", .{@tagName(button)}),
            .mouse => |mouse| std.log.info("({},{})", .{ mouse.x, mouse.y }),
            .scroll_vertical, .scroll_horizontal => |value| std.log.info("{s} {d}", .{ @tagName(event), value }),
            else => std.log.info("{s}", .{@tagName(event)}),
        }
        switch (event) {
            .close => {
                joystick.close();
                window.destroy();
                wio.deinit();
                _ = gpa.deinit();
                return false;
            },
            .button_press => |button| handlePress(button),
            .button_release => |button| handleRelease(button),
            .joystick => try joystick.open(),
            else => {},
        }
    }
    window.swapBuffers();
    return true;
}

var control: bool = false;
var cursor: u8 = 0;

fn handlePress(button: wio.Button) void {
    switch (button) {
        .left_control, .right_control => control = true,
        else => if (!control) return,
    }

    switch (button) {
        .t => window.setTitle("retitled wio example"),
        .s => window.setSize(.{ .width = 320, .height = 240 }),
        .w => window.setDisplayMode(.windowed),
        .m => window.setDisplayMode(.maximized),
        .b => window.setDisplayMode(.borderless),
        .h => window.setDisplayMode(.hidden),
        .p => {
            const cursors = std.enums.values(wio.Cursor);
            cursor +%= 1;
            window.setCursor(cursors[cursor % cursors.len]);
        },
        .n => window.setCursorMode(.normal),
        .i => window.setCursorMode(.hidden),
        .c => wio.setClipboardText("wio example"),
        .v => {
            const text = wio.getClipboardText(allocator) orelse return;
            defer wio.allocator.free(text);
            std.log.scoped(.clipboard).info("{s}", .{text});
        },
        else => {},
    }
}

fn handleRelease(button: wio.Button) void {
    switch (button) {
        .left_control, .right_control => control = false,
        else => {},
    }
}

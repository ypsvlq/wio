const std = @import("std");
const wio = @import("wio");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var window: wio.Window = undefined;
var active_joystick: ?wio.Joystick = null;
var last_joystick_state: u32 = 0;

pub fn main() !void {
    try wio.init(allocator, .{ .joystick = true, .opengl = true });
    window = try wio.createWindow(.{ .title = "wio example", .opengl = .{} });
    window.makeContextCurrent();
    try scanJoysticks();
    return wio.run(loop, .{});
}

fn loop() !bool {
    if (active_joystick) |*joystick| blk: {
        const state = try joystick.poll() orelse {
            std.log.scoped(.joystick).info("lost", .{});
            joystick.close();
            active_joystick = null;
            break :blk;
        };
        var xxh = std.hash.XxHash32.init(0);
        xxh.update(std.mem.sliceAsBytes(state.axes));
        xxh.update(std.mem.sliceAsBytes(state.hats));
        xxh.update(std.mem.sliceAsBytes(state.buttons));
        const hash = xxh.final();
        if (hash != last_joystick_state) {
            std.log.scoped(.joystick).info("axes {any}", .{state.axes});
            std.log.scoped(.joystick).info("hats {any}", .{state.hats});
            std.log.scoped(.joystick).info("buttons {any}", .{state.buttons});
            last_joystick_state = hash;
        }
    }

    while (window.getEvent()) |event| switch (event) {
        .close => {
            if (active_joystick) |*joystick| joystick.close();
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
            if (active_joystick == null) try scanJoysticks();
        },
        else => std.log.info("{s}", .{@tagName(event)}),
    };

    window.swapBuffers();
    return true;
}

fn scanJoysticks() !void {
    const joysticks = try wio.getJoysticks(allocator);
    defer joysticks.deinit();
    if (joysticks.items.len > 0) {
        const info = joysticks.items[0];
        std.log.scoped(.joystick).info("using {s} / {s}", .{ info.name, info.id });
        active_joystick = try wio.openJoystick(info.id);
    }
}

const std = @import("std");
const wio = @import("wio");
const joystick = @import("joystick.zig");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = if (@import("builtin").cpu.arch.isWasm())
        @import("wasm.zig").logFn
    else
        std.log.defaultLog,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();
var window: wio.Window = undefined;

pub fn main() !void {
    try wio.init(allocator, .{
        .joystick = true,
        .joystickConnectedFn = joystick.connected,
        .audio = true,
        .audioDefaultOutputFn = audio.defaultOutput,
        .audioDefaultInputFn = audio.defaultInput,
        .opengl = true,
    });
    window = try wio.createWindow(.{ .title = "wio example", .scale = 1 });
    try window.createContext(.{ .samples = 4 });
    window.makeContextCurrent();
    window.swapInterval(1);
    renderer.init();
    return wio.run(loop);
}

var actions = false;
var request_attention = false;

fn loop() !bool {
    while (window.getEvent()) |event| {
        logEvent(event);
        switch (event) {
            .close => {
                audio.close();
                joystick.close();
                window.destroy();
                wio.deinit();
                _ = gpa.deinit();
                return false;
            },
            .framebuffer => |size| renderer.resize(size),
            .button_press, .button_repeat => |button| {
                if (button == .left_control or button == .right_control) actions = true;
                if (actions) action(button);
            },
            .button_release => |button| {
                if (button == .left_control or button == .right_control) actions = false;
            },
            .unfocused => {
                actions = false;
                if (request_attention) {
                    window.requestAttention();
                    request_attention = false;
                }
            },
            else => {},
        }
    }
    joystick.update();
    renderer.draw();
    window.swapBuffers();
    return true;
}

fn logEvent(event: wio.Event) void {
    switch (event) {
        .size, .framebuffer => |size| std.log.info("{s} {}x{}", .{ @tagName(event), size.width, size.height }),
        .scale => |scale| std.log.info("scale {d}", .{scale}),
        .mode => |mode| std.log.info("{s}", .{@tagName(mode)}),
        .char => |char| std.log.info("char: {u}", .{char}),
        .button_press => |button| std.log.info("+{s}", .{@tagName(button)}),
        .button_repeat => |button| std.log.info("*{s}", .{@tagName(button)}),
        .button_release => |button| std.log.info("-{s}", .{@tagName(button)}),
        .mouse => |mouse| std.log.info("({},{})", .{ mouse.x, mouse.y }),
        .mouse_relative => |mouse| std.log.info("{},{}", .{ mouse.x, mouse.y }),
        .scroll_vertical, .scroll_horizontal => |value| std.log.info("{s} {d}", .{ @tagName(event), value }),
        else => std.log.info("{s}", .{@tagName(event)}),
    }
}

var cursor: u8 = 0;

fn action(button: wio.Button) void {
    switch (button) {
        .t => window.setTitle("retitled wio example"),
        .w => window.setMode(.normal),
        .m => window.setMode(.maximized),
        .f => window.setMode(.fullscreen),
        .p => {
            const cursors = std.enums.values(wio.Cursor);
            cursor +%= 1;
            window.setCursor(cursors[cursor % cursors.len]);
        },
        .n => window.setCursorMode(.normal),
        .h => window.setCursorMode(.hidden),
        .r => window.setCursorMode(.relative),
        .a => request_attention = true,
        .d => {
            wio.messageBox(.info, "wio", "info");
            wio.messageBox(.warn, "wio", "warning");
            wio.messageBox(.err, "wio", "error");
        },
        .equals, .kp_plus => window.setSize(.{ .width = 640, .height = 480 }),
        .minus, .kp_minus => window.setSize(.{ .width = 320, .height = 240 }),
        .c => window.setClipboardText("wio example"),
        .v => {
            if (window.getClipboardText(allocator)) |text| {
                defer wio.allocator.free(text);
                std.log.scoped(.clipboard).info("{s}", .{text});
            }
        },
        .o => audio.play = !audio.play,
        .i => audio.record = !audio.record,
        .e => {
            var joystick_iter = wio.JoystickDeviceIterator.init();
            defer joystick_iter.deinit();
            while (joystick_iter.next()) |device| {
                defer device.release();
                const id = device.getId(allocator) orelse "";
                defer allocator.free(id);
                const name = device.getName(allocator);
                defer allocator.free(name);
                std.log.info("joystick: {s} / {s}", .{ name, id });
            }
            for (std.enums.values(wio.AudioDeviceType)) |mode| {
                var audio_iter = wio.AudioDeviceIterator.init(mode);
                defer audio_iter.deinit();
                while (audio_iter.next()) |device| {
                    defer device.release();
                    const id = device.getId(allocator) orelse "";
                    defer allocator.free(id);
                    const name = device.getName(allocator);
                    defer allocator.free(name);
                    std.log.info("audio {s}: {s} / {s}", .{ @tagName(mode), name, id });
                }
            }
        },
        else => {},
    }
}

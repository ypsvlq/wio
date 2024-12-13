const std = @import("std");
const builtin = @import("builtin");
const wio = @import("wio");
const joystick = @import("joystick.zig");
const renderer = @import("renderer.zig");
const audio = @import("audio.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();
var window: wio.Window = undefined;

pub fn main() !void {
    try wio.init(allocator, .{
        .joystick = true,
        .joystickConnectedFn = joystick.connected,
        .audio = true,
        .audioDefaultOutputFn = audio.openOutput,
        .audioDefaultInputFn = audio.openInput,
        .opengl = true,
    });
    window = try wio.createWindow(.{ .title = "wio example" });
    try window.createContext(.{});
    window.makeContextCurrent();
    window.swapInterval(1);
    renderer.init();
    return wio.run(loop);
}

fn loop() !bool {
    joystick.update();
    while (window.getEvent()) |event| {
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
        switch (event) {
            .close => {
                audio.close();
                joystick.close();
                window.destroy();
                wio.deinit();
                _ = gpa.deinit();
                return false;
            },
            .unfocused => control = false,
            .framebuffer => |size| renderer.resize(size),
            .button_press, .button_repeat => |button| handlePress(button),
            .button_release => |button| handleRelease(button),
            else => {},
        }
    }
    renderer.draw();
    window.swapBuffers();
    if (!builtin.cpu.arch.isWasm() and request_attention_at != 0 and std.time.timestamp() > request_attention_at) {
        window.requestAttention();
        request_attention_at = 0;
    }
    return true;
}

var control: bool = false;
var cursor: u8 = 0;
var request_attention_at: i64 = 0;

fn handlePress(button: wio.Button) void {
    switch (button) {
        .left_control, .right_control => control = true,
        else => if (!control) return,
    }

    switch (button) {
        .t => window.setTitle("retitled wio example"),
        .s => window.setSize(.{ .width = 320, .height = 240 }),
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
        .a => {
            if (!builtin.cpu.arch.isWasm()) {
                request_attention_at = std.time.timestamp() + 1;
            }
        },
        .d => {
            wio.messageBox(.info, "wio", "info");
            window.messageBox(.warn, "wio", "warning");
            window.messageBox(.err, "wio", "error");
        },
        .c => wio.setClipboardText("wio example"),
        .v => {
            const text = wio.getClipboardText(allocator) orelse return;
            defer wio.allocator.free(text);
            std.log.scoped(.clipboard).info("{s}", .{text});
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
                    std.log.info("{s}: {s} / {s}", .{ @tagName(mode), name, id });
                }
            }
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

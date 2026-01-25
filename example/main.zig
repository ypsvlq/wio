const std = @import("std");
const wio = @import("wio");
const gl = @import("gl.zig");
const triangle = @import("triangle.zig");
const joystick = @import("joystick.zig");
const audio = @import("audio.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = if (@import("builtin").cpu.arch.isWasm())
        @import("wasm.zig").logFn
    else
        std.log.defaultLog,
};

var debug_allocator = std.heap.DebugAllocator(.{}).init;
pub const allocator = debug_allocator.allocator();

var window: wio.Window = undefined;
var maybe_window2: ?wio.Window = null;

pub fn main() !void {
    try wio.init(allocator, .{
        .joystickConnectedFn = joystick.connected,
        .audioDefaultOutputFn = audio.defaultOutput,
        .audioDefaultInputFn = audio.defaultInput,
    });

    window = try wio.createWindow(.{
        .title = "wio example",
        .scale = 1,
        .opengl = .{
            .major_version = 2,
            .samples = 4,
        },
    });

    if (wio.build_options.opengl) {
        window.makeContextCurrent();
        window.swapInterval(1);
        try gl.load(wio.glGetProcAddress);
        try triangle.init();
    }

    return wio.run(loop);
}

fn loop() !bool {
    while (window.getEvent()) |event| {
        logEvent(event);
        switch (event) {
            .close => {
                audio.close();
                joystick.close();

                if (maybe_window2) |*window2| window2.destroy();
                window.destroy();

                wio.deinit();
                _ = debug_allocator.deinit();

                return false;
            },
            .draw => {
                if (wio.build_options.opengl) {
                    window.makeContextCurrent();
                    triangle.draw();
                    window.swapBuffers();
                }
            },
            .framebuffer => |size| {
                if (wio.build_options.opengl) {
                    window.makeContextCurrent();
                    gl.viewport(0, 0, size.width, size.height);
                }
            },
            else => try actionEvent(event),
        }
    }

    if (maybe_window2) |*window2| {
        while (window2.getEvent()) |event| {
            logEvent(event);
            switch (event) {
                .close => {
                    window2.destroy();
                    maybe_window2 = null;
                    break;
                },
                .draw => {
                    if (wio.build_options.opengl) {
                        window2.makeContextCurrent();
                        gl.clearColor(0.5, 0.5, 0.5, 1);
                        gl.clear(gl.COLOR_BUFFER_BIT);
                        window2.swapBuffers();
                    }
                },
                .framebuffer => |size| {
                    if (wio.build_options.opengl) {
                        window2.makeContextCurrent();
                        gl.viewport(0, 0, size.width, size.height);
                    }
                },
                else => {},
            }
        }
    }

    joystick.update();
    wio.wait();

    return true;
}

fn logEvent(event: wio.Event) void {
    switch (event) {
        .size, .framebuffer => |size| std.log.info("{s} {}x{}", .{ @tagName(event), size.width, size.height }),
        .scale => |scale| std.log.info("scale {d}", .{scale}),
        .mode => |mode| std.log.info("{s}", .{@tagName(mode)}),
        .char, .preview_char => |char| std.log.info("{s}: {u}", .{ @tagName(event), char }),
        .preview_cursor => |active| std.log.info("preview_cursor {}..{}", .{ active[0], active[1] }),
        .button_press => |button| std.log.info("+{s}", .{@tagName(button)}),
        .button_repeat => |button| std.log.info("*{s}", .{@tagName(button)}),
        .button_release => |button| std.log.info("-{s}", .{@tagName(button)}),
        .mouse => |mouse| std.log.info("({},{})", .{ mouse.x, mouse.y }),
        .mouse_relative => |mouse| std.log.info("{},{}", .{ mouse.x, mouse.y }),
        .scroll_vertical, .scroll_horizontal => |value| std.log.info("{s} {d}", .{ @tagName(event), value }),
        .touch => |touch| std.log.info("touch {}: ({},{})", .{ touch.id, touch.x, touch.y }),
        .touch_end => |touch| std.log.info("touch {}: {s}", .{ touch.id, if (touch.ignore) "ignore" else "end" }),
        else => std.log.info("{s}", .{@tagName(event)}),
    }
}

var actions = false;
var request_attention = false;
var text_input = false;
var cursor: u8 = 0;

fn actionEvent(event: wio.Event) !void {
    switch (event) {
        .button_press, .button_repeat => |button| {
            if (actions) {
                try action(button);
            } else if (button == .left_control or button == .right_control) {
                actions = true;
            }
        },
        .button_release => |button| {
            if (button == .left_control or button == .right_control) {
                actions = false;
            }
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

fn action(button: wio.Button) !void {
    switch (button) {
        .enter => {
            if (maybe_window2 == null) {
                maybe_window2 = try wio.createWindow(.{
                    .size = .{ .width = 320, .height = 240 },
                    .scale = 1,
                    .opengl = .{},
                });
            }
        },
        .@"1" => {
            if (!text_input) {
                window.enableTextInput(.{ .cursor = .{ .x = 100, .y = 100 } });
            } else {
                window.disableTextInput();
            }
            text_input = !text_input;
        },
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
                defer allocator.free(text);
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

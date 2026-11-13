//! Draws into the area around the camera housing on macOS displays with a notch.
//!
//! Starts in full screen. Press F to toggle full screen, Escape to leave it, N to switch
//! between covering the notch and native full screen (applies on the next F), and Q to quit.
//! Build with -Doptimize=ReleaseFast, as software rendering is slow in debug builds.

const std = @import("std");
const wio = @import("wio");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var threaded: std.Io.Threaded = undefined;

var size: wio.Size = .{ .width = 640, .height = 480 };
var scale: f32 = 1;
var safe_area: wio.SafeArea = .{};
var mode: wio.WindowMode = .fullscreen;
var notch = true;
var events: wio.EventQueue = .empty;
var window: wio.Window = undefined;
var fb: wio.Framebuffer = undefined;

pub fn main() !void {
    const allocator = debug_allocator.allocator();
    threaded = .init(allocator, .{});

    try wio.init(.{
        .allocator = allocator,
        .io = threaded.io(),
        .eventFn = wio.EventQueue.eventFn,
    });

    window = try .create(.{
        .event_fn_data = &events,
        .title = "notch",
        .size = size,
        .scale = 1,
        .mode = mode,
        .notch = notch,
    });
    window.enableDrawAvailableEvents();

    fb = try window.createFramebuffer(size);

    return wio.run(loop);
}

var t: u32 = 0;
var visible = false;

fn loop() !bool {
    while (events.pop()) |event| {
        switch (event) {
            .close => return quit(),
            .size_physical => |new_size| {
                if (!std.meta.eql(new_size, size)) {
                    fb.destroy();
                    fb = try window.createFramebuffer(new_size);
                    size = new_size;
                }
            },
            .scale => |value| scale = value,
            .mode => |value| mode = value,
            .safe_area => |value| {
                safe_area = value;
                std.log.info("safe area {any}", .{value});
            },
            .visible => visible = true,
            .hidden => visible = false,
            .draw => {
                if (visible) {
                    render();
                    window.presentFramebuffer(&fb, .{});
                    t +%= 1;
                }
            },
            .button_press => |button| switch (button) {
                .f => window.setMode(if (mode == .fullscreen) .normal else .fullscreen),
                .escape => window.setMode(.normal),
                .n => {
                    notch = !notch;
                    window.setNotch(notch);
                    std.log.info("notch {}", .{notch});
                },
                .q => return quit(),
                else => {},
            },
            else => {},
        }
    }
    wio.wait(.{});
    return true;
}

fn quit() bool {
    fb.destroy();
    window.destroy();
    events.deinit();
    wio.deinit();
    threaded.deinit();
    _ = debug_allocator.deinit();
    return false;
}

fn physical(value: u16) u32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(value)) * scale));
}

fn render() void {
    const top = physical(safe_area.top);
    const notch_left, const notch_right = if (safe_area.notch) |rect|
        .{ physical(rect.origin.x), physical(rect.origin.x + rect.size.width) }
    else
        .{ 0, 0 };

    var y: u32 = 0;
    while (y < size.height) : (y += 1) {
        var x: u32 = 0;
        while (x < size.width) : (x += 1) {
            const color: u32 = if (y < top) blk: {
                if (x >= notch_left and x < notch_right) break :blk 0x000000;
                // ears: a hue sweep scrolling away from the notch on both sides
                const distance = if (x < notch_left) notch_left - x else x - notch_right;
                break :blk hue((distance / 4 + 1024 - (t * 4) % 1024) % 1024);
            } else if (top > 0 and y < top + physical(2)) 0xFFFFFF else blk: {
                const v = (x / 32 + y / 32 + t / 30) & 1;
                break :blk if (v == 0) 0x202028 else 0x181820;
            };
            fb.setPixel(x, y, color);
        }
    }
}

fn hue(h: u32) u32 {
    const segment = h / 171;
    const f = (h % 171) * 255 / 171;
    const r: u32, const g: u32, const b: u32 = switch (segment) {
        0 => .{ 255, f, 0 },
        1 => .{ 255 - f, 255, 0 },
        2 => .{ 0, 255, f },
        3 => .{ 0, 255 - f, 255 },
        4 => .{ f, 0, 255 },
        else => .{ 255, 0, 255 - f },
    };
    return (r << 16) | (g << 8) | b;
}

const std = @import("std");
const wio = @import("wio");

var window: wio.Window = undefined;
var maybe_buf: ?wio.SoftwareBuffer = null;
var size: wio.Size = .{ .width = 0, .height = 0 };
var t: u32 = 0;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();

    try wio.init(debug_allocator.allocator(), .{});
    defer wio.deinit();

    window = try wio.createWindow(.{ .title = "software", .scale = 1 });
    defer window.destroy();

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            switch (event) {
                .close => {
                    if (maybe_buf) |*buf| buf.destroy();
                    return;
                },
                .framebuffer => |fb| {
                    if (maybe_buf) |*buf| buf.destroy();
                    maybe_buf = null;
                    if (fb.width > 0 and fb.height > 0) {
                        maybe_buf = try window.createSoftwareBuffer(fb);
                        size = fb;
                    }
                },
                else => {},
            }
        }
        if (maybe_buf) |*buf| {
            render(buf.getPixels());
            buf.present();
            t +%= 1;
        }
        wio.wait(.{ .timeout_ns = std.time.ns_per_s / 60 });
    }
}

fn render(pixels: []u32) void {
    const w: u32 = size.width;
    const h: u32 = size.height;
    for (0..h) |y| {
        for (0..w) |x| {
            const v = @as(u32, @intCast(x)) ^ @as(u32, @intCast(y)) ^ t;
            pixels[y * w + x] = ((v & 0xff) << 16) | (((v >> 1) & 0xff) << 8) | ((v >> 2) & 0xff);
        }
    }
}

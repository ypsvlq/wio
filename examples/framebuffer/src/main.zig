const std = @import("std");
const wio = @import("wio");

var size: wio.Size = .{ .width = 640, .height = 480 };
var t: u16 = 0;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();

    try wio.init(debug_allocator.allocator(), .{});
    defer wio.deinit();

    var window = try wio.createWindow(.{ .title = "software", .size = size, .scale = 1 });
    defer window.destroy();

    var fb = try window.createFramebuffer(size);
    defer fb.destroy();

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            switch (event) {
                .close => return,
                .size_physical => |new_size| {
                    if (new_size.width != size.width or new_size.height != size.height) {
                        fb.destroy();
                        fb = try window.createFramebuffer(new_size);
                        size = new_size;
                    }
                },
                else => {},
            }
        }
        render(fb.getPixels());
        window.presentFramebuffer(&fb);
        t +%= 1;
        wio.wait(.{ .timeout_ns = std.time.ns_per_s / 60 });
    }
}

fn render(pixels: []u32) void {
    var y: u32 = 0;
    while (y < size.height) : (y += 1) {
        var x: u32 = 0;
        while (x < size.width) : (x += 1) {
            const v = x ^ y ^ t;
            std.mem.writeInt(
                u32,
                std.mem.asBytes(&pixels[y * size.width + x]),
                ((v & 0xFF) << 16) | (((v >> 1) & 0xFF) << 8) | ((v >> 2) & 0xFF),
                .little,
            );
        }
    }
}

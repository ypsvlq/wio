const std = @import("std");
const wio = @import("wio");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();

    try wio.init(allocator, threaded.io(), .{});
    defer wio.deinit();

    var size: wio.Size = .{ .width = 640, .height = 480 };
    var window = try wio.createWindow(.{ .title = "software", .size = size, .scale = 1 });
    defer window.destroy();

    var fb = try window.createFramebuffer(size);
    defer fb.destroy();

    var t: u16 = 0;

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            switch (event) {
                .close => return,
                .size_physical => |new_size| {
                    if (!std.meta.eql(new_size, size)) {
                        fb = try window.createFramebuffer(new_size);
                        size = new_size;
                    }
                },
                else => {},
            }
        }
        render(&fb, size, t);
        window.presentFramebuffer(&fb);
        t +%= 1;
        wio.wait(.{ .timeout_ns = std.time.ns_per_s / 60 });
    }
}

fn render(fb: *wio.Framebuffer, size: wio.Size, t: u16) void {
    var y: u32 = 0;
    while (y < size.height) : (y += 1) {
        var x: u32 = 0;
        while (x < size.width) : (x += 1) {
            const v = x ^ y ^ t;
            fb.setPixel(x, y, ((v & 0xFF) << 16) | (((v >> 1) & 0xFF) << 8) | ((v >> 2) & 0xFF));
        }
    }
}

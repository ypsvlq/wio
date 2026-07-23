const std = @import("std");
const builtin = @import("builtin");
const wio = @import("wio");

comptime {
    _ = wio; // for Android
}

pub const std_options: std.Options = .{ .logFn = wio.logFn };

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var threaded: std.Io.Threaded = undefined;

var size: wio.Size = .{ .width = 640, .height = 480 };
var events: wio.EventQueue = .empty;
var window: wio.Window = undefined;
var fb: wio.Framebuffer = undefined;

pub fn main() !void {
    var allocator: std.mem.Allocator = undefined;
    var io: std.Io = undefined;

    if (builtin.cpu.arch.isWasm()) {
        allocator = std.heap.wasm_allocator;
    } else {
        allocator = debug_allocator.allocator();
        threaded = .init(allocator, .{});
        io = threaded.io();
    }

    try wio.init(.{
        .allocator = allocator,
        .io = io,
        .eventFn = wio.EventQueue.eventFn,
    });

    window = try .create(.{
        .event_fn_data = &events,
        .title = "software",
        .size = size,
        .scale = 1,
    });

    fb = try window.createFramebuffer(size);

    return wio.run(loop);
}

var t: u16 = 0;
var visible = false;

fn loop() !bool {
    while (events.pop()) |event| {
        switch (event) {
            .close => {
                fb.destroy();
                window.destroy();
                events.deinit();
                wio.deinit();
                if (!builtin.cpu.arch.isWasm()) {
                    threaded.deinit();
                    _ = debug_allocator.deinit();
                }
                return false;
            },
            .size_physical => |new_size| {
                if (!std.meta.eql(new_size, size)) {
                    fb.destroy();
                    fb = try window.createFramebuffer(new_size);
                    size = new_size;
                }
            },
            .visible => visible = true,
            .hidden => visible = false,
            else => {},
        }
    }
    if (visible) {
        render();
        window.presentFramebuffer(&fb);
        t +%= 1;
    }
    wio.wait(.{ .timeout_ns = std.time.ns_per_s / 60 });
    return true;
}

fn render() void {
    var y: u32 = 0;
    while (y < size.height) : (y += 1) {
        var x: u32 = 0;
        while (x < size.width) : (x += 1) {
            const v = x ^ y ^ t;
            fb.setPixel(x, y, ((v & 0xFF) << 16) | (((v >> 1) & 0xFF) << 8) | ((v >> 2) & 0xFF));
        }
    }
}

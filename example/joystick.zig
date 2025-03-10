const std = @import("std");
const wio = @import("wio");
const main = @import("main.zig");
const log = std.log.scoped(.joystick);

var active: ?wio.Joystick = null;
var last_state: u32 = 0;

pub fn connected(device: wio.JoystickDevice) void {
    defer device.release();

    if (active == null) {
        const id = device.getId(main.allocator) orelse "";
        defer main.allocator.free(id);
        const name = device.getName(main.allocator);
        defer main.allocator.free(name);
        log.info("{s} / {s}", .{ name, id });

        active = device.open();
    }
}

pub fn close() void {
    if (active) |*joystick| joystick.close();
}

pub fn update() void {
    if (active) |*joystick| {
        const state = joystick.poll() orelse {
            log.info("lost", .{});
            joystick.close();
            active = null;
            last_state = 0;
            return;
        };
        var xxh = std.hash.XxHash32.init(0);
        xxh.update(std.mem.sliceAsBytes(state.axes));
        xxh.update(std.mem.sliceAsBytes(state.hats));
        xxh.update(std.mem.sliceAsBytes(state.buttons));
        const hash = xxh.final();
        if (hash != last_state) {
            if (state.axes.len > 0) log.info("axes {any}", .{state.axes});
            if (state.hats.len > 0) log.info("hats {any}", .{state.hats});
            if (state.buttons.len > 0) log.info("buttons {any}", .{state.buttons});
            last_state = hash;
        }
    }
}

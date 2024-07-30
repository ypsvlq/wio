const std = @import("std");
const wio = @import("wio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try wio.init(allocator, .{ .joystick = true });
    defer wio.deinit();

    const joysticks = try wio.getJoysticks(allocator);
    defer joysticks.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Select joystick:\n", .{});
    for (joysticks.items, 1..) |info, i| {
        try stdout.print(" {}. {s} / {s}\n", .{ i, info.name, info.id });
    }
    try stdout.print(">>> ", .{});

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();
    try std.io.getStdIn().reader().streamUntilDelimiter(line.writer(), '\n', null);
    line.items.len -= 1;
    const index = try std.fmt.parseUnsigned(usize, line.items, 10) - 1;
    if (index >= joysticks.items.len) return error.Overflow;

    var joystick = try wio.openJoystick(joysticks.items[index].id) orelse return error.DeviceNotFound;
    defer joystick.close();

    var xxh: std.hash.XxHash32 = undefined;
    var last_hash: u32 = 0;
    while (true) {
        const state = try joystick.poll() orelse break;
        xxh = std.hash.XxHash32.init(0);
        xxh.update(std.mem.sliceAsBytes(state.axes));
        xxh.update(std.mem.sliceAsBytes(state.hats));
        xxh.update(std.mem.sliceAsBytes(state.buttons));
        const hash = xxh.final();
        if (hash != last_hash) {
            try stdout.print(
                \\
                \\axes: {any}
                \\hats: {any}
                \\buttons: {any}
                \\
            , .{ state.axes, state.hats, state.buttons });
        }
        last_hash = hash;
        std.time.sleep(std.time.ns_per_ms);
    }
}

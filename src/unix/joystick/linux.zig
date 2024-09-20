const std = @import("std");
const wio = @import("../../wio.zig");
const c = @cImport(@cInclude("linux/input.h"));
const log = std.log.scoped(.wio);

const JoystickIterator = struct {
    dir: std.fs.Dir,
    iter: std.fs.Dir.Iterator,

    fn init() !JoystickIterator {
        const dir = try std.fs.openDirAbsoluteZ("/dev/input/by-path", .{ .iterate = true });
        return .{ .dir = dir, .iter = dir.iterateAssumeFirstIteration() };
    }

    fn deinit(self: *JoystickIterator) void {
        self.dir.close();
    }

    fn next(self: *JoystickIterator) !?struct { std.fs.File, u16 } {
        while (try self.iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, "-event-joystick")) {
                var buf: [std.fs.max_path_bytes]u8 = undefined;
                const link = try self.dir.readLink(entry.name, &buf);
                const prefix = "../event";
                if (std.mem.startsWith(u8, link, prefix)) {
                    const index = try std.fmt.parseInt(u16, link[prefix.len..], 10);
                    const file = try self.dir.openFile(entry.name, .{});
                    return .{ file, index };
                }
            }
        }
        return null;
    }
};

pub fn getJoysticks(allocator: std.mem.Allocator) ![]wio.JoystickInfo {
    var list = std.ArrayList(wio.JoystickInfo).init(allocator);
    errdefer {
        for (list.items) |info| {
            allocator.free(info.id);
            allocator.free(info.name);
        }
        list.deinit();
    }

    var iter = try JoystickIterator.init();
    defer iter.deinit();
    while (try iter.next()) |value| {
        const file, const index = value;
        defer file.close();

        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) != 0) continue;
        var buf: [512]u8 = undefined;
        const count = std.os.linux.ioctl(file.handle, c.EVIOCGNAME(buf.len), @intFromPtr(&buf));
        if (std.os.linux.E.init(count) != .SUCCESS) continue;

        const id = try std.fmt.allocPrint(allocator, "{}-{x:0>4}{x:0>4}", .{ index, info.vendor, info.product });
        errdefer allocator.free(id);
        const name = try allocator.dupe(u8, buf[0..count]);
        errdefer allocator.free(name);
        try list.append(.{ .id = id, .name = name });
    }

    return list.toOwnedSlice();
}

const Id = struct {
    index: []const u8,
    vendor: u16,
    product: u16,
};

fn parseId(id: []const u8) ?Id {
    const index = std.mem.indexOfScalar(u8, id, '-') orelse return null;
    if (id.len - index != 9) return null;
    return .{
        .index = id[0..index],
        .vendor = std.fmt.parseInt(u16, id[index + 1 .. index + 5], 16) catch return null,
        .product = std.fmt.parseInt(u16, id[index + 6 ..], 16) catch return null,
    };
}

pub fn resolveJoystickId(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    const target = parseId(id) orelse return allocator.dupe(u8, id);

    const path = try std.fmt.allocPrintZ(wio.allocator, "/dev/input/event{s}", .{target.index});
    defer wio.allocator.free(path);

    if (std.fs.openFileAbsoluteZ(path, .{})) |file| {
        defer file.close();
        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) == 0) {
            if (info.vendor == target.vendor and info.product == target.product) {
                return allocator.dupe(u8, id);
            }
        }
    } else |_| {}

    var iter = try JoystickIterator.init();
    while (try iter.next()) |value| {
        const file, const index = value;
        defer file.close();
        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) == 0) {
            if (info.vendor == target.vendor and info.product == target.product) {
                return std.fmt.allocPrint(allocator, "{}-{x:0>4}{x:0>4}", .{ index, info.vendor, info.product });
            }
        }
    }

    return allocator.dupe(u8, id);
}

fn EVIOCGABS(abs: u32) u32 {
    return 0x80184540 | abs;
}

pub fn openJoystick(s: []const u8) !?Joystick {
    const id = parseId(s) orelse return null;

    const path = try std.fmt.allocPrintZ(wio.allocator, "/dev/input/event{s}", .{id.index});
    defer wio.allocator.free(path);

    const result = std.os.linux.open(path, .{ .NONBLOCK = true }, 0);
    if (std.os.linux.E.init(result) != .SUCCESS) return null;
    const fd: i32 = @intCast(result);
    var success = false;
    defer _ = if (!success) std.os.linux.close(fd);

    var info: c.input_id = undefined;
    if (std.os.linux.ioctl(fd, c.EVIOCGID, @intFromPtr(&info)) != 0) return null;
    if (info.vendor != id.vendor or info.product != id.product) return null;

    var abs_bits = std.bit_set.ArrayBitSet(u8, c.ABS_CNT).initEmpty();
    if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_ABS, @sizeOf(@TypeOf(abs_bits.masks))), @intFromPtr(&abs_bits.masks))) != .SUCCESS) return null;
    var abs_iter = abs_bits.iterator(.{});
    var abs_map = [1]u8{0} ** c.ABS_CNT;
    var axis_count: u8 = 0;
    var hat_count: u8 = 0;
    while (abs_iter.next()) |i| {
        if (i < c.ABS_HAT0X or i > c.ABS_HAT3Y) {
            axis_count += 1;
            abs_map[i] = axis_count;
        } else {
            hat_count += 1;
            abs_map[i] = hat_count;
            abs_map[i + 1] = hat_count;
            _ = abs_iter.next();
        }
    }

    const axis_info = try wio.allocator.alloc(c.input_absinfo, axis_count);
    defer if (!success) wio.allocator.free(axis_info);
    for (abs_map, 0..) |index, code| {
        if (index != 0) {
            if (code < c.ABS_HAT0X or code > c.ABS_HAT3Y) {
                if (std.os.linux.ioctl(fd, EVIOCGABS(@intCast(code)), @intFromPtr(&axis_info[index - 1])) != 0) return null;
            }
        }
    }

    var key_bits = std.bit_set.ArrayBitSet(u8, c.KEY_CNT).initEmpty();
    if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_KEY, @sizeOf(@TypeOf(key_bits.masks))), @intFromPtr(&key_bits.masks))) != .SUCCESS) return null;
    var key_iter = key_bits.iterator(.{});
    var key_map = [1]u16{0} ** c.KEY_CNT;
    var button_count: u16 = 0;
    while (key_iter.next()) |i| {
        button_count += 1;
        key_map[i] = button_count;
    }

    const axes = try wio.allocator.alloc(u16, axis_count);
    errdefer wio.allocator.free(axes);
    const hats = try wio.allocator.alloc(wio.Hat, hat_count);
    errdefer wio.allocator.free(hats);
    const buttons = try wio.allocator.alloc(bool, button_count);
    errdefer wio.allocator.free(buttons);

    success = true;
    return .{ .fd = fd, .abs_map = abs_map, .key_map = key_map, .axis_info = axis_info, .axes = axes, .hats = hats, .buttons = buttons };
}

pub const Joystick = struct {
    fd: i32,
    abs_map: [c.ABS_CNT]u8,
    key_map: [c.KEY_CNT]u16,
    axis_info: []c.input_absinfo,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        wio.allocator.free(self.buttons);
        wio.allocator.free(self.hats);
        wio.allocator.free(self.axes);
        _ = std.os.linux.close(self.fd);
    }

    pub fn poll(self: *Joystick) !?wio.JoystickState {
        var event: c.input_event = undefined;
        while (true) {
            switch (std.os.linux.E.init(std.os.linux.read(self.fd, @ptrCast(&event), @sizeOf(c.input_event)))) {
                .SUCCESS => {},
                .AGAIN => break,
                .NODEV => return null,
                else => return error.Unexpected,
            }
            switch (event.type) {
                c.EV_ABS => {
                    const index = self.abs_map[event.code];
                    if (index != 0) {
                        if (event.code < c.ABS_HAT0X or event.code > c.ABS_HAT3Y) {
                            const info = self.axis_info[index - 1];
                            var value: f32 = @floatFromInt(event.value);
                            value -= @floatFromInt(info.minimum);
                            value /= @floatFromInt(info.maximum - info.minimum);
                            value *= 0xFFFF;
                            self.axes[index - 1] = @intFromFloat(value);
                        } else {
                            const hat = &self.hats[index - 1];
                            if (event.code & 1 != 0) {
                                hat.up = (event.value == -1);
                                hat.down = (event.value == 1);
                            } else {
                                hat.left = (event.value == -1);
                                hat.right = (event.value == 1);
                            }
                        }
                    }
                },
                c.EV_KEY => {
                    const index = self.key_map[event.code];
                    if (index != 0) {
                        self.buttons[index - 1] = (event.value != 0);
                    }
                },
                else => {},
            }
        }
        return .{ .axes = self.axes, .hats = self.hats, .buttons = self.buttons };
    }
};

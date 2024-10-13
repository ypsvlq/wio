const std = @import("std");
const wio = @import("../../wio.zig");
const c = @cImport(@cInclude("linux/input.h"));
const log = std.log.scoped(.wio);

var permission_warning_shown = false;

fn permissionWarning() void {
    if (!permission_warning_shown) {
        log.warn("access denied to joystick device", .{});
        permission_warning_shown = true;
    }
}

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

    fn nextName(self: *JoystickIterator) !?struct { []const u8, u16 } {
        while (try self.iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, "-event-joystick")) {
                var buf: [std.fs.max_path_bytes]u8 = undefined;
                const link = try self.dir.readLink(entry.name, &buf);
                const prefix = "../event";
                if (std.mem.startsWith(u8, link, prefix)) {
                    return .{ entry.name, try std.fmt.parseUnsigned(u16, link[prefix.len..], 10) };
                }
            }
        }
        return null;
    }

    fn nextFile(self: *JoystickIterator) !?struct { std.fs.File, u16 } {
        const name, const index = try self.nextName() orelse return null;
        const file = self.dir.openFile(name, .{}) catch |err| switch (err) {
            error.AccessDenied => {
                permissionWarning();
                return self.nextFile();
            },
            else => return err,
        };
        return .{ file, index };
    }
};

pub fn init() !void {
    var iter = try JoystickIterator.init();
    defer iter.deinit();
    while (try iter.nextName()) |value| {
        _, const index = value;
        if (wio.init_options.joystickCallback) |callback| {
            callback(index);
        }
    }
}

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
    while (try iter.nextFile()) |value| {
        const file, const index = value;
        defer file.close();

        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) != 0) continue;
        var buf: [512]u8 = undefined;
        const count = std.os.linux.ioctl(file.handle, c.EVIOCGNAME(buf.len), @intFromPtr(&buf));
        if (std.os.linux.E.init(count) != .SUCCESS) continue;

        const id = try std.fmt.allocPrint(allocator, "{x:0>4}{x:0>4}-{}", .{ info.vendor, info.product, index });
        errdefer allocator.free(id);
        const name = try allocator.dupe(u8, buf[0..count]);
        errdefer allocator.free(name);
        try list.append(.{ .handle = index, .id = id, .name = name });
    }

    return list.toOwnedSlice();
}

pub fn freeJoysticks(allocator: std.mem.Allocator, list: []wio.JoystickInfo) void {
    for (list) |info| {
        allocator.free(info.id);
        allocator.free(info.name);
    }
    allocator.free(list);
}

pub fn resolveJoystickId(id: []const u8) ?usize {
    if (id.len < 10 or id[8] != '-') return null;
    const target_vendor = std.fmt.parseUnsigned(u16, id[0..4], 16) catch return null;
    const target_product = std.fmt.parseUnsigned(u16, id[4..8], 16) catch return null;
    const target_index = std.fmt.parseUnsigned(u16, id[9..], 10) catch return null;

    const path = std.fmt.allocPrintZ(wio.allocator, "/dev/input/event{}", .{target_index}) catch return null;
    defer wio.allocator.free(path);

    if (std.fs.openFileAbsoluteZ(path, .{})) |file| {
        defer file.close();
        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) == 0) {
            if (info.vendor == target_vendor and info.product == target_product) {
                return target_index;
            }
        }
    } else |_| {}

    var iter = JoystickIterator.init() catch return null;
    while (iter.nextFile() catch return null) |value| {
        const file, const index = value;
        defer file.close();
        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(file.handle, c.EVIOCGID, @intFromPtr(&info)) == 0) {
            if (info.vendor == target_vendor and info.product == target_product) {
                return index;
            }
        }
    }

    return null;
}

fn EVIOCGABS(abs: u32) u32 {
    return 0x80184540 | abs;
}

pub fn openJoystick(handle: usize) !Joystick {
    const path = try std.fmt.allocPrintZ(wio.allocator, "/dev/input/event{}", .{handle});
    defer wio.allocator.free(path);

    const result = std.os.linux.open(path, .{ .NONBLOCK = true }, 0);
    switch (std.os.linux.E.init(result)) {
        .SUCCESS => {},
        .ACCES => {
            permissionWarning();
            return error.Unavailable;
        },
        else => return error.Unavailable,
    }
    if (std.os.linux.E.init(result) != .SUCCESS) return error.Unavailable;
    const fd: i32 = @intCast(result);
    errdefer _ = std.os.linux.close(fd);

    var abs_bits = std.bit_set.ArrayBitSet(u8, c.ABS_CNT).initEmpty();
    if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_ABS, @sizeOf(@TypeOf(abs_bits.masks))), @intFromPtr(&abs_bits.masks))) != .SUCCESS) return error.Unavailable;
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
    errdefer wio.allocator.free(axis_info);
    for (abs_map, 0..) |index, code| {
        if (index != 0) {
            if (code < c.ABS_HAT0X or code > c.ABS_HAT3Y) {
                if (std.os.linux.ioctl(fd, EVIOCGABS(@intCast(code)), @intFromPtr(&axis_info[index - 1])) != 0) return error.Unavailable;
            }
        }
    }

    var key_bits = std.bit_set.ArrayBitSet(u8, c.KEY_CNT).initEmpty();
    if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_KEY, @sizeOf(@TypeOf(key_bits.masks))), @intFromPtr(&key_bits.masks))) != .SUCCESS) return error.Unavailable;
    var key_iter = key_bits.iterator(.{});
    var key_map = [1]u16{0} ** c.KEY_CNT;
    var button_count: u16 = 0;
    while (key_iter.next()) |i| {
        button_count += 1;
        key_map[i] = button_count;
    }

    const axes = try wio.allocator.alloc(u16, axis_count);
    errdefer wio.allocator.free(axes);
    @memset(axes, 0xFFFF / 2);
    const hats = try wio.allocator.alloc(wio.Hat, hat_count);
    errdefer wio.allocator.free(hats);
    const buttons = try wio.allocator.alloc(bool, button_count);
    errdefer wio.allocator.free(buttons);

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
        wio.allocator.free(self.axis_info);
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

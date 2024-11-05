const std = @import("std");
const wio = @import("../../wio.zig");
const c = @cImport({
    @cInclude("linux/input.h");
    @cInclude("sys/inotify.h");
});
const log = std.log.scoped(.wio);

var maybe_dir: ?std.fs.Dir = null;
var inotify: i32 = 0;

pub fn init() !void {
    maybe_dir = std.fs.openDirAbsoluteZ("/dev/input/by-path", .{ .iterate = true }) catch |err| {
        log.err("could not open {s}: {s}", .{ "/dev/input/by-path", @errorName(err) });
        return;
    };

    if (wio.init_options.joystickCallback) |callback| {
        var iter = JoystickIterator.init();
        while (iter.next()) |device| callback(.{ .backend = device });

        inotify = c.inotify_init1(c.IN_NONBLOCK | c.IN_CLOEXEC);
        _ = c.inotify_add_watch(inotify, "/dev/input/by-path", c.IN_CREATE);
    }
}

pub fn deinit() void {
    if (maybe_dir == null) return;
    if (wio.init_options.joystickCallback) |_| {
        _ = std.os.linux.close(inotify);
    }
}

pub fn update() void {
    if (maybe_dir == null) return;
    if (wio.init_options.joystickCallback) |callback| {
        var buf: [@sizeOf(c.inotify_event) + std.os.linux.NAME_MAX + 1]u8 align(@alignOf(c.inotify_event)) = undefined;
        while (std.os.linux.E.init(std.os.linux.read(inotify, &buf, buf.len)) == .SUCCESS) {
            const event: *c.inotify_event = @ptrCast(&buf);
            const name = std.mem.sliceTo(event.name()[0..event.len], 0);
            if (nameToDevice(name)) |device| {
                callback(.{ .backend = device });
            }
        }
    }
}

pub const JoystickIterator = struct {
    iter: std.fs.Dir.Iterator,

    pub fn init() JoystickIterator {
        return .{ .iter = if (maybe_dir) |dir| dir.iterate() else undefined };
    }

    pub fn next(self: *JoystickIterator) ?JoystickDevice {
        if (maybe_dir == null) return null;
        while (self.iter.next() catch return self.next()) |entry| {
            if (nameToDevice(entry.name)) |device| {
                return device;
            }
        }
        return null;
    }
};

var permission_warning = false;

fn nameToDevice(name: []const u8) ?JoystickDevice {
    if (std.mem.endsWith(u8, name, "-event-joystick")) {
        var buf: [std.fs.max_path_bytes + 1:0]u8 = undefined;
        const link = maybe_dir.?.readLink(name, &buf) catch return null;
        const prefix = "../event";
        if (std.mem.startsWith(u8, link, prefix)) {
            buf[link.len] = 0;
            const result = std.os.linux.openat(maybe_dir.?.fd, &buf, .{ .NONBLOCK = true }, 0);
            switch (std.os.linux.E.init(result)) {
                .SUCCESS => {},
                .ACCES => {
                    if (!permission_warning) {
                        log.warn("could not access joystick", .{});
                        permission_warning = true;
                    }
                    return null;
                },
                else => return null,
            }
            return .{ .fd = @intCast(result) };
        }
    }
    return null;
}

fn EVIOCGABS(abs: u32) u32 {
    return 0x80184540 | abs;
}

pub const JoystickDevice = struct {
    fd: i32,

    pub fn release(self: JoystickDevice) void {
        _ = std.os.linux.close(self.fd);
    }

    pub fn open(self: JoystickDevice) !Joystick {
        const result = std.os.linux.dup(self.fd);
        if (std.os.linux.E.init(result) != .SUCCESS) return error.Unexpected;
        const fd: i32 = @intCast(result);
        errdefer _ = std.os.linux.close(fd);

        var abs_bits = std.bit_set.ArrayBitSet(u8, c.ABS_CNT).initEmpty();
        if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_ABS, @sizeOf(@TypeOf(abs_bits.masks))), @intFromPtr(&abs_bits.masks))) != .SUCCESS) return error.Unexpected;
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
                    if (std.os.linux.ioctl(fd, EVIOCGABS(@intCast(code)), @intFromPtr(&axis_info[index - 1])) != 0) return error.Unexpected;
                }
            }
        }

        var key_bits = std.bit_set.ArrayBitSet(u8, c.KEY_CNT).initEmpty();
        if (std.os.linux.E.init(std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_KEY, @sizeOf(@TypeOf(key_bits.masks))), @intFromPtr(&key_bits.masks))) != .SUCCESS) return error.Unexpected;
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
        @memset(hats, .{});
        const buttons = try wio.allocator.alloc(bool, button_count);
        errdefer wio.allocator.free(buttons);
        @memset(buttons, false);

        return .{ .fd = fd, .abs_map = abs_map, .key_map = key_map, .axis_info = axis_info, .axes = axes, .hats = hats, .buttons = buttons };
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) !?[]u8 {
        var info: c.input_id = undefined;
        if (std.os.linux.ioctl(self.fd, c.EVIOCGID, @intFromPtr(&info)) != 0) return null;
        return try std.fmt.allocPrint(allocator, "{x:0>4}{x:0>4}", .{ info.vendor, info.product });
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        var buf: [512]u8 = undefined;
        const count = std.os.linux.ioctl(self.fd, c.EVIOCGNAME(buf.len), @intFromPtr(&buf));
        if (std.os.linux.E.init(count) != .SUCCESS) return "";
        return allocator.dupe(u8, buf[0..count]);
    }
};

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

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        var event: c.input_event = undefined;
        while (true) {
            switch (std.os.linux.E.init(std.os.linux.read(self.fd, @ptrCast(&event), @sizeOf(c.input_event)))) {
                .SUCCESS => {},
                .AGAIN => break,
                .NODEV => return null,
                else => return null,
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

const std = @import("std");
const build_options = @import("build_options");
const wio = @import("../../wio.zig");
const internal = @import("../../wio.internal.zig");
const unix = @import("../../unix.zig");
const DynLib = @import("../DynLib.zig");
const h = @cImport({
    @cInclude("linux/input.h");
    @cInclude("libudev.h");
});
const log = std.log.scoped(.wio);

var imports: extern struct {
    udev_new: *const @TypeOf(h.udev_new),
    udev_unref: *const @TypeOf(h.udev_unref),
    udev_enumerate_new: *const @TypeOf(h.udev_enumerate_new),
    udev_enumerate_unref: *const @TypeOf(h.udev_enumerate_unref),
    udev_enumerate_add_match_property: *const @TypeOf(h.udev_enumerate_add_match_property),
    udev_enumerate_scan_devices: *const @TypeOf(h.udev_enumerate_scan_devices),
    udev_enumerate_get_list_entry: *const @TypeOf(h.udev_enumerate_get_list_entry),
    udev_list_entry_get_next: *const @TypeOf(h.udev_list_entry_get_next),
    udev_list_entry_get_name: *const @TypeOf(h.udev_list_entry_get_name),
    udev_monitor_new_from_netlink: *const @TypeOf(h.udev_monitor_new_from_netlink),
    udev_monitor_unref: *const @TypeOf(h.udev_monitor_unref),
    udev_monitor_get_fd: *const @TypeOf(h.udev_monitor_get_fd),
    udev_monitor_filter_add_match_subsystem_devtype: *const @TypeOf(h.udev_monitor_filter_add_match_subsystem_devtype),
    udev_monitor_enable_receiving: *const @TypeOf(h.udev_monitor_enable_receiving),
    udev_monitor_receive_device: *const @TypeOf(h.udev_monitor_receive_device),
    udev_device_unref: *const @TypeOf(h.udev_device_unref),
    udev_device_get_property_value: *const @TypeOf(h.udev_device_get_property_value),
    udev_device_get_devpath: *const @TypeOf(h.udev_device_get_devpath),
} = undefined;
const c = if (build_options.system_integration) h else &imports;

var libudev: DynLib = undefined;
var udev: *h.udev = undefined;
var monitor: *h.udev_monitor = undefined;

pub fn init() !void {
    try DynLib.load(&imports, &.{.{ .handle = &libudev, .name = "libudev.so.1" }});
    errdefer libudev.close();

    udev = c.udev_new() orelse return error.Unexpected;
    errdefer _ = c.udev_unref(udev);

    if (internal.init_options.joystickConnectedFn) |callback| {
        var iter = JoystickDeviceIterator.init();
        while (iter.next()) |device| callback(.{ .backend = device });

        monitor = c.udev_monitor_new_from_netlink(udev, "udev") orelse return error.Unexpected;
        errdefer _ = c.udev_monitor_unref(monitor);
        try unix.pollfds.append(internal.allocator, .{ .fd = c.udev_monitor_get_fd(monitor), .events = std.c.POLL.IN, .revents = undefined });
        _ = c.udev_monitor_filter_add_match_subsystem_devtype(monitor, "input", null);
        _ = c.udev_monitor_enable_receiving(monitor);
    }
}

pub fn deinit() void {
    if (internal.init_options.joystickConnectedFn != null) _ = c.udev_monitor_unref(monitor);
    _ = c.udev_unref(udev);
    libudev.close();
}

pub fn update() void {
    if (internal.init_options.joystickConnectedFn) |callback| {
        while (c.udev_monitor_receive_device(monitor)) |device| {
            defer _ = c.udev_device_unref(device);
            const joystick = std.mem.sliceTo(c.udev_device_get_property_value(device, "ID_INPUT_JOYSTICK") orelse continue, 0);
            if (std.mem.eql(u8, joystick, "1")) {
                const path = std.mem.sliceTo(c.udev_device_get_devpath(device) orelse continue, 0);
                callback(.{ .backend = pathToDevice(path) orelse continue });
            }
        }
    }
}

pub const JoystickDeviceIterator = struct {
    enumerate: ?*h.udev_enumerate = null,
    entry: ?*h.udev_list_entry = undefined,

    pub fn init() JoystickDeviceIterator {
        if (c.udev_enumerate_new(udev)) |enumerate| {
            if (c.udev_enumerate_add_match_property(enumerate, "ID_INPUT_JOYSTICK", "1") >= 0) {
                if (c.udev_enumerate_scan_devices(enumerate) >= 0) {
                    if (c.udev_enumerate_get_list_entry(enumerate)) |entry| {
                        return .{ .enumerate = enumerate, .entry = entry };
                    }
                }
            }
            _ = c.udev_enumerate_unref(enumerate);
        }
        return .{};
    }

    pub fn deinit(self: *JoystickDeviceIterator) void {
        if (self.enumerate == null) return;
        _ = c.udev_enumerate_unref(self.enumerate);
    }

    pub fn next(self: *JoystickDeviceIterator) ?JoystickDevice {
        if (self.enumerate == null) return null;
        if (self.entry == null) return null;
        const name = std.mem.sliceTo(c.udev_list_entry_get_name(self.entry), 0);
        self.entry = c.udev_list_entry_get_next(self.entry);
        return pathToDevice(name) orelse self.next();
    }
};

fn pathToDevice(path: []const u8) ?JoystickDevice {
    const basename = path[std.mem.lastIndexOfScalar(u8, path, '/').? + 1 ..];
    if (!std.mem.startsWith(u8, basename, "event")) return null;

    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "/dev/input/{s}", .{basename}) catch return null;
    const result = std.os.linux.open(&buf, .{ .NONBLOCK = true }, 0);
    if (std.os.linux.E.init(result) != .SUCCESS) return null;
    return .{ .fd = @intCast(result) };
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

        var abs_bits = std.bit_set.ArrayBitSet(u8, h.ABS_CNT).initEmpty();
        if (std.os.linux.E.init(std.os.linux.ioctl(fd, h.EVIOCGBIT(h.EV_ABS, @sizeOf(@TypeOf(abs_bits.masks))), @intFromPtr(&abs_bits.masks))) != .SUCCESS) return error.Unexpected;
        var abs_iter = abs_bits.iterator(.{});
        var abs_map = [1]u8{0} ** h.ABS_CNT;
        var axis_count: u8 = 0;
        var hat_count: u8 = 0;
        while (abs_iter.next()) |i| {
            if (i < h.ABS_HAT0X or i > h.ABS_HAT3Y) {
                axis_count += 1;
                abs_map[i] = axis_count;
            } else {
                hat_count += 1;
                abs_map[i] = hat_count;
                abs_map[i + 1] = hat_count;
                _ = abs_iter.next();
            }
        }

        const axis_info = try internal.allocator.alloc(h.input_absinfo, axis_count);
        errdefer internal.allocator.free(axis_info);
        for (abs_map, 0..) |index, code| {
            if (index != 0) {
                if (code < h.ABS_HAT0X or code > h.ABS_HAT3Y) {
                    // EVIOCGABS typing requires a type wider than c_uint
                    if (std.os.linux.ioctl(fd, @intCast(h.EVIOCGABS(@as(u64, @intCast(code)))), @intFromPtr(&axis_info[index - 1])) != 0) return error.Unexpected;
                }
            }
        }

        var key_bits = std.bit_set.ArrayBitSet(u8, h.KEY_CNT).initEmpty();
        if (std.os.linux.E.init(std.os.linux.ioctl(fd, h.EVIOCGBIT(h.EV_KEY, @sizeOf(@TypeOf(key_bits.masks))), @intFromPtr(&key_bits.masks))) != .SUCCESS) return error.Unexpected;
        var key_iter = key_bits.iterator(.{});
        var key_map = [1]u16{0} ** h.KEY_CNT;
        var button_count: u16 = 0;
        while (key_iter.next()) |i| {
            button_count += 1;
            key_map[i] = button_count;
        }

        const axes = try internal.allocator.alloc(u16, axis_count);
        errdefer internal.allocator.free(axes);
        @memset(axes, 0xFFFF / 2);
        const hats = try internal.allocator.alloc(wio.Hat, hat_count);
        errdefer internal.allocator.free(hats);
        @memset(hats, .{});
        const buttons = try internal.allocator.alloc(bool, button_count);
        errdefer internal.allocator.free(buttons);
        @memset(buttons, false);

        try unix.pollfds.append(internal.allocator, .{ .fd = fd, .events = std.c.POLL.IN, .revents = undefined });

        return .{ .fd = fd, .abs_map = abs_map, .key_map = key_map, .axis_info = axis_info, .axes = axes, .hats = hats, .buttons = buttons };
    }

    pub fn getId(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        var info: h.input_id = undefined;
        if (std.os.linux.ioctl(self.fd, h.EVIOCGID, @intFromPtr(&info)) != 0) return error.Unexpected;
        return std.fmt.allocPrint(allocator, "{x:0>4}{x:0>4}", .{ info.vendor, info.product });
    }

    pub fn getName(self: JoystickDevice, allocator: std.mem.Allocator) ![]u8 {
        var name: [512]u8 = undefined;
        var name_len = std.os.linux.ioctl(self.fd, h.EVIOCGNAME(name.len), @intFromPtr(&name));
        if (std.os.linux.E.init(name_len) != .SUCCESS) return error.Unexpected;
        name_len -= 1; // null terminator
        return allocator.dupe(u8, name[0..name_len]);
    }
};

pub const Joystick = struct {
    fd: i32,
    abs_map: [h.ABS_CNT]u8,
    key_map: [h.KEY_CNT]u16,
    axis_info: []h.input_absinfo,
    axes: []u16,
    hats: []wio.Hat,
    buttons: []bool,

    pub fn close(self: *Joystick) void {
        for (unix.pollfds.items, 0..) |pollfd, i| {
            if (pollfd.fd == self.fd) {
                _ = unix.pollfds.swapRemove(i);
                break;
            }
        }

        internal.allocator.free(self.buttons);
        internal.allocator.free(self.hats);
        internal.allocator.free(self.axes);
        internal.allocator.free(self.axis_info);

        _ = std.os.linux.close(self.fd);
    }

    pub fn poll(self: *Joystick) ?wio.JoystickState {
        var event: h.input_event = undefined;
        while (true) {
            switch (std.os.linux.E.init(std.os.linux.read(self.fd, @ptrCast(&event), @sizeOf(h.input_event)))) {
                .SUCCESS => {},
                .AGAIN => break,
                .NODEV => return null,
                else => return null,
            }
            switch (event.type) {
                h.EV_ABS => {
                    const index = self.abs_map[event.code];
                    if (index != 0) {
                        if (event.code < h.ABS_HAT0X or event.code > h.ABS_HAT3Y) {
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
                h.EV_KEY => {
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

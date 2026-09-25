const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const log = std.log.scoped(.wio);
const DynLib = @This();

handle: if (build_options.system_integration) void else std.DynLib,

pub fn open(comptime versioned_name: [:0]const u8) !DynLib {
    if (build_options.system_integration) {
        return .{ .handle = {} };
    } else {
        const name = switch (builtin.os.tag) {
            .openbsd, .netbsd => versioned_name[0..comptime std.mem.findScalarLast(u8, versioned_name, '.').?] ++ "",
            else => versioned_name,
        };

        return .{
            .handle = std.DynLib.openZ(name) catch |err| {
                log.err("could not load {s}: {s}", .{ name, @errorName(err) });
                return err;
            },
        };
    }
}

pub fn close(self: *DynLib) void {
    if (!build_options.system_integration) self.handle.close();
}

pub fn lookup(self: *DynLib, comptime T: type, name: [:0]const u8) ?T {
    return self.handle.lookup(T, name);
}

pub const Lib = struct {
    handle: *DynLib,
    name: [:0]const u8,
    prefix: []const u8 = "",
    exclude: []const u8 = "",
};

pub fn load(c: anytype, comptime libs: []const Lib) !void {
    if (build_options.system_integration) return;

    var succeeded: usize = 0;
    errdefer for (0..succeeded) |i| {
        libs[i].handle.close();
    };
    inline for (libs) |lib| {
        lib.handle.* = try open(lib.name);
        succeeded += 1;
    }

    const names = comptime std.meta.fieldNames(@TypeOf(c.*));
    const table: *[names.len]?*const fn () void = @ptrCast(c);
    for (names, table) |name, *out| {
        for (libs) |lib| {
            if (lib.exclude.len > 0 and std.mem.startsWith(u8, name, lib.exclude)) continue;
            if (std.mem.startsWith(u8, name, lib.prefix)) {
                out.* = lib.handle.lookup(*const fn () void, name) orelse {
                    log.err("could not load {s}", .{name});
                    return error.Unexpected;
                };
                break;
            }
        }
    }
}

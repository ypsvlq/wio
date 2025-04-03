const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.wio);

pub const Lib = struct {
    handle: *std.DynLib,
    name: [:0]const u8,
    prefix: []const u8 = "",
    exclude: []const u8 = "",
};

pub fn open(comptime name: [:0]const u8) !std.DynLib {
    return std.DynLib.openZ(
        if (builtin.os.tag == .openbsd or builtin.os.tag == .netbsd)
            name[0..comptime std.mem.lastIndexOfScalar(u8, name, '.').?] ++ ""
        else
            name,
    );
}

pub fn load(c: anytype, comptime libs: []const Lib) !void {
    var succeeded: usize = 0;
    errdefer for (0..succeeded) |i| {
        libs[i].handle.close();
    };
    inline for (libs) |lib| {
        lib.handle.* = try open(lib.name);
        succeeded += 1;
    }

    const names = std.meta.fieldNames(@TypeOf(c.*));
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

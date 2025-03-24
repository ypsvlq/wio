const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.wio);

pub const Lib = struct {
    handle: *std.DynLib,
    name: [:0]const u8,
    prefix: []const u8 = "",
    predicate: bool = true,
};

pub fn open(name: [:0]const u8) !std.DynLib {
    return std.DynLib.openZ(
        if (builtin.os.tag == .openbsd or builtin.os.tag == .netbsd)
            name[0 .. std.mem.indexOfScalar(u8, name, '.').? + 3]
        else
            name,
    );
}

pub fn load(c: anytype, libs: []const Lib) !void {
    var succeeded: usize = 0;
    errdefer for (0..succeeded) |i| {
        if (libs[i].predicate) libs[i].handle.close();
    };
    for (libs) |lib| {
        if (lib.predicate) {
            lib.handle.* = try open(lib.name);
        }
        succeeded += 1;
    }

    const names = std.meta.fieldNames(@TypeOf(c.*));
    const table: *[names.len]?*const fn () void = @ptrCast(c);
    for (names, table) |name, *out| {
        for (libs) |lib| {
            if (std.mem.startsWith(u8, name, lib.prefix)) {
                if (!lib.predicate) break;
                out.* = lib.handle.lookup(*const fn () void, name) orelse {
                    log.err("could not load {s}", .{name});
                    return error.Unexpected;
                };
                break;
            }
        }
    }
}

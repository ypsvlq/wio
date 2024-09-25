const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.wio);

pub const Lib = struct {
    handle: *std.DynLib,
    name: []const u8,
    prefix: []const u8 = "",
    predicate: bool = true,
};

const sonames = if (builtin.os.tag == .openbsd or builtin.os.tag == .netbsd) false else true;

pub fn loadLibs(c: anytype, libs: []const Lib) !void {
    var succeeded: usize = 0;
    errdefer for (0..succeeded) |i| {
        if (libs[i].predicate) libs[i].handle.close();
    };
    for (libs) |lib| {
        if (lib.predicate) {
            lib.handle.* = try std.DynLib.open(if (sonames) lib.name else lib.name[0..std.mem.lastIndexOfScalar(u8, lib.name, '.').?]);
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

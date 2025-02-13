const std = @import("std");

extern "log" fn write([*]const u8, usize) void;
extern "log" fn flush() void;

fn logWriteFn(_: void, bytes: []const u8) !usize {
    write(bytes.ptr, bytes.len);
    return bytes.len;
}

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const writer = std.io.GenericWriter(void, error{}, logWriteFn){ .context = {} };
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    flush();
}

const std = @import("std");

extern "log" fn write([*]const u8, usize) void;
extern "log" fn flush() void;

fn drain(_: *std.Io.Writer, data: []const []const u8, _: usize) !usize {
    write(data[0].ptr, data[0].len);
    return data[0].len;
}

var writer = std.Io.Writer{
    .vtable = &.{ .drain = drain },
    .buffer = &.{},
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    flush();
}

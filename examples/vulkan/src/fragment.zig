const std = @import("std");
const gpu = std.gpu;

const v_color = @extern(*addrspace(.input) @Vector(3, f32), .{ .name = "v_color", .decoration = .{ .location = 0 } });
const f_color = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "f_color", .decoration = .{ .location = 0 } });

export fn main() callconv(.spirv_fragment) void {
    f_color.* = .{ v_color[0], v_color[1], v_color[2], 1 };
}

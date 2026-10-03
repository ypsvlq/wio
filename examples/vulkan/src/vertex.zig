const std = @import("std");
const spirv = std.spirv;

const v_color = @extern(*addrspace(.output) @Vector(3, f32), .{ .name = "v_color", .decoration = .{ .location = 0 } });

const positions: [3]@Vector(4, f32) = .{
    .{ 0, -0.5, 0, 1 },
    .{ 0.5, 0.5, 0, 1 },
    .{ -0.5, 0.5, 0, 1 },
};

const colors: [3]@Vector(3, f32) = .{
    .{ 1, 0, 0 },
    .{ 0, 1, 0 },
    .{ 0, 0, 1 },
};

export fn main() callconv(.spirv_vertex) void {
    spirv.position_out.* = positions[spirv.vertex_index];
    v_color.* = colors[spirv.vertex_index];
}

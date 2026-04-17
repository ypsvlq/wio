const std = @import("std");
const gpu = std.gpu;

const v_color = @extern(*addrspace(.output) @Vector(3, f32), .{ .name = "v_color", .decoration = .{ .location = 0 } });

const positions = [3]@Vector(4, f32){
    .{ 0, -0.5, 0, 1 },
    .{ 0.5, 0.5, 0, 1 },
    .{ -0.5, 0.5, 0, 1 },
};

const colors = [_]@Vector(3, f32){
    .{ 1, 0, 0 },
    .{ 0, 1, 0 },
    .{ 0, 0, 1 },
};

export fn main() callconv(.spirv_vertex) void {
    gpu.position_out.* = positions[gpu.vertex_index];
    v_color.* = colors[gpu.vertex_index];
}

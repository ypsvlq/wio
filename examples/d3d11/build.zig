const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
    });

    const win32 = b.dependency("win32", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "wio", .module = wio.module("wio") },
            .{ .name = "win32", .module = win32.module("win32") },
        },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "d3d11",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

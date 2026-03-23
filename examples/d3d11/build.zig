const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("wio", wio.module("wio"));

    const win32 = b.dependency("win32", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("win32", win32.module("win32"));

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

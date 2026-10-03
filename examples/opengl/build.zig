const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_opengl = true,
        .macos_sdk_path = b.option([]const u8, "macos_sdk_path", "Path to the macOS SDK"),
        .unix_backends = b.option([]const u8, "unix_backends", "List of enabled wio backends"),
    });

    const opengl = b.dependency("opengl", .{
        .major_version = 4,
        .minor_version = 1,
        .profile = .core,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "wio", .module = wio.module("wio") },
            .{ .name = "gl", .module = opengl.module("opengl") },
        },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "opengl",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const macos_sdk_path = b.option([]const u8, "macos_sdk_path", "Path to the macOS SDK");

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_framebuffer = true,
        .macos_sdk_path = macos_sdk_path,
    });

    const exe = b.addExecutable(.{
        .name = "notch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "wio", .module = wio.module("wio") },
            },
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

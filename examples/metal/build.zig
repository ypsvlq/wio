const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const macos_sdk_path = b.option([]const u8, "macos_sdk_path", "Path to the macOS SDK");

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
        .macos_sdk_path = macos_sdk_path,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "wio", .module = wio.module("wio") },
        },
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addCSourceFile(.{ .file = b.path("src/metal.m") });

    if (macos_sdk_path) |sdk| {
        exe_mod.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System", "Library", "Frameworks" }) });
        exe_mod.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr", "include" }) });
    }
    exe_mod.linkFramework("Metal", .{});
    exe_mod.linkFramework("QuartzCore", .{});

    const exe = b.addExecutable(.{
        .name = "metal",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

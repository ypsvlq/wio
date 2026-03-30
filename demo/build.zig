const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_opengl = true,
        .enable_joystick = true,
        .enable_audio = true,
        .unix_backends = b.option([]const u8, "unix_backends", "List of enabled wio backends"),
    });
    exe_mod.addImport("wio", wio.module("wio"));

    const opengl = b.dependency("opengl", .{
        .api = .gles2,
        .major_version = 2,
    });
    exe_mod.addImport("gl", opengl.module("opengl"));

    const exe = b.addExecutable(.{
        .name = "demo",
        .root_module = exe_mod,
        // https://github.com/ziglang/zig/issues/24140
        .use_llvm = true,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

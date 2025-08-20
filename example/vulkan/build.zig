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
        .features = "vulkan",
        .unix_backends = b.option([]const u8, "unix_backends", "List of enabled wio backends"),
    });
    exe_mod.addImport("wio", wio.module("wio"));

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan", .{ .registry = vulkan_headers.path("registry/vk.xml") });
    exe_mod.addImport("vulkan", vulkan.module("vulkan-zig"));

    const exe = b.addExecutable(.{
        .name = "vulkan",
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

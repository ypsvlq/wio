const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
    });

    const vertex = b.addObject(.{
        .name = "vertex",
        .root_module = b.addModule("vertex", .{
            .root_source_file = b.path("src/vertex.zig"),
            .target = spirv_target,
            .optimize = optimize,
        }),
        .use_llvm = false,
    });

    const fragment = b.addObject(.{
        .name = "fragment",
        .root_module = b.addModule("fragment", .{
            .root_source_file = b.path("src/fragment.zig"),
            .target = spirv_target,
            .optimize = optimize,
        }),
        .use_llvm = false,
    });

    const wio = b.dependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_vulkan = true,
        .unix_backends = b.option([]const u8, "unix_backends", "List of enabled wio backends"),
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{});

    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "wio", .module = wio.module("wio") },
            .{ .name = "vulkan", .module = vulkan.module("vulkan-zig") },
            .{ .name = "vertex", .module = b.createModule(.{ .root_source_file = vertex.getEmittedBin() }) },
            .{ .name = "fragment", .module = b.createModule(.{ .root_source_file = fragment.getEmittedBin() }) },
        },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

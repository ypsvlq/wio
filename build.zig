const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("wio", .{
        .root_source_file = b.path("src/wio.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (target.result.os.tag) {
        .windows => {
            if (b.lazyDependency("win32", .{ .target = target, .optimize = optimize })) |win32| {
                module.addImport("win32", win32.module("win32"));
            }
        },
        .macos => {
            if (b.lazyDependency("glfw", .{})) |glfw| {
                module.addCSourceFiles(.{ .root = glfw.path("src"), .files = glfw_files, .flags = &.{"-D_GLFW_COCOA"} });
                module.addIncludePath(glfw.path("include"));
            }
            if (b.lazyImport(@This(), "xcode_frameworks")) |xcode_frameworks| {
                xcode_frameworks.addPaths(module);
            }
            module.linkFramework("Cocoa", .{});
            module.linkFramework("IOKit", .{});
        },
        .linux, .openbsd, .netbsd, .freebsd => {
            module.link_libc = true;
            if (b.lazyDependency("x11_headers", .{})) |x11_headers| {
                module.addIncludePath(x11_headers.path("."));
            }
        },
        else => {
            if (target.result.isWasm()) {
                module.export_symbol_names = &.{"wioLoop"};
            }
        },
    }

    if (b.option(bool, "win32_manifest", "Embed application manifest (default: true)") orelse true) {
        module.addWin32ResourceFile(.{ .file = b.path("src/win32.rc") });
    }

    const exe = b.addExecutable(.{
        .name = "wio",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("wio", module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const glfw_files: []const []const u8 = &.{
    "cocoa_init.m",
    "cocoa_joystick.m",
    "cocoa_monitor.m",
    "cocoa_time.c",
    "cocoa_window.m",
    "context.c",
    "egl_context.c",
    "init.c",
    "input.c",
    "monitor.c",
    "nsgl_context.m",
    "null_init.c",
    "null_joystick.c",
    "null_monitor.c",
    "null_window.c",
    "osmesa_context.c",
    "platform.c",
    "posix_module.c",
    "posix_thread.c",
    "vulkan.c",
    "window.c",
};

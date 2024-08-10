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
        .linux, .openbsd => {
            module.link_libc = true;
            if (b.lazyDependency("glfw", .{})) |glfw| {
                module.addCSourceFiles(.{ .root = glfw.path("src"), .files = glfw_files, .flags = &.{"-D_GLFW_X11"} });
                module.addIncludePath(glfw.path("include"));
            }
            if (b.lazyDependency("x11_headers", .{ .target = target, .optimize = optimize })) |x11_headers| {
                module.linkLibrary(x11_headers.artifact("x11-headers"));
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
        else => {},
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
    "glx_context.c",
    "init.c",
    "input.c",
    "linux_joystick.c",
    "monitor.c",
    "nsgl_context.m",
    "null_init.c",
    "null_joystick.c",
    "null_monitor.c",
    "null_window.c",
    "osmesa_context.c",
    "platform.c",
    "posix_module.c",
    "posix_poll.c",
    "posix_thread.c",
    "posix_time.c",
    "vulkan.c",
    "window.c",
    "wl_init.c",
    "wl_monitor.c",
    "wl_window.c",
    "x11_init.c",
    "x11_monitor.c",
    "x11_window.c",
    "xkb_unicode.c",
};

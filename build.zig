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
            module.addCSourceFile(.{ .file = b.path("src/macos.m"), .flags = &.{ "-fobjc-arc", "-Wno-deprecated-declarations" } });
            if (b.lazyDependency("xcode_frameworks", .{})) |xcode_frameworks| {
                module.addSystemFrameworkPath(xcode_frameworks.path("Frameworks"));
                module.addSystemIncludePath(xcode_frameworks.path("include"));
                module.addLibraryPath(xcode_frameworks.path("lib"));
            }
            module.linkFramework("Cocoa", .{});
            module.linkFramework("QuartzCore", .{});
            module.linkFramework("IOKit", .{});
            module.linkFramework("CoreAudio", .{});
            module.linkFramework("AudioUnit", .{});
            module.linkFramework("AudioToolbox", .{});
        },
        .linux, .openbsd, .netbsd, .freebsd, .dragonfly => |tag| {
            module.link_libc = true;
            if (b.lazyDependency("unix_headers", .{})) |unix_headers| {
                module.addIncludePath(unix_headers.path("."));
            }
            module.addCSourceFile(.{ .file = b.path("src/unix/wayland.c") });
            if (tag == .openbsd) module.linkSystemLibrary("sndio", .{});

            if (b.systemIntegrationOption("x11", .{})) {
                module.linkSystemLibrary("x11", .{});
                module.linkSystemLibrary("xcursor", .{});
            }

            if (b.systemIntegrationOption("gl", .{})) module.linkSystemLibrary("gl", .{});

            if (b.systemIntegrationOption("wayland", .{})) {
                module.linkSystemLibrary("wayland-client", .{});
                module.linkSystemLibrary("xkbcommon", .{});
                module.linkSystemLibrary("decor-0", .{});
            }

            if (b.systemIntegrationOption("egl", .{})) {
                module.linkSystemLibrary("wayland-egl", .{});
                module.linkSystemLibrary("egl", .{});
            }

            if (b.systemIntegrationOption("udev", .{}))
                module.linkSystemLibrary("libudev", .{});

            if (b.systemIntegrationOption("pulse", .{})) module.linkSystemLibrary("pulse", .{});

            if (b.systemIntegrationOption("vulkan", .{})) module.linkSystemLibrary("vulkan", .{});
        },
        else => {
            if (target.result.isWasm()) {
                module.export_symbol_names = &.{ "wioLoop", "wioJoystick" };
            }
        },
    }

    if (b.option(bool, "win32_manifest", "Embed application manifest (default: true)") orelse true) {
        module.addWin32ResourceFile(.{ .file = b.path("src/win32.rc") });
    }

    const options = b.addOptions();
    options.addOption([]const u8, "unix_backends", b.option([]const u8, "unix_backends", "Comma-separated list of backends (default: x11,wayland)") orelse "x11,wayland");
    module.addOptions("build_options", options);

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

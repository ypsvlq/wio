const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("wio", .{
        .root_source_file = b.path("src/wio.zig"),
        .target = target,
        .optimize = optimize,
    });

    var enable_opengl = false;
    var enable_vulkan = false;
    var enable_joystick = false;
    var enable_audio = false;

    const features = b.option([]const u8, "features", "Comma-separated list of enabled features (default: opengl,vulkan,joystick,audio)") orelse "opengl,vulkan,joystick,audio";
    var feature_iter = std.mem.splitScalar(u8, features, ',');
    while (feature_iter.next()) |feature| {
        if (std.mem.eql(u8, feature, "opengl")) {
            enable_opengl = true;
        } else if (std.mem.eql(u8, feature, "vulkan")) {
            enable_vulkan = true;
        } else if (std.mem.eql(u8, feature, "joystick")) {
            enable_joystick = true;
        } else if (std.mem.eql(u8, feature, "audio")) {
            enable_audio = true;
        } else {
            @panic("option 'features' is invalid");
        }
    }

    var enable_x11 = false;
    var enable_wayland = false;

    const unix_backends = b.option([]const u8, "unix_backends", "Comma-separated list of enabled backends (default: x11,wayland)") orelse "x11,wayland";
    var backend_iter = std.mem.splitScalar(u8, unix_backends, ',');
    while (backend_iter.next()) |feature| {
        if (std.mem.eql(u8, feature, "x11")) {
            enable_x11 = true;
        } else if (std.mem.eql(u8, feature, "wayland")) {
            enable_wayland = true;
        } else {
            @panic("option 'unix_backends' is invalid");
        }
    }

    const system_integration = b.systemIntegrationOption("wio", .{});
    const options = b.addOptions();
    options.addOption(bool, "opengl", enable_opengl);
    options.addOption(bool, "vulkan", enable_vulkan);
    options.addOption(bool, "joystick", enable_joystick);
    options.addOption(bool, "audio", enable_audio);
    options.addOption(bool, "x11", enable_x11);
    options.addOption(bool, "wayland", enable_wayland);
    options.addOption(bool, "system_integration", system_integration);
    module.addOptions("build_options", options);

    if (b.option(bool, "win32_manifest", "Embed application manifest (default: true)") orelse true) {
        module.addWin32ResourceFile(.{ .file = b.path("src/win32.rc") });
    }

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
            if (enable_joystick) {
                module.linkFramework("IOKit", .{});
            }
            if (enable_audio) {
                module.linkFramework("CoreAudio", .{});
                module.linkFramework("AudioUnit", .{});
                module.linkFramework("AudioToolbox", .{});
            }
        },
        .linux, .openbsd, .netbsd, .freebsd, .dragonfly => |tag| {
            module.link_libc = true;
            module.addCSourceFile(.{ .file = b.path("src/unix/wayland.c") });
            if (b.lazyDependency("unix_headers", .{})) |unix_headers| {
                module.addIncludePath(unix_headers.path("."));
            }

            if (tag == .openbsd) module.linkSystemLibrary("sndio", .{});

            if (system_integration) {
                if (enable_x11) {
                    module.linkSystemLibrary("x11", .{});
                    module.linkSystemLibrary("xcursor", .{});
                    if (enable_opengl) {
                        module.linkSystemLibrary("gl", .{});
                    }
                }
                if (enable_wayland) {
                    module.linkSystemLibrary("wayland-client", .{});
                    module.linkSystemLibrary("xkbcommon", .{});
                    module.linkSystemLibrary("libdecor-0", .{});
                    if (enable_opengl) {
                        module.linkSystemLibrary("wayland-egl", .{});
                        module.linkSystemLibrary("egl", .{});
                    }
                }
                if (enable_vulkan) {
                    module.linkSystemLibrary("vulkan", .{});
                }
                if (tag == .linux) {
                    if (enable_joystick) {
                        module.linkSystemLibrary("libudev", .{});
                    }
                    if (enable_audio) {
                        module.linkSystemLibrary("libpulse", .{});
                    }
                }
            }
        },
        else => {
            if (target.result.isWasm()) {
                module.export_symbol_names = &.{ "wioLoop", "wioJoystick" };
            }
        },
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

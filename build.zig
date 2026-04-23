const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("wio", .{
        .root_source_file = b.path("src/wio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const enable_framebuffer = b.option(bool, "enable_framebuffer", "Enable software framebuffer support (default: false)") orelse false;
    const enable_opengl = b.option(bool, "enable_opengl", "Enable OpenGL support (default: false)") orelse false;
    const enable_vulkan = b.option(bool, "enable_vulkan", "Enable Vulkan support (default: false)") orelse false;
    const enable_joystick = b.option(bool, "enable_joystick", "Enable joystick support (default: false)") orelse false;
    const enable_audio = b.option(bool, "enable_audio", "Enable audio support (default: false)") orelse false;

    var enable_x11 = false;
    var enable_wayland = false;

    const unix_backends = b.option([]const u8, "unix_backends", "List of enabled backends (default: x11,wayland)") orelse "x11,wayland";
    var backend_iter = std.mem.tokenizeScalar(u8, unix_backends, ',');
    while (backend_iter.next()) |backend| {
        if (std.mem.eql(u8, backend, "x11")) {
            enable_x11 = true;
        } else if (std.mem.eql(u8, backend, "wayland")) {
            enable_wayland = true;
        } else {
            @panic("option 'unix_backends' is invalid");
        }
    }

    const system_integration = b.systemIntegrationOption("wio", .{});
    const options = b.addOptions();
    options.addOption(bool, "framebuffer", enable_framebuffer);
    options.addOption(bool, "opengl", enable_opengl);
    options.addOption(bool, "vulkan", enable_vulkan);
    options.addOption(bool, "joystick", enable_joystick);
    options.addOption(bool, "audio", enable_audio);
    options.addOption(bool, "x11", enable_x11);
    options.addOption(bool, "wayland", enable_wayland);
    options.addOption(bool, "system_integration", system_integration);
    module.addOptions("build_options", options);

    if (enable_framebuffer) module.addCMacro("WIO_FRAMEBUFFER", "");
    if (enable_opengl) module.addCMacro("WIO_OPENGL", "");
    if (enable_vulkan) module.addCMacro("WIO_VULKAN", "");
    if (enable_joystick) module.addCMacro("WIO_JOYSTICK", "");
    if (enable_audio) module.addCMacro("WIO_AUDIO", "");

    if (b.option(bool, "win32_manifest", "Embed application manifest (default: true)") orelse true) {
        module.addWin32ResourceFile(.{ .file = b.path("src/win32.rc") });
    }

    switch (target.result.os.tag) {
        .windows => {
            if (b.lazyDependency("win32", .{ .target = target, .optimize = optimize })) |win32| {
                module.addImport("win32", win32.module("win32"));
            }

            module.linkSystemLibrary("user32", .{});
            module.linkSystemLibrary("ole32", .{});
            module.linkSystemLibrary("shell32", .{});
            if (enable_framebuffer or enable_opengl) {
                module.linkSystemLibrary("gdi32", .{});
            }
            if (enable_opengl) {
                module.linkSystemLibrary("opengl32", .{});
            }
            if (enable_joystick) {
                module.linkSystemLibrary("hid", .{});
                module.linkSystemLibrary(if (target.result.cpu.arch.isX86()) "xinput9_1_0" else "xinput1_4", .{});
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
            if (enable_vulkan) {
                module.linkFramework("QuartzCore", .{});
            }
            if (enable_joystick) {
                module.linkFramework("IOKit", .{});
            }
            if (enable_audio) {
                module.linkFramework("CoreAudio", .{});
                module.linkFramework("AudioUnit", .{});
                module.linkFramework("AudioToolbox", .{});
            }
        },
        .linux, .openbsd, .netbsd, .freebsd, .dragonfly, .illumos => |tag| {
            if (target.result.abi.isAndroid()) {
                if (b.lazyDependency("android", .{})) |android| {
                    module.addImport("android", android.module("android"));
                }

                module.linkSystemLibrary("android", .{});
                if (enable_opengl) {
                    module.linkSystemLibrary("EGL", .{});
                }
                if (enable_vulkan) {
                    module.linkSystemLibrary("vulkan", .{});
                }
            } else {
                var cimport: std.ArrayList(u8) = .empty;
                if (enable_x11) {
                    try cimport.appendSlice(b.allocator,
                        \\#include <X11/Xlib.h>
                        \\#include <X11/Xatom.h>
                        \\#include <X11/XKBlib.h>
                        \\#include <X11/Xcursor/Xcursor.h>
                        \\#include <GL/glx.h>
                        \\
                    );
                }
                if (enable_wayland) {
                    if (!system_integration) {
                        try cimport.appendSlice(b.allocator,
                            \\#include <wio-wayland.h>
                            \\#include <wayland-protocol.c>
                            \\
                        );
                    }
                    try cimport.appendSlice(b.allocator,
                        \\#include <viewporter-protocol.c>
                        \\#include <fractional-scale-v1-protocol.c>
                        \\#include <text-input-v3-protocol.c>
                        \\#include <tablet-v2-protocol.c>
                        \\#include <cursor-shape-v1-protocol.c>
                        \\#include <pointer-constraints-v1-protocol.c>
                        \\#include <relative-pointer-v1-protocol.c>
                        \\#include <xdg-activation-v1-protocol.c>
                        \\#include <wayland-client-protocol.h>
                        \\#include <viewporter-client-protocol.h>
                        \\#include <fractional-scale-v1-client-protocol.h>
                        \\#include <text-input-v3-client-protocol.h>
                        \\#include <cursor-shape-v1-client-protocol.h>
                        \\#include <pointer-constraints-v1-client-protocol.h>
                        \\#include <relative-pointer-v1-client-protocol.h>
                        \\#include <xdg-activation-v1-client-protocol.h>
                        \\#include <xkbcommon/xkbcommon.h>
                        \\#include <xkbcommon/xkbcommon-compose.h>
                        \\#include <libdecor.h>
                        \\#include <wayland-egl.h>
                        \\#include <EGL/egl.h>
                        \\
                    );
                }
                switch (tag) {
                    .linux => {
                        if (enable_joystick) {
                            try cimport.appendSlice(b.allocator,
                                \\#include <linux/input.h>
                                \\#include <libudev.h>
                                \\
                            );
                        }
                        if (enable_audio) {
                            try cimport.appendSlice(b.allocator, "#include <pulse/pulseaudio.h>\n");
                        }
                    },
                    .openbsd => {
                        if (enable_audio) {
                            try cimport.appendSlice(b.allocator, "#include <sndio.h>\n");
                        }
                    },
                    else => {},
                }

                const translate_c = b.addTranslateC(.{
                    .root_source_file = b.addWriteFiles().add("cimport.c", cimport.items),
                    .target = target,
                    .optimize = optimize,
                });
                if (b.lazyDependency("wio_unix_headers", .{})) |unix_headers| {
                    translate_c.addIncludePath(unix_headers.path("."));
                }
                module.addImport("c", translate_c.createModule());

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
                    switch (tag) {
                        .linux => {
                            if (enable_joystick) {
                                module.linkSystemLibrary("libudev", .{});
                            }
                            if (enable_audio) {
                                module.linkSystemLibrary("libpulse", .{});
                            }
                        },
                        .openbsd => {
                            if (enable_audio) {
                                module.linkSystemLibrary("sndio", .{});
                            }
                        },
                        else => {},
                    }
                }
            }
        },
        .haiku => {
            module.linkSystemLibrary("be", .{});
            if (enable_opengl) module.linkSystemLibrary("GL", .{});
            if (enable_joystick) module.linkSystemLibrary("device", .{});
            if (enable_audio) module.linkSystemLibrary("media", .{});

            const gcc = b.addSystemCommand(&.{
                "g++",
                "-Wall",
                switch (optimize) {
                    .Debug => "-O0",
                    .ReleaseFast, .ReleaseSafe => "-O3",
                    .ReleaseSmall => "-Os",
                },
                "-g",
                "-c",
                "-o",
            });
            const output = gcc.addOutputFileArg("haiku.o");
            gcc.addFileArg(b.path("src/haiku.cpp"));
            gcc.addArgs(module.c_macros.items);
            module.addObjectFile(output);
        },
        else => {
            if (target.result.cpu.arch.isWasm()) {
                var exports: std.ArrayList([]const u8) = .empty;
                try exports.append(b.allocator, "wioLoop");
                if (enable_joystick) {
                    try exports.append(b.allocator, "wioJoystick");
                }
                module.export_symbol_names = exports.items;
            }
        },
    }
}

pub fn setupApk(wio: *std.Build.Dependency, apk: anytype) void {
    const b = wio.builder;
    apk.addJavaSourceFiles(.{
        .root = b.path("src/android"),
        .files = &.{
            "WioActivity.java",
            "WioSurfaceView.java",
            "WioInputConnection.java",
        },
    });
}

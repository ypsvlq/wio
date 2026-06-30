const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unix_backends = b.option([]const u8, "unix_backends", "List of enabled wio backends");
    const android_all_targets = b.option(bool, "android", "Build APK supporting all Android targets") orelse false;

    if (android_all_targets or target.result.abi.isAndroid()) {
        if (b.lazyImport(@This(), "android")) |android| {
            const sdk = android.Sdk.create(b, .{});

            const apk = sdk.createApk(.{
                .name = "vulkan",
                .build_tools_version = b.option([]const u8, "android_build_tools_version", "Android build tools version (e.g. 35.0.0)") orelse "37.0.0",
                .ndk_version = b.option([]const u8, "android_ndk_version", "Android NDK version (e.g. 27.0.12077973)") orelse "29.0.14206865",
                .api_level = @enumFromInt(b.option(u32, "android_api_level", "Android API level (e.g. 35)") orelse 35),
            });
            apk.setKeyStore(sdk.createKeyStore(.example));
            apk.setAndroidManifest(b.path("src/android/AndroidManifest.xml"));
            apk.addResourceDirectory(b.path("src/android/res"));
            @import("wio").setupApk(b.dependency("wio", .{}), apk);

            for (android.resolveTargets(b, .{ .default_target = target, .all_targets = android_all_targets })) |android_target| {
                apk.addArtifact(b.addLibrary(.{
                    .linkage = .dynamic,
                    .name = "main",
                    .root_module = createModule(b, android_target, optimize, unix_backends),
                }));
            }

            const install_apk = apk.addInstallApk();
            b.getInstallStep().dependOn(&install_apk.step);

            const adb_install = sdk.addAdbInstall(install_apk.source);
            const adb_start = sdk.addAdbStart("net.tiredsleepy.wio.vulkan/net.tiredsleepy.wio.WioActivity");
            adb_start.step.dependOn(&adb_install.step);

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&adb_start.step);
        }
    } else {
        const exe = b.addExecutable(.{
            .name = "vulkan",
            .root_module = createModule(b, target, optimize, unix_backends),
        });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}

fn createModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, unix_backends: ?[]const u8) *std.Build.Module {
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
        .unix_backends = unix_backends,
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{});

    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    });

    const module = b.createModule(.{
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

    return module;
}

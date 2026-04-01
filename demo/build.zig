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

    if (target.result.abi.isAndroid()) {
        if (b.lazyImport(@This(), "android")) |android| {
            const sdk = android.Sdk.create(b, .{});
            const apk = sdk.createApk(.{
                .build_tools_version = b.option([]const u8, "android_build_tools_version", "Android build tools version (e.g. 35.0.0)") orelse "37.0.0",
                .ndk_version = b.option([]const u8, "android_ndk_version", "Android NDK version (e.g. 27.0.12077973)") orelse "29.0.14206865",
                .api_level = b.option(android.ApiLevel, "android_api_level", "Android API level (e.g. android15)") orelse .android15,
            });
            apk.setKeyStore(sdk.createKeyStore(.example));
            apk.setAndroidManifest(b.path("src/android/AndroidManifest.xml"));
            apk.addResourceDirectory(b.path("src/android/res"));
            apk.addArtifact(b.addLibrary(.{
                .name = "demo",
                .root_module = exe_mod,
                .linkage = .dynamic,
            }));
            @import("wio").setupApk(wio.module("wio"), apk);
            apk.installApk();
        }
    } else {
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
}

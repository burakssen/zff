// ponytail: build setup generating c.h internally via translateC into @import("raylib") module
const std = @import("std");
const raylib = @import("raylib");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Generate c.h internally and translate it to "raylib" module
    const write_files = b.addWriteFiles();
    const c_h = write_files.add("c.h",
        \\#include <raylib.h>
        \\#include <rlgl.h>
        \\#include <raymath.h>
        \\#if defined(__EMSCRIPTEN__)
        \\#include <GLES2/gl2.h>
        \\#elif defined(__APPLE__)
        \\#define GL_SILENCE_DEPRECATION
        \\#include <OpenGL/gl.h>
        \\#else
        \\#include <GL/gl.h>
        \\#endif
        \\#ifndef GL_LINES
        \\#define GL_LINES 0x0001
        \\#endif
        \\
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = c_h,
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(raylib_dep.path("src"));

    if (target.result.os.tag == .emscripten) {
        const emsdk_dep = b.dependency("emsdk", .{});
        const sysroot_include = emsdk_dep.path("upstream/emscripten/cache/sysroot/include");
        translate_c.addIncludePath(sysroot_include);
    } else if (target.result.os.tag == .macos) {
        translate_c.defineCMacro("GL_SILENCE_DEPRECATION", "");
    }

    const raylib_mod = translate_c.createModule();

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "raylib", .module = raylib_mod },
        },
        .link_libc = true,
    });
    exe_mod.linkLibrary(raylib_artifact);
    exe_mod.addIncludePath(raylib_dep.path("src"));

    // --- Emscripten Build (WASM) ---
    if (target.result.os.tag == .emscripten) {
        const emsdk_dep = b.dependency("emsdk", .{});
        const sysroot_include = emsdk_dep.path("upstream/emscripten/cache/sysroot/include");
        exe_mod.addIncludePath(sysroot_include);

        const wasm = b.addLibrary(.{
            .name = "flip",
            .root_module = exe_mod,
        });
        wasm.root_module.linkLibrary(raylib_artifact);
        wasm.root_module.addIncludePath(raylib_dep.path("src"));

        var emcc_flags = raylib.emsdk.emccDefaultFlags(b.allocator, .{
            .optimize = optimize,
            .asyncify = true,
        });
        try emcc_flags.put("-msimd128", {});

        var emcc_settings = raylib.emsdk.emccDefaultSettings(b.allocator, .{
            .optimize = optimize,
        });
        try emcc_settings.put("INITIAL_MEMORY", "134217728");
        try emcc_settings.put("USE_GLFW", "3");
        try emcc_settings.put("EXPORTED_FUNCTIONS", "[_main]");

        const emcc_step = raylib.emsdk.emccStep(b, raylib_artifact, wasm, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .shell_file_path = b.path("index.html"),
            .install_dir = .{ .custom = "web" },
            .preload_paths = &.{},
        });

        b.getInstallStep().dependOn(emcc_step);
        return;
    }

    const exe = b.addExecutable(.{
        .name = "flip",
        .root_module = exe_mod,
    });
    exe.root_module.linkLibrary(raylib_artifact);

    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("OpenGL", .{});
    } else if (target.result.os.tag == .linux or target.result.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("GL", .{});
    }

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the flip executable");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
}

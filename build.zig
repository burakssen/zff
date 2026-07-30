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

    // Create modules
    const graphics_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/graphics/graphics.zig"),
        .link_libc = true,
    });
    // Graphics module needs C headers for @cImport
    graphics_mod.linkLibrary(raylib_artifact);
    graphics_mod.addIncludePath(raylib_dep.path("src"));

    const core_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core/core.zig"),
        .imports = &.{
            .{ .name = "graphics", .module = graphics_mod },
        },
        .link_libc = true,
    });
    // Core module also uses @cImport
    core_mod.linkLibrary(raylib_artifact);
    core_mod.addIncludePath(raylib_dep.path("src"));

    const fluid_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/fluid/fluid.zig"),
        .imports = &.{},
    });

    graphics_mod.addImport("fluid", fluid_mod);
    core_mod.addImport("fluid", fluid_mod);

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });
    exe_mod.linkLibrary(raylib_artifact);
    exe_mod.addIncludePath(raylib_dep.path("src"));

    // --- Emscripten Build (WASM) ---
    if (target.result.os.tag == .emscripten) {
        const emsdk_dep = b.dependency("emsdk", .{});
        const sysroot_include = emsdk_dep.path("upstream/emscripten/cache/sysroot/include");
        graphics_mod.addIncludePath(sysroot_include);
        core_mod.addIncludePath(sysroot_include);
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

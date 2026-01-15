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

    // Create graphics module
    const graphics_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/graphics/graphics.zig"),
    });

    graphics_mod.linkLibrary(raylib_artifact);
    graphics_mod.addIncludePath(raylib_dep.path("src"));

    // Create core module with graphics dependency
    const core_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core/core.zig"),
        .imports = &.{
            .{ .name = "graphics", .module = graphics_mod },
        },
    });

    // Create fluid module with core dependency
    const fluid_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/fluid/fluid.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // Add fluid dependency to graphics and core modules
    graphics_mod.addImport("fluid", fluid_mod);
    core_mod.addImport("fluid", fluid_mod);

    // Create executable module
    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // --- Emscripten Build (WASM) ---
    if (target.result.os.tag == .emscripten) {
        const wasm = b.addLibrary(.{
            .name = "flip",
            .root_module = exe_mod,
        });

        // 1. Create Emscripten Flags
        // Corresponds to CMake: target_compile_options(flip PRIVATE -O3 -msimd128)
        // and LINK_FLAGS: -s USE_GLFW=3 -s ASYNCIFY=1 ...
        var emcc_flags = raylib.emsdk.emccDefaultFlags(b.allocator, .{
            .optimize = optimize,
            .asyncify = true, // Matches -s ASYNCIFY=1
        });

        try emcc_flags.put("-msimd128", {});

        // 2. Create Emscripten Settings
        var emcc_settings = raylib.emsdk.emccDefaultSettings(b.allocator, .{
            .optimize = optimize,
        });

        // Matches CMake: -s INITIAL_MEMORY=134217728
        try emcc_settings.put("INITIAL_MEMORY", "134217728"); // 128MB
        try emcc_settings.put("USE_GLFW", "3");
        try emcc_settings.put("EXPORTED_FUNCTIONS", "[_main]"); // Minimal export

        // 3. Compile to HTML
        const emcc_step = raylib.emsdk.emccStep(b, raylib_artifact, wasm, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .shell_file_path = b.path("index.html"), // Ensure this file exists
            .install_dir = .{ .custom = "web" },
            // Matches CMake: --preload-file shaders@shaders
            .preload_paths = &.{},
        });

        b.getInstallStep().dependOn(emcc_step);
        return;
    }

    // --- Native Build (Desktop) ---

    // Note on Optimizations:
    // CMake: /O2 (MSVC) or -O3 (Linux/Mac) -> Handled by passing '-Doptimize=ReleaseFast' to `zig build`
    // CMake: -march=native -> Zig defaults to native cpu model when building locally.

    const exe = b.addExecutable(.{
        .name = "flip",
        .root_module = exe_mod,
    });

    // macOS specific linking
    if (target.result.os.tag == .macos) {
        exe.linkFramework("OpenGL");
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

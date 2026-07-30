// ponytail: main entry point supporting both WASM and native targets
const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const AppState = @import("core/app_state.zig");

pub const main = if (builtin.os.tag == .emscripten) emscriptenMain else nativeMain;

fn emscriptenMain() !void {
    var app = try AppState.init(std.heap.c_allocator);
    defer app.deinit();
    try app.run();
}

fn nativeMain(init: std.process.Init) !void {
    const allocator = init.gpa;

    var app = try AppState.init(allocator);
    defer app.deinit();

    var it = std.process.Args.Iterator.init(init.minimal.args);
    _ = it.skip();

    if (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--benchmark")) {
            app.paused = false;
            const parsed_frames: usize = if (it.next()) |f_arg| std.fmt.parseInt(usize, f_arg, 10) catch 500 else 500;
            const frames = @max(1, parsed_frames);
            std.debug.print("Running benchmark for {d} frames...\n", .{frames});

            const start = rl.GetTime();

            for (0..frames) |_| {
                app.simulateStep();
            }

            const end = rl.GetTime();
            const elapsed_ms = (end - start) * 1000.0;

            const ms_per_frame = elapsed_ms / @as(f64, @floatFromInt(frames));
            const fps = if (ms_per_frame > 0.0) 1000.0 / ms_per_frame else 0.0;
            std.debug.print("Benchmark completed: {d} frames in {d:.2} ms ({d:.2} ms/frame, {d:.1} FPS)\n", .{ frames, elapsed_ms, ms_per_frame, fps });
            return;
        }
    }

    try app.run();
}

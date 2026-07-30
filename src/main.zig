// ponytail: main entry point with benchmark mode
const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const AppState = @import("core/app_state.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = switch (builtin.os.tag) {
        .emscripten => std.heap.c_allocator,
        else => init.gpa,
    };

    var app = try AppState.init(allocator);
    defer app.deinit();

    var it = std.process.Args.Iterator.init(init.minimal.args);
    _ = it.skip();

    if (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--benchmark")) {
            app.paused = false;
            const frames: usize = if (it.next()) |f_arg| std.fmt.parseInt(usize, f_arg, 10) catch 500 else 500;
            std.debug.print("Running benchmark for {d} frames...\n", .{frames});

            const start = rl.GetTime();

            for (0..frames) |_| {
                try app.simulateStep();
            }

            const end = rl.GetTime();
            const elapsed_ms = (end - start) * 1000.0;

            const ms_per_frame = elapsed_ms / @as(f64, @floatFromInt(frames));
            const fps = 1000.0 / ms_per_frame;
            std.debug.print("Benchmark completed: {d} frames in {d:.2} ms ({d:.2} ms/frame, {d:.1} FPS)\n", .{ frames, elapsed_ms, ms_per_frame, fps });
            return;
        }
    }

    try app.run();
}

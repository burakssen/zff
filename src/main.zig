const std = @import("std");
const builtin = @import("builtin");

const core = @import("core");
const AppState = core.AppState;
pub fn main() !void {
    // ponytail: use DebugAllocator for leak detection on native, c_allocator on emscripten
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = if (builtin.os.tag != .emscripten) gpa.deinit();

    const allocator = switch (builtin.os.tag) {
        .emscripten => std.heap.c_allocator,
        else => gpa.allocator(),
    };

    var app = try AppState.init(allocator);
    defer app.deinit();

    try app.run();
}

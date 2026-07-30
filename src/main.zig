// ponytail: main entry point
const std = @import("std");
const builtin = @import("builtin");

const AppState = @import("core/app_state.zig");

pub fn main() !void {
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

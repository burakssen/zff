const std = @import("std");
const builtin = @import("builtin");

const core = @import("core");
const AppState = core.AppState;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const allocator = switch (builtin.os.tag) {
        .emscripten => std.heap.c_allocator,
        else => gpa.allocator(),
    };

    defer _ = if (builtin.os.tag != .emscripten) gpa.deinit();

    var app = try AppState.init(allocator);
    defer app.deinit();

    try app.run();
}

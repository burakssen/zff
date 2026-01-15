const std = @import("std");

pub inline fn clampPosition(x: *f32, y: *f32, minX: f32, maxX: f32, minY: f32, maxY: f32) void {
    x.* = @max(minX, @min(x.*, maxX));
    y.* = @max(minY, @min(y.*, maxY));
}

pub inline fn bilinearWeights(fx: f32, fy: f32, w00: *f32, w10: *f32, w11: *f32, w01: *f32) void {
    const tx = fx - std.math.floor(fx);
    const ty = fy - std.math.floor(fy);
    const sx = 1.0 - tx;
    const sy = 1.0 - ty;

    w00.* = sx * sy;
    w10.* = tx * sy;
    w11.* = tx * ty;
    w01.* = sx * ty;
}

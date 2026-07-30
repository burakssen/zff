// ponytail: unit test suite for zff correctness and numerical stability
const std = @import("std");
const testing = std.testing;

const ParticleData = @import("fluid/particle_data.zig");
const FlipFluid = @import("fluid/flip_fluid.zig");

test "ParticleData initializes memory to zero" {
    const allocator = testing.allocator;
    var particles = try ParticleData.init(allocator, 100);
    defer particles.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), particles.count);
    try testing.expectEqual(@as(usize, 100), particles.capacity);

    for (particles.vel_x) |vx| {
        try testing.expectEqual(@as(f32, 0.0), vx);
    }
    for (particles.vel_y) |vy| {
        try testing.expectEqual(@as(f32, 0.0), vy);
    }
    for (particles.pos_x) |px| {
        try testing.expectEqual(@as(f32, 0.0), px);
    }
    for (particles.pos_y) |py| {
        try testing.expectEqual(@as(f32, 0.0), py);
    }
}

test "ParticleData view returns correct slice lengths" {
    const allocator = testing.allocator;
    var particles = try ParticleData.init(allocator, 50);
    defer particles.deinit(allocator);

    particles.count = 10;
    const view = particles.view();
    try testing.expectEqual(@as(usize, 10), view.count);
    try testing.expectEqual(@as(usize, 10), view.pos_x.len);
    try testing.expectEqual(@as(usize, 10), view.vel_y.len);
}

test "FlipFluid parameter validation" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidParameter, FlipFluid.init(allocator, 1000.0, -1.0, 2.0, 0.03, 0.01, 100));
    try testing.expectError(error.InvalidParameter, FlipFluid.init(allocator, 1000.0, 4.0, 2.0, 0.0, 0.01, 100));
}

test "FlipFluid rectangular domain stability & finite values" {
    const allocator = testing.allocator;
    const width: f32 = 4.0;
    const height: f32 = 2.0;
    const spacing: f32 = 0.1;
    const particle_radius: f32 = 0.03;
    const max_particles: usize = 200;

    var fluid = try FlipFluid.init(allocator, 1000.0, width, height, spacing, particle_radius, max_particles);
    defer fluid.deinit();

    try testing.expect(fluid.grid_size_x != fluid.grid_size_y);

    fluid.particles.count = 50;
    for (0..50) |i| {
        const fi = @as(f32, @floatFromInt(i));
        fluid.particles.pos_x[i] = 0.2 + @mod(fi * 0.05, 3.0);
        fluid.particles.pos_y[i] = 0.2 + @mod(fi * 0.03, 1.5);
    }

    const params: FlipFluid.SimParams = .{};
    const obstacle: FlipFluid.Obstacle = .{};

    for (0..100) |_| {
        fluid.simulate(params, obstacle);
    }

    const view = fluid.particles.view();
    for (0..view.count) |i| {
        try testing.expect(std.math.isFinite(view.pos_x[i]));
        try testing.expect(std.math.isFinite(view.pos_y[i]));
        try testing.expect(std.math.isFinite(view.vel_x[i]));
        try testing.expect(std.math.isFinite(view.vel_y[i]));
    }
}

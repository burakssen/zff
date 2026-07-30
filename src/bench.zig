// ponytail: headless CPU simulation benchmark without window or GPU context overhead
const std = @import("std");
const FlipFluid = @import("fluid/flip_fluid.zig");
const SceneFactory = @import("fluid/scene_factory.zig");

fn getNanoTimestamp() i128 {
    var ts: std.posix.timespec = undefined;
    std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts) catch return 0;
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip(); // skip executable name

    var steps: usize = 200;
    var target_particles: usize = 10000;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--steps")) {
            if (args.next()) |val| steps = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, arg, "--particles")) {
            if (args.next()) |val| target_particles = try std.fmt.parseInt(usize, val, 10);
        }
    }

    steps = @max(1, steps);
    target_particles = @max(100, target_particles);

    const tank_width: f32 = 4.0;
    const tank_height: f32 = 3.0;
    const cell_size: f32 = tank_height / 100.0;
    const particle_radius: f32 = 0.3 * cell_size;
    const density: f32 = 1000.0;

    var fluid = try FlipFluid.init(allocator, density, tank_width, tank_height, cell_size, particle_radius, target_particles);
    defer fluid.deinit();

    SceneFactory.setupDamBreak(&fluid, .{});

    const active_particles = fluid.particles.count;
    std.debug.print("====================================================\n", .{});
    std.debug.print(" ZFF Headless Physics Benchmark\n", .{});
    std.debug.print("====================================================\n", .{});
    std.debug.print(" Active Particles:   {d}\n", .{active_particles});
    std.debug.print(" Grid Dimensions:    {d} x {d} ({d} cells)\n", .{ fluid.grid_size_x, fluid.grid_size_y, fluid.num_cells });
    std.debug.print(" Active Fluid Cells: {d} / {d}\n", .{ fluid.pressure.active_cell_count, fluid.num_cells });
    std.debug.print(" Total Substeps:     {d}\n", .{steps});
    std.debug.print("----------------------------------------------------\n", .{});

    const sim_params: FlipFluid.SimParams = .{};
    const obstacle: FlipFluid.Obstacle = .{};

    // Warm-up iteration
    fluid.simulate(sim_params, obstacle);

    const start_ns = getNanoTimestamp();

    for (0..steps) |_| {
        fluid.simulate(sim_params, obstacle);
    }

    const end_ns = getNanoTimestamp();
    const elapsed_ns = end_ns - start_ns;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const ms_per_step = elapsed_ms / @as(f64, @floatFromInt(steps));
    const simulated_fps = 1000.0 / ms_per_step;
    const particles_per_sec = (@as(f64, @floatFromInt(active_particles * steps)) / elapsed_ms) * 1000.0;

    std.debug.print(" Total Time:       {d:.2} ms\n", .{elapsed_ms});
    std.debug.print(" Step Time:        {d:.3} ms/step\n", .{ms_per_step});
    std.debug.print(" Effective FPS:    {d:.1} FPS\n", .{simulated_fps});
    std.debug.print(" Particle Rate:    {d:.0} particles/sec\n", .{particles_per_sec});
    std.debug.print("====================================================\n", .{});
}

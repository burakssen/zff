// ponytail: scene factory for particle block and boundary initialization
const std = @import("std");
const FlipFluid = @import("flip_fluid.zig");

const SceneFactory = @This();

pub const SceneConfig = struct {
    relative_width: f32 = 0.8,
    relative_height: f32 = 0.8,
    density: f32 = 1000.0,
};

pub fn setupDamBreak(fluid: *FlipFluid, config: SceneConfig) void {
    const tank_width = @as(f32, @floatFromInt(fluid.grid_size_x - 1)) * fluid.cell_size;
    const tank_height = @as(f32, @floatFromInt(fluid.grid_size_y - 1)) * fluid.cell_size;

    const delta_x = 2.0 * fluid.particle_radius;
    const delta_y = (std.math.sqrt(3.0) / 2.0) * delta_x;

    const num_particles_x: usize = @intFromFloat(std.math.floor((config.relative_width * tank_width - 2.0 * fluid.cell_size - 2.0 * fluid.particle_radius) / delta_x));
    const num_particles_y: usize = @intFromFloat(std.math.floor((config.relative_height * tank_height - 2.0 * fluid.cell_size - 2.0 * fluid.particle_radius) / delta_y));

    const particle_count = num_particles_x * num_particles_y;
    fluid.particles.count = @min(particle_count, fluid.particles.capacity);

    var idx: usize = 0;
    for (0..num_particles_x) |i| {
        for (0..num_particles_y) |j| {
            if (idx >= fluid.particles.count) break;
            const x_offset = if (j % 2 == 0) 0.0 else fluid.particle_radius;
            const float_x = @as(f32, @floatFromInt(i));
            const float_y = @as(f32, @floatFromInt(j));

            fluid.particles.pos_x[idx] = fluid.cell_size + fluid.particle_radius + delta_x * float_x + x_offset;
            fluid.particles.pos_y[idx] = fluid.cell_size + fluid.particle_radius + delta_y * float_y;
            fluid.particles.vel_x[idx] = 0.0;
            fluid.particles.vel_y[idx] = 0.0;

            idx += 1;
        }
    }

    const grid_height: usize = @intCast(fluid.grid_size_y);
    const grid_width: usize = @intCast(fluid.grid_size_x);

    for (0..grid_width) |i| {
        for (0..grid_height) |j| {
            const solid_value: f32 = if (i == 0 or i == grid_width - 1 or j == 0) 0.0 else 1.0;
            fluid.pressure.s[i * grid_height + j] = solid_value;
        }
    }
}

const std = @import("std");

const SimulationConfig = @This();

// Grid parameters
grid_size_x: i32,
grid_size_y: i32,
num_cells: usize,
cell_size: f32,
inv_cell_size: f32,
// Particle parameters
particle_radius: f32,
density: f32,
rest_density: f32,

pub fn init(width: f32, height: f32, spacing: f32, particle_radius: f32, density: f32) SimulationConfig {
    const grid_size_x: i32 = @intFromFloat(std.math.floor(width / spacing));
    const grid_size_y: i32 = @intFromFloat(std.math.floor(height / spacing));
    const grid_size_x_inc = grid_size_x + 1;
    const grid_size_y_inc = grid_size_y + 1;

    const cell_size = @max(width / @as(f32, @floatFromInt(grid_size_x_inc)), height / @as(f32, @floatFromInt(grid_size_y_inc)));

    return SimulationConfig{
        .grid_size_x = grid_size_x_inc,
        .grid_size_y = grid_size_y_inc,
        .num_cells = @intCast(grid_size_x_inc * grid_size_y_inc),
        .cell_size = cell_size,
        .inv_cell_size = 1.0 / cell_size,
        .particle_radius = particle_radius,
        .density = density,
        .rest_density = 0.0,
    };
}

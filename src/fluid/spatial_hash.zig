// ponytail: spatial hash grid using flat slices
const std = @import("std");

const SpatialHash = @This();

num_cell_particles: []i32,
first_cell_particle: []i32,
particle_ids: []i32,

grid_size_x: i32,
grid_size_y: i32,
num_cells: usize,
inv_spacing: f32,

pub fn init(allocator: std.mem.Allocator, sizeX: i32, sizeY: i32, maxParticles: usize, inv_spacing: f32) !SpatialHash {
    const num_cells: usize = @intCast(sizeX * sizeY);
    const num_cell_particles = try allocator.alloc(i32, num_cells);
    const first_cell_particle = try allocator.alloc(i32, num_cells + 1);
    const particle_ids = try allocator.alloc(i32, maxParticles);
    @memset(num_cell_particles, 0);
    @memset(first_cell_particle, 0);
    @memset(particle_ids, 0);

    return SpatialHash{
        .num_cell_particles = num_cell_particles,
        .first_cell_particle = first_cell_particle,
        .particle_ids = particle_ids,
        .grid_size_x = sizeX,
        .grid_size_y = sizeY,
        .num_cells = num_cells,
        .inv_spacing = inv_spacing,
    };
}

pub fn deinit(self: *SpatialHash, allocator: std.mem.Allocator) void {
    allocator.free(self.num_cell_particles);
    allocator.free(self.first_cell_particle);
    allocator.free(self.particle_ids);
}

pub fn clear(self: *SpatialHash) void {
    @memset(self.num_cell_particles, 0);
}

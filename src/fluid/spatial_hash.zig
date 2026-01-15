const std = @import("std");

const SpatialHash = @This();

allocator: std.mem.Allocator,
num_cell_particles: std.ArrayList(i32),
first_cell_particle: std.ArrayList(i32),
particle_ids: std.ArrayList(i32),

grid_size_x: i32,
grid_size_y: i32,
num_cells: usize,
inv_spacing: f32,

pub fn init(allocator: std.mem.Allocator) SpatialHash {
    return SpatialHash{
        .allocator = allocator,
        .num_cell_particles = .empty,
        .first_cell_particle = .empty,
        .particle_ids = .empty,
        .grid_size_x = 0,
        .grid_size_y = 0,
        .num_cells = 0,
        .inv_spacing = 0,
    };
}

pub fn deinit(self: *SpatialHash) void {
    self.num_cell_particles.deinit(self.allocator);
    self.first_cell_particle.deinit(self.allocator);
    self.particle_ids.deinit(self.allocator);
}

pub fn resize(self: *SpatialHash, sizeX: i32, sizeY: i32, maxParticles: usize) !void {
    self.grid_size_x = sizeX;
    self.grid_size_y = sizeY;
    self.num_cells = @intCast(sizeX * sizeY);
    try self.num_cell_particles.resize(self.allocator, self.num_cells);
    try self.first_cell_particle.resize(self.allocator, self.num_cells + 1);
    try self.particle_ids.resize(self.allocator, maxParticles);
}

pub fn clear(self: *SpatialHash) void {
    @memset(self.num_cell_particles.items, 0);
}

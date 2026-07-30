// ponytail: particle data using SoA slices (pos_x, pos_y, vel_x, vel_y)
const std = @import("std");

const ParticleData = @This();

pub const fields = .{ "pos_x", "pos_y", "vel_x", "vel_y" };

pos_x: []f32,
pos_y: []f32,
vel_x: []f32,
vel_y: []f32,
count: usize,
capacity: usize,

pub fn init(allocator: std.mem.Allocator, max_particles: usize) !ParticleData {
    return ParticleData{
        .pos_x = try allocator.alloc(f32, max_particles),
        .pos_y = try allocator.alloc(f32, max_particles),
        .vel_x = try allocator.alloc(f32, max_particles),
        .vel_y = try allocator.alloc(f32, max_particles),
        .count = 0,
        .capacity = max_particles,
    };
}

pub fn deinit(self: *ParticleData, allocator: std.mem.Allocator) void {
    inline for (fields) |field_name| {
        allocator.free(@field(self, field_name));
    }
}

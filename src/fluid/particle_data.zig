// ponytail: particle data using SoA slices with failure-atomic init and explicit zeroing
const std = @import("std");

const ParticleData = @This();

pub const fields = .{ "pos_x", "pos_y", "vel_x", "vel_y" };

pub const ParticleView = struct {
    pos_x: []const f32,
    pos_y: []const f32,
    vel_x: []const f32,
    vel_y: []const f32,
    count: usize,
};

pos_x: []f32,
pos_y: []f32,
vel_x: []f32,
vel_y: []f32,
count: usize,
capacity: usize,

pub fn init(allocator: std.mem.Allocator, max_particles: usize) !ParticleData {
    const pos_x = try allocator.alloc(f32, max_particles);
    errdefer allocator.free(pos_x);

    const pos_y = try allocator.alloc(f32, max_particles);
    errdefer allocator.free(pos_y);

    const vel_x = try allocator.alloc(f32, max_particles);
    errdefer allocator.free(vel_x);

    const vel_y = try allocator.alloc(f32, max_particles);
    errdefer allocator.free(vel_y);

    @memset(pos_x, 0.0);
    @memset(pos_y, 0.0);
    @memset(vel_x, 0.0);
    @memset(vel_y, 0.0);

    return ParticleData{
        .pos_x = pos_x,
        .pos_y = pos_y,
        .vel_x = vel_x,
        .vel_y = vel_y,
        .count = 0,
        .capacity = max_particles,
    };
}

pub fn deinit(self: *ParticleData, allocator: std.mem.Allocator) void {
    inline for (fields) |field_name| {
        allocator.free(@field(self, field_name));
    }
}

pub fn view(self: *const ParticleData) ParticleView {
    return .{
        .pos_x = self.pos_x[0..self.count],
        .pos_y = self.pos_y[0..self.count],
        .vel_x = self.vel_x[0..self.count],
        .vel_y = self.vel_y[0..self.count],
        .count = self.count,
    };
}


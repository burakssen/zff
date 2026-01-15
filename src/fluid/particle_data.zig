const std = @import("std");

const ParticleData = @This();

allocator: std.mem.Allocator,
// Position data (accessed together during spatial queries)
pos_x: std.ArrayList(f32),
pos_y: std.ArrayList(f32),

// Velocity data (accessed together during integration)
vel_x: std.ArrayList(f32),
vel_y: std.ArrayList(f32),

// Color data (only accessed during rendering)
color_r: std.ArrayList(f32),
color_g: std.ArrayList(f32),
color_b: std.ArrayList(f32),

count: usize,
capacity: usize,

pub fn init(allocator: std.mem.Allocator) ParticleData {
    return ParticleData{
        .allocator = allocator,
        .pos_x = .empty,
        .pos_y = .empty,
        .vel_x = .empty,
        .vel_y = .empty,
        .color_r = .empty,
        .color_g = .empty,
        .color_b = .empty,
        .count = 0,
        .capacity = 0,
    };
}

pub fn deinit(self: *ParticleData) void {
    self.pos_x.deinit(self.allocator);
    self.pos_y.deinit(self.allocator);
    self.vel_x.deinit(self.allocator);
    self.vel_y.deinit(self.allocator);
    self.color_r.deinit(self.allocator);
    self.color_g.deinit(self.allocator);
    self.color_b.deinit(self.allocator);
}

pub fn resize(self: *ParticleData, n: usize) !void {
    self.capacity = n;
    try self.pos_x.resize(self.allocator, n);
    try self.pos_y.resize(self.allocator, n);
    try self.vel_x.resize(self.allocator, n);
    try self.vel_y.resize(self.allocator, n);
    try self.color_r.resize(self.allocator, n);
    try self.color_g.resize(self.allocator, n);
    try self.color_b.resize(self.allocator, n);
    self.count = 0;
}

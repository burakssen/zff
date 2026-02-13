const std = @import("std");

const ParticleData = @This();

pub const fields = .{ "pos_x", "pos_y", "vel_x", "vel_y", "color_r", "color_g", "color_b" };

allocator: std.mem.Allocator,

// Position data
pos_x: std.ArrayList(f32),
pos_y: std.ArrayList(f32),

// Velocity data
vel_x: std.ArrayList(f32),
vel_y: std.ArrayList(f32),

// Color data
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
    inline for (fields) |field_name| {
        @field(self, field_name).deinit(self.allocator);
    }
}

pub fn resize(self: *ParticleData, n: usize) !void {
    self.capacity = n;
    inline for (fields) |field_name| {
        try @field(self, field_name).resize(self.allocator, n);
    }
    self.count = 0;
}

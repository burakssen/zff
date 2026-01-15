const std = @import("std");

const VelocityGrid = @This();

allocator: std.mem.Allocator,
u: std.ArrayList(f32), // X-velocity
v: std.ArrayList(f32), // Y-velocity
prev_u: std.ArrayList(f32), // Previous X-velocity
prev_v: std.ArrayList(f32), // Previous Y-velocity

// Working buffers for scatter operations
du: std.ArrayList(f32), // Denominator for u
dv: std.ArrayList(f32), // Denominator for v

pub fn init(allocator: std.mem.Allocator) VelocityGrid {
    return VelocityGrid{
        .allocator = allocator,
        .u = .empty,
        .v = .empty,
        .prev_u = .empty,
        .prev_v = .empty,
        .du = .empty,
        .dv = .empty,
    };
}

pub fn deinit(self: *VelocityGrid) void {
    self.u.deinit(self.allocator);
    self.v.deinit(self.allocator);
    self.prev_u.deinit(self.allocator);
    self.prev_v.deinit(self.allocator);
    self.du.deinit(self.allocator);
    self.dv.deinit(self.allocator);
}

pub fn resize(self: *VelocityGrid, n: usize) !void {
    try self.u.resize(self.allocator, n);
    try self.v.resize(self.allocator, n);
    try self.prev_u.resize(self.allocator, n);
    try self.prev_v.resize(self.allocator, n);
    try self.du.resize(self.allocator, n);
    try self.dv.resize(self.allocator, n);
}

pub fn clear(self: *VelocityGrid) void {
    @memset(self.u.items, 0.0);
    @memset(self.v.items, 0.0);
    @memset(self.du.items, 0.0);
    @memset(self.dv.items, 0.0);
}

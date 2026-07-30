// ponytail: velocity grid using flat slices
const std = @import("std");

const VelocityGrid = @This();

u: []f32, // X-velocity
v: []f32, // Y-velocity
prev_u: []f32, // Previous X-velocity
prev_v: []f32, // Previous Y-velocity
du: []f32, // Denominator for u
dv: []f32, // Denominator for v

pub fn init(allocator: std.mem.Allocator, num_cells: usize) !VelocityGrid {
    const u = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(u);
    const v = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(v);
    const prev_u = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(prev_u);
    const prev_v = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(prev_v);
    const du = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(du);
    const dv = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(dv);

    var self = VelocityGrid{
        .u = u,
        .v = v,
        .prev_u = prev_u,
        .prev_v = prev_v,
        .du = du,
        .dv = dv,
    };
    self.clear();
    return self;
}

pub fn deinit(self: *VelocityGrid, allocator: std.mem.Allocator) void {
    allocator.free(self.u);
    allocator.free(self.v);
    allocator.free(self.prev_u);
    allocator.free(self.prev_v);
    allocator.free(self.du);
    allocator.free(self.dv);
}

pub fn clear(self: *VelocityGrid) void {
    @memset(self.u, 0.0);
    @memset(self.v, 0.0);
    @memset(self.du, 0.0);
    @memset(self.dv, 0.0);
}

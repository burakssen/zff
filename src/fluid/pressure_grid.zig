const std = @import("std");

pub const CellType = enum(u8) {
    fluid = 0,
    air = 1,
    solid = 2,
};

const PressureGrid = @This();

allocator: std.mem.Allocator,
p: std.ArrayList(f32), // Pressure
s: std.ArrayList(f32), // Solid boundary markers
density: std.ArrayList(f32), // Particle density per cell
cell_type: std.ArrayList(CellType), // Cell classification

pub fn init(allocator: std.mem.Allocator) PressureGrid {
    return PressureGrid{
        .allocator = allocator,
        .p = .empty,
        .s = .empty,
        .density = .empty,
        .cell_type = .empty,
    };
}

pub fn deinit(self: *PressureGrid) void {
    self.p.deinit(self.allocator);
    self.s.deinit(self.allocator);
    self.density.deinit(self.allocator);
    self.cell_type.deinit(self.allocator);
}

pub fn resize(self: *PressureGrid, n: usize) !void {
    try self.p.resize(self.allocator, n);
    try self.s.resize(self.allocator, n);
    try self.density.resize(self.allocator, n);
    try self.cell_type.resize(self.allocator, n);
}

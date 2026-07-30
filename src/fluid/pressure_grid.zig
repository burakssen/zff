// ponytail: pressure grid using flat slices
const std = @import("std");

pub const CellType = enum(u8) {
    fluid = 0,
    air = 1,
    solid = 2,
};

const PressureGrid = @This();

p: []f32, // Pressure
s: []f32, // Solid boundary markers
density: []f32, // Particle density per cell
cell_type: []CellType, // Cell classification
active_cells: []usize, // Active fluid cell indices for solver iteration
active_cell_count: usize = 0,

pub fn init(allocator: std.mem.Allocator, num_cells: usize) !PressureGrid {
    const p = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(p);
    const s = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(s);
    const density = try allocator.alloc(f32, num_cells);
    errdefer allocator.free(density);
    const cell_type = try allocator.alloc(CellType, num_cells);
    errdefer allocator.free(cell_type);
    const active_cells = try allocator.alloc(usize, num_cells);
    errdefer allocator.free(active_cells);

    @memset(p, 0);
    @memset(s, 0);
    @memset(density, 0);
    @memset(cell_type, .air);
    @memset(active_cells, 0);

    return PressureGrid{
        .p = p,
        .s = s,
        .density = density,
        .cell_type = cell_type,
        .active_cells = active_cells,
        .active_cell_count = 0,
    };
}

pub fn deinit(self: *PressureGrid, allocator: std.mem.Allocator) void {
    allocator.free(self.p);
    allocator.free(self.s);
    allocator.free(self.density);
    allocator.free(self.cell_type);
    allocator.free(self.active_cells);
}

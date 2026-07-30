const std = @import("std");

const utils = @import("utils.zig");

const ParticleData = @import("particle_data.zig");
const SimulationConfig = @import("simulation_config.zig");
const PressureGrid = @import("pressure_grid.zig");
const VelocityGrid = @import("velocity_grid.zig");
const SpatialHash = @import("spatial_hash.zig");

const FlipFluid = @This();

allocator: std.mem.Allocator,
particles: ParticleData,
scratch_particles: ParticleData,
config: SimulationConfig,
pressure: PressureGrid,
velocity: VelocityGrid,
spatial_hash: SpatialHash,
cell_color: std.ArrayList(f32), // Rendering data

pub fn init(allocator: std.mem.Allocator, density: f32, width: f32, height: f32, spacing: f32, particle_radius: f32, max_particles: usize) !FlipFluid {
    const config = SimulationConfig.init(width, height, spacing, particle_radius, density);
    var particles = ParticleData.init(allocator);
    try particles.resize(max_particles);

    var scratch_particles = ParticleData.init(allocator);
    try scratch_particles.resize(max_particles);

    var velocity = VelocityGrid.init(allocator);
    try velocity.resize(config.num_cells);

    var pressure = PressureGrid.init(allocator);
    try pressure.resize(config.num_cells);

    var cell_color: std.ArrayList(f32) = .empty;
    try cell_color.resize(allocator, 3 * config.num_cells);

    // Setup spatial hash grid
    const hash_spacing = 2.2 * particle_radius;
    const hash_size_x: i32 = @as(i32, @intFromFloat(std.math.floor(width / hash_spacing))) + 1;
    const hash_size_y: i32 = @as(i32, @intFromFloat(std.math.floor(height / hash_spacing))) + 1;

    var spatial_hash = SpatialHash.init(allocator);
    try spatial_hash.resize(hash_size_x, hash_size_y, max_particles);
    spatial_hash.inv_spacing = 1.0 / hash_spacing;

    // Initialize particle colors to blue
    @memset(particles.color_b.items, 1.0);

    return FlipFluid{
        .allocator = allocator,
        .particles = particles,
        .scratch_particles = scratch_particles,
        .config = config,
        .pressure = pressure,
        .velocity = velocity,
        .spatial_hash = spatial_hash,
        .cell_color = cell_color,
    };
}

pub fn deinit(self: *FlipFluid) void {
    self.particles.deinit();
    self.scratch_particles.deinit();
    self.pressure.deinit();
    self.velocity.deinit();
    self.spatial_hash.deinit();
    self.cell_color.deinit(self.allocator);
}

// Public data access
pub fn numParticles(self: *const FlipFluid) usize {
    return self.particles.count;
}
pub fn grid_size_x(self: *const FlipFluid) i32 {
    return self.config.grid_size_x;
}
pub fn grid_size_y(self: *const FlipFluid) i32 {
    return self.config.grid_size_y;
}
pub fn cell_size(self: *const FlipFluid) f32 {
    return self.config.cell_size;
}

// Utility methods
inline fn cellIndex(self: *const FlipFluid, x: i32, y: i32) usize {
    return @intCast(x * self.config.grid_size_y + y);
}
inline fn hashIndex(self: *const FlipFluid, x: i32, y: i32) usize {
    return @intCast(x * self.spatial_hash.grid_size_y + y);
}

pub fn simulate(self: *FlipFluid, dt: f32, gravity: f32, flipRatio: f32, numPressureIters: i32, numParticleIters: i32, overRelaxation: f32, obstacleX: f32, obstacleY: f32, obstacleRadius: f32, obstacleVelX: f32, obstacleVelY: f32) !void {
    self.integrateParticles(dt, gravity);
    try self.buildSpatialHash();
    self.resolveCollisions(numParticleIters);
    self.handleBoundaryCollisions(obstacleX, obstacleY, obstacleRadius, obstacleVelX, obstacleVelY);
    self.transferToGrid();
    self.computeDensity();
    self.solvePressure(numPressureIters, dt, overRelaxation);
    self.transferToParticles(flipRatio);
    self.updateVisuals();
}

fn integrateParticles(self: *FlipFluid, dt: f32, gravity: f32) void {
    const particle_count = self.particles.count;
    const velocity_y = self.particles.vel_y.items;
    const position_x = self.particles.pos_x.items;
    const position_y = self.particles.pos_y.items;
    const velocity_x = self.particles.vel_x.items;

    for (0..particle_count) |i| {
        velocity_y[i] += dt * gravity;
        position_x[i] += velocity_x[i] * dt;
        position_y[i] += velocity_y[i] * dt;
    }
}

fn buildSpatialHash(self: *FlipFluid) !void {
    self.spatial_hash.clear();

    const n = self.particles.count;
    const inv_spacing = self.spatial_hash.inv_spacing;
    const max_x = self.spatial_hash.grid_size_x - 1;
    const max_y = self.spatial_hash.grid_size_y - 1;

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const num_cell = self.spatial_hash.num_cell_particles.items;

    // Count particles per cell
    for (0..n) |i| {
        const xi = std.math.clamp(@as(i32, @intFromFloat(pos_x[i] * inv_spacing)), 0, max_x);
        const yi = std.math.clamp(@as(i32, @intFromFloat(pos_y[i] * inv_spacing)), 0, max_y);
        const idx = self.hashIndex(xi, yi);
        num_cell[idx] += 1;
    }

    // Compute prefix sum
    var sum: i32 = 0;
    const first = self.spatial_hash.first_cell_particle.items;
    for (0..self.spatial_hash.num_cells) |i| {
        first[i] = sum;
        sum += num_cell[i];
    }
    first[self.spatial_hash.num_cells] = sum;

    // ponytail: clone cursor slice directly via ArrayList(T).clone(allocator)
    var cell_cursor = try self.spatial_hash.first_cell_particle.clone(self.allocator);
    defer cell_cursor.deinit(self.allocator);
    const cursor_items = cell_cursor.items;

    // Sort particles into scratch_particles
    for (0..n) |i| {
        const x = pos_x[i];
        const y = pos_y[i];
        const xi = std.math.clamp(@as(i32, @intFromFloat(x * inv_spacing)), 0, max_x);
        const yi = std.math.clamp(@as(i32, @intFromFloat(y * inv_spacing)), 0, max_y);
        const idx = self.hashIndex(xi, yi);

        const dest: usize = @intCast(cursor_items[idx]);
        cursor_items[idx] += 1;

        inline for (ParticleData.fields) |field_name| {
            @field(self.scratch_particles, field_name).items[dest] = @field(self.particles, field_name).items[i];
        }
    }

    // ponytail: use stdlib @memcpy for fast unrolled array copy back
    inline for (ParticleData.fields) |field_name| {
        @memcpy(@field(self.particles, field_name).items[0..n], @field(self.scratch_particles, field_name).items[0..n]);
    }
}

fn resolveCollisions(self: *FlipFluid, numIters: i32) void {
    const min_dist = 2.0 * self.config.particle_radius;
    const min_dist_2 = min_dist * min_dist;

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const first = self.spatial_hash.first_cell_particle.items;

    var iter: i32 = 0;
    while (iter < numIters) : (iter += 1) {
        var color: i32 = 0;
        while (color < 9) : (color += 1) {
            const shiftX = @mod(color, 3);
            const shiftY = @divTrunc(color, 3);

            var xi = shiftX;
            while (xi < self.spatial_hash.grid_size_x) : (xi += 3) {
                var yi = shiftY;
                while (yi < self.spatial_hash.grid_size_y) : (yi += 3) {
                    const cell_idx = self.hashIndex(xi, yi);
                    const start: usize = @intCast(first[cell_idx]);
                    const end: usize = @intCast(first[cell_idx + 1]);

                    var i = start;
                    while (i < end) : (i += 1) {
                        const px = pos_x[i];
                        const py = pos_y[i];

                        const x0 = @max(xi - 1, 0);
                        const y0 = @max(yi - 1, 0);
                        const x1 = @min(xi + 1, self.spatial_hash.grid_size_x - 1);
                        const y1 = @min(yi + 1, self.spatial_hash.grid_size_y - 1);

                        var nxi = x0;
                        while (nxi <= x1) : (nxi += 1) {
                            var nyi = y0;
                            while (nyi <= y1) : (nyi += 1) {
                                const neighbor_cell_index = self.hashIndex(nxi, nyi);
                                const neighbor_start: usize = @intCast(first[neighbor_cell_index]);
                                const neighbor_end: usize = @intCast(first[neighbor_cell_index + 1]);

                                var j = neighbor_start;
                                while (j < neighbor_end) : (j += 1) {
                                    if (i == j) continue;

                                    const dx = pos_x[j] - px;
                                    const dy = pos_y[j] - py;
                                    const d2 = dx * dx + dy * dy;

                                    if (d2 > min_dist_2 or d2 == 0.0) continue;

                                    const d = std.math.sqrt(d2);
                                    const s = 0.5 * (min_dist - d) / d;

                                    pos_x[i] -= dx * s;
                                    pos_y[i] -= dy * s;
                                    pos_x[j] += dx * s;
                                    pos_y[j] += dy * s;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn handleBoundaryCollisions(self: *FlipFluid, obst_x: f32, obst_y: f32, obst_r: f32, obst_vel_x: f32, obst_vel_y: f32) void {
    const min_x = self.config.cell_size + self.config.particle_radius;
    const max_x = @as(f32, @floatFromInt(self.config.grid_size_x - 1)) * self.config.cell_size - self.config.particle_radius;
    const min_y = min_x;
    const max_y = max_x; // Assuming square bounds logic from C++ source
    const min_dist_2 = (obst_r + self.config.particle_radius) * (obst_r + self.config.particle_radius);

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const vel_x = self.particles.vel_x.items;
    const vel_y = self.particles.vel_y.items;

    for (0..self.particles.count) |i| {
        var x = pos_x[i];
        var y = pos_y[i];

        // Obstacle collision
        const dx = x - obst_x;
        const dy = y - obst_y;
        if (dx * dx + dy * dy < min_dist_2) {
            vel_x[i] = obst_vel_x;
            vel_y[i] = obst_vel_y;
        }

        // Boundary collisions
        if (x < min_x or x > max_x) {
            vel_x[i] = 0.0;
            x = std.math.clamp(x, min_x, max_x);
        }

        if (y < min_y or y > max_y) {
            vel_y[i] = 0.0;
            y = std.math.clamp(y, min_y, max_y);
        }

        pos_x[i] = x;
        pos_y[i] = y;
    }
}

fn transferToGrid(self: *FlipFluid) void {
    self.velocity.clear();

    // Reset cell types
    for (0..self.config.num_cells) |i| {
        self.pressure.cell_type.items[i] = if (self.pressure.s.items[i] == 0.0) .solid else .air;
    }

    // Mark fluid cells
    const inv_spacing = self.config.inv_cell_size;
    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;

    for (0..self.particles.count) |i| {
        const xi = std.math.clamp(@as(i32, @intFromFloat(pos_x[i] * inv_spacing)), 0, self.config.grid_size_x - 1);
        const yi = std.math.clamp(@as(i32, @intFromFloat(pos_y[i] * inv_spacing)), 0, self.config.grid_size_y - 1);
        const idx = self.cellIndex(xi, yi);

        if (self.pressure.cell_type.items[idx] == .air) {
            self.pressure.cell_type.items[idx] = .fluid;
        }
    }

    // Transfer velocities
    const h_sz = self.config.cell_size;
    const h2 = 0.5 * h_sz;

    // Loop comp 0 (u) and 1 (v) using comptime inline for
    inline for (0..2) |comp| {
        const dx = if (comp == 0) 0.0 else h2;
        const dy = if (comp == 0) h2 else 0.0;

        const f = if (comp == 0) self.velocity.u.items else self.velocity.v.items;
        const d = if (comp == 0) self.velocity.du.items else self.velocity.dv.items;
        const particle_velocity = if (comp == 0) self.particles.vel_x.items else self.particles.vel_y.items;

        for (0..self.particles.count) |i| {
            const x = std.math.clamp(pos_x[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_x - 1)) * h_sz);
            const y = std.math.clamp(pos_y[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_y - 1)) * h_sz);

            const x0 = @min(@as(i32, @intFromFloat((x - dx) * inv_spacing)), self.config.grid_size_x - 2);
            const x1 = @min(x0 + 1, self.config.grid_size_x - 1);
            const y0 = @min(@as(i32, @intFromFloat((y - dy) * inv_spacing)), self.config.grid_size_y - 2);
            const y1 = @min(y0 + 1, self.config.grid_size_y - 1);

            var w00: f32 = undefined;
            var w10: f32 = undefined;
            var w11: f32 = undefined;
            var w01: f32 = undefined;
            utils.bilinearWeights((x - dx) * inv_spacing, (y - dy) * inv_spacing, &w00, &w10, &w11, &w01);

            const n = self.config.grid_size_y;
            const _i00: usize = @intCast(x0 * n + y0);
            const _i10: usize = @intCast(x1 * n + y0);
            const _i11: usize = @intCast(x1 * n + y1);
            const _i01: usize = @intCast(x0 * n + y1);

            const velocity_value = particle_velocity[i];
            f[_i00] += w00 * velocity_value;
            f[_i10] += w10 * velocity_value;
            f[_i11] += w11 * velocity_value;
            f[_i01] += w01 * velocity_value;

            d[_i00] += w00;
            d[_i10] += w10;
            d[_i11] += w11;
            d[_i01] += w01;
        }

        // Normalize
        for (0..self.config.num_cells) |i| {
            if (d[i] > 0.0) {
                f[i] /= d[i];
            }
        }
    }

    // Restore solid velocities
    var i: i32 = 0;
    while (i < self.config.grid_size_x) : (i += 1) {
        var j: i32 = 0;
        while (j < self.config.grid_size_y) : (j += 1) {
            const idx = self.cellIndex(i, j);
            const solid = self.pressure.cell_type.items[idx] == .solid;

            if (solid or (i > 0 and self.pressure.cell_type.items[self.cellIndex(i - 1, j)] == .solid)) {
                self.velocity.u.items[idx] = 0.0;
            }

            if (solid or (j > 0 and self.pressure.cell_type.items[self.cellIndex(i, j - 1)] == .solid)) {
                self.velocity.v.items[idx] = 0.0;
            }
        }
    }

    // Save PIC velocities (Copy slices)
    @memcpy(self.velocity.prev_u.items, self.velocity.u.items);
    @memcpy(self.velocity.prev_v.items, self.velocity.v.items);
}

fn computeDensity(self: *FlipFluid) void {
    @memset(self.pressure.density.items, 0.0);

    const h_sz = self.config.cell_size;
    const h2 = h_sz * 0.5;
    const inv_spacing = self.config.inv_cell_size;
    const n = self.config.grid_size_y;

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const dens = self.pressure.density.items;

    for (0..self.particles.count) |i| {
        const x = std.math.clamp(pos_x[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_x - 1)) * h_sz);
        const y = std.math.clamp(pos_y[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_y - 1)) * h_sz);

        const x0 = @as(i32, @intFromFloat((x - h2) * inv_spacing));
        const x1 = @min(x0 + 1, self.config.grid_size_x - 2);
        const y0 = @as(i32, @intFromFloat((y - h2) * inv_spacing));
        const y1 = @min(y0 + 1, self.config.grid_size_y - 2);

        var w00: f32 = undefined;
        var w10: f32 = undefined;
        var w11: f32 = undefined;
        var w01: f32 = undefined;
        utils.bilinearWeights((x - h2) * inv_spacing, (y - h2) * inv_spacing, &w00, &w10, &w11, &w01);
        dens[@intCast(x0 * n + y0)] += w00;
        dens[@intCast(x1 * n + y0)] += w10;
        dens[@intCast(x1 * n + y1)] += w11;
        dens[@intCast(x0 * n + y1)] += w01;
    }

    if (self.config.rest_density == 0.0) {
        var sum: f32 = 0.0;
        var count: f32 = 0.0;

        for (0..self.config.num_cells) |idx| {
            if (self.pressure.cell_type.items[idx] == .fluid) {
                sum += self.pressure.density.items[idx];
                count += 1.0;
            }
        }

        if (count > 0.0) {
            self.config.rest_density = sum / count;
        }
    }
}

fn solvePressure(self: *FlipFluid, num_iters: i32, dt: f32, over_relaxation: f32) void {
    @memset(self.pressure.p.items, 0.0);

    const cp = (self.config.density * self.config.cell_size) / dt;

    const u = self.velocity.u.items;
    const v = self.velocity.v.items;
    const p = self.pressure.p.items;
    const s = self.pressure.s.items;
    const dens = self.pressure.density.items;
    const type_arr = self.pressure.cell_type.items;

    var iter: i32 = 0;
    while (iter < num_iters) : (iter += 1) {
        var rb: i32 = 0;
        while (rb < 2) : (rb += 1) {
            var i: i32 = 1;
            while (i < self.config.grid_size_x - 1) : (i += 1) {
                var j: i32 = 1;
                while (j < self.config.grid_size_y - 1) : (j += 1) {
                    if (@mod(i + j, 2) != rb) continue;

                    const c = self.cellIndex(i, j);
                    if (type_arr[c] != .fluid) continue;

                    const l = self.cellIndex(i - 1, j);
                    const r = self.cellIndex(i + 1, j);
                    const b = self.cellIndex(i, j - 1);
                    const t = self.cellIndex(i, j + 1);

                    const sx0 = s[l];
                    const sx1 = s[r];
                    const sy0 = s[b];
                    const sy1 = s[t];
                    const solid_sum = sx0 + sx1 + sy0 + sy1;

                    if (solid_sum == 0.0) continue;

                    var div = u[r] - u[c] + v[t] - v[c];

                    if (self.config.rest_density > 0.0) {
                        const compression = dens[c] - self.config.rest_density;
                        if (compression > 0.0) {
                            div -= compression;
                        }
                    }

                    const pressure_update = (-div / solid_sum) * over_relaxation;
                    p[c] += cp * pressure_update;
                    u[c] -= sx0 * pressure_update;
                    u[r] += sx1 * pressure_update;
                    v[c] -= sy0 * pressure_update;
                    v[t] += sy1 * pressure_update;
                }
            }
        }
    }
}

fn transferToParticles(self: *FlipFluid, flip_ratio: f32) void {
    const h_sz = self.config.cell_size;
    const h2 = h_sz * 0.5;
    const inv_spacing = self.config.inv_cell_size;
    const n = self.config.grid_size_y;

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const vel_x = self.particles.vel_x.items;
    const vel_y = self.particles.vel_y.items;

    const u = self.velocity.u.items;
    const v = self.velocity.v.items;
    const prev_u = self.velocity.prev_u.items;
    const prev_v = self.velocity.prev_v.items;
    const type_arr = self.pressure.cell_type.items;

    for (0..self.particles.count) |i| {
        const x = std.math.clamp(pos_x[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_x - 1)) * h_sz);
        const y = std.math.clamp(pos_y[i], h_sz, @as(f32, @floatFromInt(self.config.grid_size_y - 1)) * h_sz);

        // U component
        {
            const x0 = @min(@as(i32, @intFromFloat(x * inv_spacing)), self.config.grid_size_x - 2);
            const x1 = @min(x0 + 1, self.config.grid_size_x - 1);
            const y0 = @min(@as(i32, @intFromFloat((y - h2) * inv_spacing)), self.config.grid_size_y - 2);
            const y1 = @min(y0 + 1, self.config.grid_size_y - 2);

            var w00: f32 = undefined;
            var w10: f32 = undefined;
            var w11: f32 = undefined;
            var w01: f32 = undefined;

            utils.bilinearWeights(x * inv_spacing, (y - h2) * inv_spacing, &w00, &w10, &w11, &w01);

            const _i00: usize = @intCast(x0 * n + y0);
            const _i10: usize = @intCast(x1 * n + y0);
            const _i11: usize = @intCast(x1 * n + y1);
            const _i01: usize = @intCast(x0 * n + y1);

            // Helper to check valid cells (Note: Zig usize doesn't support negative indexing, assume logic matches C++)
            // We use @intCast which wraps on negative, but here indices are calculated from clamped positions so they are safe > 0
            const v0: f32 = if (type_arr[_i00] != .air or type_arr[_i00 - @as(usize, @intCast(n))] != .air) 1.0 else 0.0;
            const v1: f32 = if (type_arr[_i10] != .air or type_arr[_i10 - @as(usize, @intCast(n))] != .air) 1.0 else 0.0;
            const v2: f32 = if (type_arr[_i11] != .air or type_arr[_i11 - @as(usize, @intCast(n))] != .air) 1.0 else 0.0;
            const v3: f32 = if (type_arr[_i01] != .air or type_arr[_i01 - @as(usize, @intCast(n))] != .air) 1.0 else 0.0;

            const tw = v0 * w00 + v1 * w10 + v2 * w11 + v3 * w01;

            if (tw > 0.0) {
                const pic = (v0 * w00 * u[_i00] + v1 * w10 * u[_i10] + v2 * w11 * u[_i11] + v3 * w01 * u[_i01]) / tw;
                const corr = (v0 * w00 * (u[_i00] - prev_u[_i00]) + v1 * w10 * (u[_i10] - prev_u[_i10]) +
                    v2 * w11 * (u[_i11] - prev_u[_i11]) + v3 * w01 * (u[_i01] - prev_u[_i01])) / tw;

                vel_x[i] = (1.0 - flip_ratio) * pic + flip_ratio * (vel_x[i] + corr);
            }
        }

        // V component
        {
            const x0 = @min(@as(i32, @intFromFloat((x - h2) * inv_spacing)), self.config.grid_size_x - 2);
            const x1 = @min(x0 + 1, self.config.grid_size_x - 1);
            const y0 = @min(@as(i32, @intFromFloat(y * inv_spacing)), self.config.grid_size_y - 2);
            const y1 = @min(y0 + 1, self.config.grid_size_y - 2);

            var w00: f32 = undefined;
            var w10: f32 = undefined;
            var w11: f32 = undefined;
            var w01: f32 = undefined;
            utils.bilinearWeights((x - h2) * inv_spacing, y * inv_spacing, &w00, &w10, &w11, &w01);

            const _i00: usize = @intCast(x0 * n + y0);
            const _i10: usize = @intCast(x1 * n + y0);
            const _i11: usize = @intCast(x1 * n + y1);
            const _i01: usize = @intCast(x0 * n + y1);

            const v0: f32 = if (type_arr[_i00] != .air or type_arr[_i00 - 1] != .air) 1.0 else 0.0;
            const v1: f32 = if (type_arr[_i10] != .air or type_arr[_i10 - 1] != .air) 1.0 else 0.0;
            const v2: f32 = if (type_arr[_i11] != .air or type_arr[_i11 - 1] != .air) 1.0 else 0.0;
            const v3: f32 = if (type_arr[_i01] != .air or type_arr[_i01 - 1] != .air) 1.0 else 0.0;

            const tw = v0 * w00 + v1 * w10 + v2 * w11 + v3 * w01;

            if (tw > 0.0) {
                const pic = (v0 * w00 * v[_i00] + v1 * w10 * v[_i10] + v2 * w11 * v[_i11] + v3 * w01 * v[_i01]) / tw;
                const corr = (v0 * w00 * (v[_i00] - prev_v[_i00]) + v1 * w10 * (v[_i10] - prev_v[_i10]) +
                    v2 * w11 * (v[_i11] - prev_v[_i11]) + v3 * w01 * (v[_i01] - prev_v[_i01])) / tw;

                vel_y[i] = (1.0 - flip_ratio) * pic + flip_ratio * (vel_y[i] + corr);
            }
        }
    }
}

fn updateVisuals(self: *FlipFluid) void {
    const s = 0.01;
    const d0 = self.config.rest_density;
    const has_rest = d0 > 0.0;
    const inv_spacing = self.config.inv_cell_size;

    const pos_x = self.particles.pos_x.items;
    const pos_y = self.particles.pos_y.items;
    const col_r = self.particles.color_r.items;
    const col_g = self.particles.color_g.items;
    const col_b = self.particles.color_b.items;

    for (0..self.particles.count) |i| {
        col_r[i] = std.math.clamp(col_r[i] - s, 0.0, 1.0);
        col_g[i] = std.math.clamp(col_g[i] - s, 0.0, 1.0);
        col_b[i] = std.math.clamp(col_b[i] + s, 0.0, 1.0);

        if (has_rest) {
            const xi = std.math.clamp(@as(i32, @intFromFloat(pos_x[i] * inv_spacing)), 1, self.config.grid_size_x - 1);
            const yi = std.math.clamp(@as(i32, @intFromFloat(pos_y[i] * inv_spacing)), 1, self.config.grid_size_y - 1);
            const idx = self.cellIndex(xi, yi);
            const rel_dens = self.pressure.density.items[idx] / d0;

            if (rel_dens < 0.7) {
                col_r[i] = 0.8;
                col_g[i] = 0.8;
                col_b[i] = 1.0;
            }
        }
    }
}

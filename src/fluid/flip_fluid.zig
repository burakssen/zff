// ponytail: optimized FLIP fluid simulation core with optimized stride indexing
const std = @import("std");

const ParticleData = @import("particle_data.zig");
const PressureGrid = @import("pressure_grid.zig");
const VelocityGrid = @import("velocity_grid.zig");
const SpatialHash = @import("spatial_hash.zig");

const FlipFluid = @This();

pub const Obstacle = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    radius: f32 = 0.15,
    vel_x: f32 = 0.0,
    vel_y: f32 = 0.0,
};

pub const SimParams = struct {
    dt: f32 = 1.0 / 60.0,
    gravity: f32 = -9.81,
    flip_ratio: f32 = 0.9,
    num_pressure_iters: i32 = 20,
    num_particle_iters: i32 = 2,
    over_relaxation: f32 = 1.9,
};

allocator: std.mem.Allocator,
particles: ParticleData,
scratch_particles: ParticleData,
pressure: PressureGrid,
velocity: VelocityGrid,
spatial_hash: SpatialHash,

// Grid parameters
grid_size_x: i32,
grid_size_y: i32,
num_cells: usize,
cell_size: f32,
inv_cell_size: f32,
particle_radius: f32,
density: f32,
rest_density: f32 = 0.0,

pub const StencilWeights = struct {
    w00: f32,
    w10: f32,
    w11: f32,
    w01: f32,
};

pub fn init(allocator: std.mem.Allocator, density: f32, width: f32, height: f32, spacing: f32, particle_radius: f32, max_particles: usize) !FlipFluid {
    if (width <= 0.0 or height <= 0.0 or spacing <= 0.0 or particle_radius <= 0.0 or density <= 0.0) {
        return error.InvalidParameter;
    }

    const gx: i32 = @as(i32, @intFromFloat(std.math.floor(width / spacing))) + 1;
    const gy: i32 = @as(i32, @intFromFloat(std.math.floor(height / spacing))) + 1;
    const cell_sz = @max(width / @as(f32, @floatFromInt(gx)), height / @as(f32, @floatFromInt(gy)));
    const num_cells: usize = @intCast(gx * gy);

    var particles = try ParticleData.init(allocator, max_particles);
    errdefer particles.deinit(allocator);

    var scratch_particles = try ParticleData.init(allocator, max_particles);
    errdefer scratch_particles.deinit(allocator);

    var velocity = try VelocityGrid.init(allocator, num_cells);
    errdefer velocity.deinit(allocator);

    var pressure = try PressureGrid.init(allocator, num_cells);
    errdefer pressure.deinit(allocator);

    const hash_spacing = 2.2 * particle_radius;
    const hash_size_x: i32 = @as(i32, @intFromFloat(std.math.floor(width / hash_spacing))) + 1;
    const hash_size_y: i32 = @as(i32, @intFromFloat(std.math.floor(height / hash_spacing))) + 1;
    var spatial_hash = try SpatialHash.init(allocator, hash_size_x, hash_size_y, 1.0 / hash_spacing);
    errdefer spatial_hash.deinit(allocator);

    return FlipFluid{
        .allocator = allocator,
        .particles = particles,
        .scratch_particles = scratch_particles,
        .pressure = pressure,
        .velocity = velocity,
        .spatial_hash = spatial_hash,
        .grid_size_x = gx,
        .grid_size_y = gy,
        .num_cells = num_cells,
        .cell_size = cell_sz,
        .inv_cell_size = 1.0 / cell_sz,
        .particle_radius = particle_radius,
        .density = density,
    };
}

pub fn deinit(self: *FlipFluid) void {
    self.particles.deinit(self.allocator);
    self.scratch_particles.deinit(self.allocator);
    self.pressure.deinit(self.allocator);
    self.velocity.deinit(self.allocator);
    self.spatial_hash.deinit(self.allocator);
}

pub inline fn numParticles(self: *const FlipFluid) usize {
    return self.particles.count;
}

inline fn cellIndex(self: *const FlipFluid, x: i32, y: i32) usize {
    return @intCast(x * self.grid_size_y + y);
}

inline fn bilinearWeights(fx: f32, fy: f32) StencilWeights {
    const tx = fx - std.math.floor(fx);
    const ty = fy - std.math.floor(fy);
    const sx = 1.0 - tx;
    const sy = 1.0 - ty;
    return .{
        .w00 = sx * sy,
        .w10 = tx * sy,
        .w11 = tx * ty,
        .w01 = sx * ty,
    };
}

pub fn simulate(self: *FlipFluid, params: SimParams, obstacle: Obstacle) void {
    self.integrateParticles(params.dt, params.gravity);
    self.buildSpatialHash();
    self.resolveCollisions(params.num_particle_iters);
    self.handleBoundaryCollisions(obstacle);
    self.transferToGrid();
    self.computeDensity();
    self.solvePressure(params.num_pressure_iters, params.dt, params.over_relaxation);
    self.transferToParticles(params.flip_ratio);
}

fn integrateParticles(self: *FlipFluid, dt: f32, gravity: f32) void {
    const particle_count = self.particles.count;
    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const vel_x = self.particles.vel_x;
    const vel_y = self.particles.vel_y;
    const dt_gravity = dt * gravity;

    var i: usize = 0;
    while (i + 4 <= particle_count) : (i += 4) {
        inline for (0..4) |offset| {
            const idx = i + offset;
            vel_y[idx] += dt_gravity;
            pos_x[idx] += vel_x[idx] * dt;
            pos_y[idx] += vel_y[idx] * dt;
        }
    }

    while (i < particle_count) : (i += 1) {
        vel_y[i] += dt_gravity;
        pos_x[i] += vel_x[i] * dt;
        pos_y[i] += vel_y[i] * dt;
    }
}

fn buildSpatialHash(self: *FlipFluid) void {
    self.spatial_hash.clear();

    const n = self.particles.count;
    const inv_spacing = self.spatial_hash.inv_spacing;
    const max_x = self.spatial_hash.grid_size_x - 1;
    const max_y = self.spatial_hash.grid_size_y - 1;
    const hgy: usize = @intCast(self.spatial_hash.grid_size_y);

    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const num_cell = self.spatial_hash.num_cell_particles;

    for (0..n) |i| {
        const xi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(pos_x[i] * inv_spacing)), 0, max_x));
        const yi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(pos_y[i] * inv_spacing)), 0, max_y));
        const idx = xi * hgy + yi;
        num_cell[idx] += 1;
    }

    var sum: i32 = 0;
    const first = self.spatial_hash.first_cell_particle;
    for (0..self.spatial_hash.num_cells) |i| {
        first[i] = sum;
        sum += num_cell[i];
    }
    first[self.spatial_hash.num_cells] = sum;

    // ponytail: reuse pre-allocated cell_cursor buffer instead of dynamic heap allocation
    const cell_cursor = self.spatial_hash.cell_cursor;
    @memcpy(cell_cursor[0 .. self.spatial_hash.num_cells + 1], first[0 .. self.spatial_hash.num_cells + 1]);

    for (0..n) |i| {
        const x = pos_x[i];
        const y = pos_y[i];
        const xi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(x * inv_spacing)), 0, max_x));
        const yi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(y * inv_spacing)), 0, max_y));
        const idx = xi * hgy + yi;

        const dest: usize = @intCast(cell_cursor[idx]);
        cell_cursor[idx] += 1;

        inline for (ParticleData.fields) |field_name| {
            @field(self.scratch_particles, field_name)[dest] = @field(self.particles, field_name)[i];
        }
    }

    // ponytail: swap particle structs instead of copying 4 arrays with @memcpy
    std.mem.swap(ParticleData, &self.particles, &self.scratch_particles);
    self.particles.count = n;
}

fn resolveCollisions(self: *FlipFluid, numIters: i32) void {
    const min_dist = 2.0 * self.particle_radius;
    const min_dist_2 = min_dist * min_dist;

    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const first = self.spatial_hash.first_cell_particle;
    const hgy: usize = @intCast(self.spatial_hash.grid_size_y);
    const hgx: i32 = self.spatial_hash.grid_size_x;
    const hgy_i: i32 = self.spatial_hash.grid_size_y;

    var iter: i32 = 0;
    while (iter < numIters) : (iter += 1) {
        var color: i32 = 0;
        while (color < 9) : (color += 1) {
            const shiftX = @mod(color, 3);
            const shiftY = @divTrunc(color, 3);

            var xi = shiftX;
            while (xi < hgx) : (xi += 3) {
                const u_xi: usize = @intCast(xi);
                const col_off = u_xi * hgy;

                var yi = shiftY;
                while (yi < hgy_i) : (yi += 3) {
                    const u_yi: usize = @intCast(yi);
                    const cell_idx = col_off + u_yi;
                    const start: usize = @intCast(first[cell_idx]);
                    const end: usize = @intCast(first[cell_idx + 1]);
                    if (start == end) continue;

                    const x0 = @max(xi - 1, 0);
                    const y0 = @max(yi - 1, 0);
                    const x1 = @min(xi + 1, hgx - 1);
                    const y1 = @min(yi + 1, hgy_i - 1);

                    var i = start;
                    while (i < end) : (i += 1) {
                        var nxi = x0;
                        while (nxi <= x1) : (nxi += 1) {
                            const ncol_off: usize = @as(usize, @intCast(nxi)) * hgy;
                            var nyi = y0;
                            while (nyi <= y1) : (nyi += 1) {
                                const neighbor_cell_index = ncol_off + @as(usize, @intCast(nyi));
                                const neighbor_start: usize = @intCast(first[neighbor_cell_index]);
                                const neighbor_end: usize = @intCast(first[neighbor_cell_index + 1]);

                                var j = neighbor_start;
                                while (j < neighbor_end) : (j += 1) {
                                    if (j <= i) continue;

                                    const dx = pos_x[j] - pos_x[i];
                                    const dy = pos_y[j] - pos_y[i];
                                    const d2 = dx * dx + dy * dy;

                                    if (d2 > min_dist_2 or d2 == 0.0) continue;

                                    const inv_d = 1.0 / std.math.sqrt(d2);
                                    const s = 0.5 * (min_dist * inv_d - 1.0);

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

fn handleBoundaryCollisions(self: *FlipFluid, obstacle: Obstacle) void {
    const min_x = self.cell_size + self.particle_radius;
    const max_x = @as(f32, @floatFromInt(self.grid_size_x - 1)) * self.cell_size - self.particle_radius;
    const min_y = self.cell_size + self.particle_radius;
    const max_y = @as(f32, @floatFromInt(self.grid_size_y - 1)) * self.cell_size - self.particle_radius;
    const min_dist_2 = (obstacle.radius + self.particle_radius) * (obstacle.radius + self.particle_radius);

    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const vel_x = self.particles.vel_x;
    const vel_y = self.particles.vel_y;

    for (0..self.particles.count) |i| {
        var x = pos_x[i];
        var y = pos_y[i];

        const dx = x - obstacle.x;
        const dy = y - obstacle.y;
        if (dx * dx + dy * dy < min_dist_2) {
            vel_x[i] = obstacle.vel_x;
            vel_y[i] = obstacle.vel_y;
        }

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

    for (0..self.num_cells) |i| {
        self.pressure.cell_type[i] = if (self.pressure.s[i] == 0.0) .solid else .air;
    }

    const inv_spacing = self.inv_cell_size;
    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const gy: usize = @intCast(self.grid_size_y);

    for (0..self.particles.count) |i| {
        const xi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(pos_x[i] * inv_spacing)), 0, self.grid_size_x - 1));
        const yi: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(pos_y[i] * inv_spacing)), 0, self.grid_size_y - 1));
        const idx = xi * gy + yi;

        if (self.pressure.cell_type[idx] == .air) {
            self.pressure.cell_type[idx] = .fluid;
        }
    }

    const h_sz = self.cell_size;
    const h2 = 0.5 * h_sz;
    const max_x_bound = @as(f32, @floatFromInt(self.grid_size_x - 1)) * h_sz;
    const max_y_bound = @as(f32, @floatFromInt(self.grid_size_y - 1)) * h_sz;

    for (0..self.particles.count) |i| {
        const x = std.math.clamp(pos_x[i], h_sz, max_x_bound);
        const y = std.math.clamp(pos_y[i], h_sz, max_y_bound);

        {
            const fx = x * inv_spacing;
            const fy = (y - h2) * inv_spacing;
            const x0 = @min(@as(i32, @intFromFloat(fx)), self.grid_size_x - 2);
            const x1 = @min(x0 + 1, self.grid_size_x - 1);
            const y0 = @min(@as(i32, @intFromFloat(fy)), self.grid_size_y - 2);
            const y1 = @min(y0 + 1, self.grid_size_y - 1);

            const w = bilinearWeights(fx, fy);

            const _i00: usize = @intCast(x0 * self.grid_size_y + y0);
            const _i10: usize = @intCast(x1 * self.grid_size_y + y0);
            const _i11: usize = @intCast(x1 * self.grid_size_y + y1);
            const _i01: usize = @intCast(x0 * self.grid_size_y + y1);

            const velocity_val = self.particles.vel_x[i];
            self.velocity.u[_i00] += w.w00 * velocity_val;
            self.velocity.u[_i10] += w.w10 * velocity_val;
            self.velocity.u[_i11] += w.w11 * velocity_val;
            self.velocity.u[_i01] += w.w01 * velocity_val;

            self.velocity.du[_i00] += w.w00;
            self.velocity.du[_i10] += w.w10;
            self.velocity.du[_i11] += w.w11;
            self.velocity.du[_i01] += w.w01;
        }

        {
            const fx = (x - h2) * inv_spacing;
            const fy = y * inv_spacing;
            const x0 = @min(@as(i32, @intFromFloat(fx)), self.grid_size_x - 2);
            const x1 = @min(x0 + 1, self.grid_size_x - 1);
            const y0 = @min(@as(i32, @intFromFloat(fy)), self.grid_size_y - 2);
            const y1 = @min(y0 + 1, self.grid_size_y - 1);

            const w = bilinearWeights(fx, fy);

            const _i00: usize = @intCast(x0 * self.grid_size_y + y0);
            const _i10: usize = @intCast(x1 * self.grid_size_y + y0);
            const _i11: usize = @intCast(x1 * self.grid_size_y + y1);
            const _i01: usize = @intCast(x0 * self.grid_size_y + y1);

            const velocity_val = self.particles.vel_y[i];
            self.velocity.v[_i00] += w.w00 * velocity_val;
            self.velocity.v[_i10] += w.w10 * velocity_val;
            self.velocity.v[_i11] += w.w11 * velocity_val;
            self.velocity.v[_i01] += w.w01 * velocity_val;

            self.velocity.dv[_i00] += w.w00;
            self.velocity.dv[_i10] += w.w10;
            self.velocity.dv[_i11] += w.w11;
            self.velocity.dv[_i01] += w.w01;
        }
    }

    for (0..self.num_cells) |i| {
        if (self.velocity.du[i] > 0.0) {
            self.velocity.u[i] /= self.velocity.du[i];
        }
        if (self.velocity.dv[i] > 0.0) {
            self.velocity.v[i] /= self.velocity.dv[i];
        }
    }

    var i: i32 = 0;
    while (i < self.grid_size_x) : (i += 1) {
        var j: i32 = 0;
        while (j < self.grid_size_y) : (j += 1) {
            const idx = self.cellIndex(i, j);
            const solid = self.pressure.cell_type[idx] == .solid;

            if (solid or (i > 0 and self.pressure.cell_type[self.cellIndex(i - 1, j)] == .solid)) {
                self.velocity.u[idx] = 0.0;
            }

            if (solid or (j > 0 and self.pressure.cell_type[self.cellIndex(i, j - 1)] == .solid)) {
                self.velocity.v[idx] = 0.0;
            }
        }
    }

    @memcpy(self.velocity.prev_u, self.velocity.u);
    @memcpy(self.velocity.prev_v, self.velocity.v);
}

fn computeDensity(self: *FlipFluid) void {
    @memset(self.pressure.density, 0.0);

    const h_sz = self.cell_size;
    const h2 = h_sz * 0.5;
    const inv_spacing = self.inv_cell_size;
    const n = self.grid_size_y;
    const max_x_bound = @as(f32, @floatFromInt(self.grid_size_x - 1)) * h_sz;
    const max_y_bound = @as(f32, @floatFromInt(self.grid_size_y - 1)) * h_sz;

    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const dens = self.pressure.density;

    for (0..self.particles.count) |i| {
        const x = std.math.clamp(pos_x[i], h_sz, max_x_bound);
        const y = std.math.clamp(pos_y[i], h_sz, max_y_bound);

        const fx = (x - h2) * inv_spacing;
        const fy = (y - h2) * inv_spacing;
        const x0 = @as(i32, @intFromFloat(fx));
        const x1 = @min(x0 + 1, self.grid_size_x - 2);
        const y0 = @as(i32, @intFromFloat(fy));
        const y1 = @min(y0 + 1, self.grid_size_y - 2);

        const w = bilinearWeights(fx, fy);
        dens[@intCast(x0 * n + y0)] += w.w00;
        dens[@intCast(x1 * n + y0)] += w.w10;
        dens[@intCast(x1 * n + y1)] += w.w11;
        dens[@intCast(x0 * n + y1)] += w.w01;
    }

    if (self.rest_density == 0.0) {
        var sum: f32 = 0.0;
        var count: f32 = 0.0;

        for (0..self.num_cells) |idx| {
            if (self.pressure.cell_type[idx] == .fluid) {
                sum += self.pressure.density[idx];
                count += 1.0;
            }
        }

        if (count > 0.0) {
            self.rest_density = sum / count;
        }
    }
}

fn solvePressure(self: *FlipFluid, num_iters: i32, dt: f32, over_relaxation: f32) void {
    @memset(self.pressure.p, 0.0);

    const cp = (self.density * self.cell_size) / dt;

    const u = self.velocity.u;
    const v = self.velocity.v;
    const p = self.pressure.p;
    const s = self.pressure.s;
    const dens = self.pressure.density;
    const type_arr = self.pressure.cell_type;

    const gy: usize = @intCast(self.grid_size_y);
    const gx: usize = @intCast(self.grid_size_x);
    const has_rest = self.rest_density > 0.0;
    const rest_d = self.rest_density;

    var iter: i32 = 0;
    while (iter < num_iters) : (iter += 1) {
        var rb: usize = 0;
        while (rb < 2) : (rb += 1) {
            var i: usize = 1;
            while (i < gx - 1) : (i += 1) {
                const col_offset = i * gy;
                const start_j: usize = 1 + ((i + 1 + rb) % 2);
                var j: usize = start_j;
                while (j < gy - 1) : (j += 2) {
                    const c = col_offset + j;
                    if (type_arr[c] != .fluid) continue;

                    const l = c - gy;
                    const r = c + gy;
                    const b = c - 1;
                    const t = c + 1;

                    const sx0 = s[l];
                    const sx1 = s[r];
                    const sy0 = s[b];
                    const sy1 = s[t];
                    const solid_sum = sx0 + sx1 + sy0 + sy1;

                    if (solid_sum == 0.0) continue;

                    var div = u[r] - u[c] + v[t] - v[c];

                    if (has_rest) {
                        const compression = dens[c] - rest_d;
                        if (compression > 0.0) {
                            div -= compression;
                        }
                    }

                    const pressure_update = (-div / solid_sum) * over_relaxation;
                    const cp_update = cp * pressure_update;
                    p[c] += cp_update;
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
    const h_sz = self.cell_size;
    const h2 = h_sz * 0.5;
    const inv_spacing = self.inv_cell_size;
    const max_x_bound = @as(f32, @floatFromInt(self.grid_size_x - 1)) * h_sz;
    const max_y_bound = @as(f32, @floatFromInt(self.grid_size_y - 1)) * h_sz;

    const pos_x = self.particles.pos_x;
    const pos_y = self.particles.pos_y;
    const vel_x = self.particles.vel_x;
    const vel_y = self.particles.vel_y;

    const u = self.velocity.u;
    const v = self.velocity.v;
    const prev_u = self.velocity.prev_u;
    const prev_v = self.velocity.prev_v;
    const type_arr = self.pressure.cell_type;
    const gy_us: usize = @intCast(self.grid_size_y);

    for (0..self.particles.count) |i| {
        const x = std.math.clamp(pos_x[i], h_sz, max_x_bound);
        const y = std.math.clamp(pos_y[i], h_sz, max_y_bound);

        // U component
        {
            const fx = x * inv_spacing;
            const fy = (y - h2) * inv_spacing;
            const x0 = @min(@as(i32, @intFromFloat(fx)), self.grid_size_x - 2);
            const y0 = @min(@as(i32, @intFromFloat(fy)), self.grid_size_y - 2);

            const w = bilinearWeights(fx, fy);

            const _i00: usize = @intCast(x0 * self.grid_size_y + y0);
            const _i10: usize = _i00 + gy_us;
            const _i01: usize = _i00 + 1;
            const _i11: usize = _i10 + 1;

            const v0: f32 = if (type_arr[_i00] != .air or (_i00 >= gy_us and type_arr[_i00 - gy_us] != .air)) 1.0 else 0.0;
            const v1: f32 = if (type_arr[_i10] != .air or (_i10 >= gy_us and type_arr[_i10 - gy_us] != .air)) 1.0 else 0.0;
            const v2: f32 = if (type_arr[_i11] != .air or (_i11 >= gy_us and type_arr[_i11 - gy_us] != .air)) 1.0 else 0.0;
            const v3: f32 = if (type_arr[_i01] != .air or (_i01 >= gy_us and type_arr[_i01 - gy_us] != .air)) 1.0 else 0.0;

            const tw = v0 * w.w00 + v1 * w.w10 + v2 * w.w11 + v3 * w.w01;

            if (tw > 0.0) {
                const pic = (v0 * w.w00 * u[_i00] + v1 * w.w10 * u[_i10] + v2 * w.w11 * u[_i11] + v3 * w.w01 * u[_i01]) / tw;
                const corr = (v0 * w.w00 * (u[_i00] - prev_u[_i00]) + v1 * w.w10 * (u[_i10] - prev_u[_i10]) +
                    v2 * w.w11 * (u[_i11] - prev_u[_i11]) + v3 * w.w01 * (u[_i01] - prev_u[_i01])) / tw;

                vel_x[i] = (1.0 - flip_ratio) * pic + flip_ratio * (vel_x[i] + corr);
            }
        }

        // V component
        {
            const fx = (x - h2) * inv_spacing;
            const fy = y * inv_spacing;
            const x0 = @min(@as(i32, @intFromFloat(fx)), self.grid_size_x - 2);
            const y0 = @min(@as(i32, @intFromFloat(fy)), self.grid_size_y - 2);

            const w = bilinearWeights(fx, fy);

            const _i00: usize = @intCast(x0 * self.grid_size_y + y0);
            const _i10: usize = _i00 + gy_us;
            const _i01: usize = _i00 + 1;
            const _i11: usize = _i10 + 1;

            const v0: f32 = if (type_arr[_i00] != .air or (_i00 > 0 and type_arr[_i00 - 1] != .air)) 1.0 else 0.0;
            const v1: f32 = if (type_arr[_i10] != .air or (_i10 > 0 and type_arr[_i10 - 1] != .air)) 1.0 else 0.0;
            const v2: f32 = if (type_arr[_i11] != .air or (_i11 > 0 and type_arr[_i11 - 1] != .air)) 1.0 else 0.0;
            const v3: f32 = if (type_arr[_i01] != .air or (_i01 > 0 and type_arr[_i01 - 1] != .air)) 1.0 else 0.0;

            const tw = v0 * w.w00 + v1 * w.w10 + v2 * w.w11 + v3 * w.w01;

            if (tw > 0.0) {
                const pic = (v0 * w.w00 * v[_i00] + v1 * w.w10 * v[_i10] + v2 * w.w11 * v[_i11] + v3 * w.w01 * v[_i01]) / tw;
                const corr = (v0 * w.w00 * (v[_i00] - prev_v[_i00]) + v1 * w.w10 * (v[_i10] - prev_v[_i10]) +
                    v2 * w.w11 * (v[_i11] - prev_v[_i11]) + v3 * w.w01 * (v[_i01] - prev_v[_i01])) / tw;

                vel_y[i] = (1.0 - flip_ratio) * pic + flip_ratio * (vel_y[i] + corr);
            }
        }
    }
}

// ponytail: high performance interleaved OpenGL particle line renderer
const std = @import("std");

const rl = @import("raylib");
const FlipFluid = @import("../fluid/flip_fluid.zig");

const ParticleRenderer = @This();

// ponytail: single interleaved vertex layout (3x f32 pos + 4x u8 color)
pub const ParticleVertex = extern struct {
    x: f32,
    y: f32,
    z: f32 = 0.0,
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

vao_id: u32 = 0,
vbo_id: u32 = 0,
max_particles: usize = 0,

vertex_data: []ParticleVertex,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, max_count: usize) !ParticleRenderer {
    const vertex_count = max_count * 2; // 2 vertices per line segment

    const vertex_data = try allocator.alloc(ParticleVertex, vertex_count);

    const vao_id = rl.rlLoadVertexArray();
    _ = rl.rlEnableVertexArray(vao_id);

    const stride: c_int = @sizeOf(ParticleVertex);
    const vbo_id = rl.rlLoadVertexBuffer(vertex_data.ptr, @intCast(vertex_data.len * @sizeOf(ParticleVertex)), true);

    // Attribute 0: Position (3 x f32)
    rl.rlSetVertexAttribute(0, 3, rl.RL_FLOAT, false, stride, 0);
    rl.rlEnableVertexAttribute(0);

    // Attribute 3: Color (4 x u8, normalized)
    rl.rlSetVertexAttribute(3, 4, rl.RL_UNSIGNED_BYTE, true, stride, @offsetOf(ParticleVertex, "r"));
    rl.rlEnableVertexAttribute(3);

    rl.rlDisableVertexArray();

    return ParticleRenderer{
        .vao_id = vao_id,
        .vbo_id = vbo_id,
        .max_particles = max_count,
        .vertex_data = vertex_data,
        .allocator = allocator,
    };
}

pub fn deinit(self: *ParticleRenderer) void {
    rl.rlUnloadVertexArray(self.vao_id);
    rl.rlUnloadVertexBuffer(self.vbo_id);
    self.allocator.free(self.vertex_data);
}

pub fn draw(self: *ParticleRenderer, flip_fluid: *const FlipFluid, c_scale: f32, height: f32) void {
    const count = flip_fluid.numParticles();
    if (count == 0) return;

    const pos_x = flip_fluid.particles.pos_x;
    const pos_y = flip_fluid.particles.pos_y;
    const vel_x = flip_fluid.particles.vel_x;
    const vel_y = flip_fluid.particles.vel_y;

    // ponytail: pre-multiply scale and trail length constant outside loop
    const trail_scale = 0.01 * c_scale;

    // ponytail: SIMD 8-lane vectorized vertex generation
    const vec_c_scale: @Vector(8, f32) = @splat(c_scale);
    const vec_height: @Vector(8, f32) = @splat(height);
    const vec_trail_scale: @Vector(8, f32) = @splat(trail_scale);

    var i: usize = 0;
    while (i + 8 <= count) : (i += 8) {
        const px8: @Vector(8, f32) = pos_x[i..][0..8].* * vec_c_scale;
        const py8: @Vector(8, f32) = vec_height - (pos_y[i..][0..8].* * vec_c_scale);
        const vx8: @Vector(8, f32) = vel_x[i..][0..8].*;
        const vy8: @Vector(8, f32) = vel_y[i..][0..8].*;

        const speed_sq8: @Vector(8, f32) = vx8 * vx8 + vy8 * vy8;
        const end_x8: @Vector(8, f32) = px8 - (vx8 * vec_trail_scale);
        const end_y8: @Vector(8, f32) = py8 + (vy8 * vec_trail_scale);

        inline for (0..8) |offset| {
            const idx = (i + offset) * 2;
            const spd_sq = speed_sq8[offset];
            const t = if (spd_sq > 15.0) 1.0 else spd_sq * (1.0 / 15.0);

            const r: u8 = @intFromFloat(50.0 + t * 205.0);
            const g: u8 = @intFromFloat(100.0 + t * 155.0);

            var ey = end_y8[offset];
            if (spd_sq < 0.1) ey += 1.5;

            self.vertex_data[idx + 0] = .{
                .x = px8[offset],
                .y = py8[offset],
                .z = 0.0,
                .r = r,
                .g = g,
                .b = 255,
                .a = 255,
            };
            self.vertex_data[idx + 1] = .{
                .x = end_x8[offset],
                .y = ey,
                .z = 0.0,
                .r = r,
                .g = g,
                .b = 255,
                .a = 255,
            };
        }
    }

    while (i < count) : (i += 1) {
        const px = pos_x[i] * c_scale;
        const py = height - (pos_y[i] * c_scale);
        const vx = vel_x[i];
        const vy = vel_y[i];

        const speed_sq = vx * vx + vy * vy;
        const t = if (speed_sq > 15.0) 1.0 else speed_sq / 15.0;

        const r: u8 = @intFromFloat(50.0 + t * 205.0);
        const g: u8 = @intFromFloat(100.0 + t * 155.0);

        const end_x = px - (vx * trail_scale);
        var end_y = py + (vy * trail_scale);
        if (speed_sq < 0.1) end_y += 1.5;

        const idx = i * 2;
        self.vertex_data[idx + 0] = .{
            .x = px,
            .y = py,
            .z = 0.0,
            .r = r,
            .g = g,
            .b = 255,
            .a = 255,
        };
        self.vertex_data[idx + 1] = .{
            .x = end_x,
            .y = end_y,
            .z = 0.0,
            .r = r,
            .g = g,
            .b = 255,
            .a = 255,
        };
    }

    // ponytail: single VBO update call per frame
    rl.rlUpdateVertexBuffer(self.vbo_id, self.vertex_data.ptr, @intCast(count * 2 * @sizeOf(ParticleVertex)), 0);

    const default_shader_id = rl.rlGetShaderIdDefault();
    rl.rlEnableShader(default_shader_id);

    const mat_model_view = rl.rlGetMatrixModelview();
    const mat_projection = rl.rlGetMatrixProjection();
    const mat_mvp = rl.MatrixMultiply(mat_model_view, mat_projection);
    const locs = rl.rlGetShaderLocsDefault();
    rl.rlSetUniformMatrix(locs[rl.RL_SHADER_LOC_MATRIX_MVP], mat_mvp);

    var col = rl.Vector4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    rl.rlSetUniform(locs[rl.RL_SHADER_LOC_COLOR_DIFFUSE], &col, rl.RL_SHADER_UNIFORM_VEC4, 1);

    rl.rlActiveTextureSlot(0);
    rl.rlEnableTexture(rl.rlGetTextureIdDefault());
    var tex_slot: i32 = 0;
    rl.rlSetUniform(locs[rl.RL_SHADER_LOC_MAP_DIFFUSE], &tex_slot, rl.RL_SHADER_UNIFORM_INT, 1);

    _ = rl.rlEnableVertexArray(self.vao_id);
    rl.glDrawArrays(rl.GL_LINES, 0, @intCast(count * 2));
    rl.rlDisableVertexArray();

    rl.rlDisableShader();
}

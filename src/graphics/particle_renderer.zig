// ponytail: high performance OpenGL particle line renderer
const std = @import("std");

const rl = @import("raylib");
const FlipFluid = @import("../fluid/flip_fluid.zig");

const ParticleRenderer = @This();

vao_id: u32 = 0,
pos_buffer_id: u32 = 0,
col_buffer_id: u32 = 0,
max_particles: usize = 0,

pos_data: []f32,
col_data: []u8,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, max_count: usize) !ParticleRenderer {
    const vertex_count = max_count * 2; // Lines

    const pos_data = try allocator.alloc(f32, vertex_count * 3);
    const col_data = try allocator.alloc(u8, vertex_count * 4);

    const vao_id = rl.rlLoadVertexArray();
    _ = rl.rlEnableVertexArray(vao_id);
    const pos_buffer_id = rl.rlLoadVertexBuffer(pos_data.ptr, @intCast(pos_data.len * @sizeOf(f32)), true);
    rl.rlSetVertexAttribute(0, 3, rl.RL_FLOAT, false, 0, 0);
    rl.rlEnableVertexAttribute(0);

    const col_buffer_id = rl.rlLoadVertexBuffer(col_data.ptr, @intCast(col_data.len * @sizeOf(u8)), true);
    rl.rlSetVertexAttribute(3, 4, rl.RL_UNSIGNED_BYTE, true, 0, 0);
    rl.rlEnableVertexAttribute(3);

    rl.rlDisableVertexArray();

    return ParticleRenderer{
        .vao_id = vao_id,
        .pos_buffer_id = pos_buffer_id,
        .col_buffer_id = col_buffer_id,
        .max_particles = max_count,
        .pos_data = pos_data,
        .col_data = col_data,
        .allocator = allocator,
    };
}

pub fn deinit(self: *ParticleRenderer) void {
    rl.rlUnloadVertexArray(self.vao_id);
    rl.rlUnloadVertexBuffer(self.pos_buffer_id);
    rl.rlUnloadVertexBuffer(self.col_buffer_id);
    self.allocator.free(self.pos_data);
    self.allocator.free(self.col_data);
}

pub fn draw(self: *ParticleRenderer, flip_fluid: *const FlipFluid, c_scale: f32, height: f32) void {
    const count = flip_fluid.numParticles();
    if (count == 0) return;

    const pos_x = flip_fluid.particles.pos_x;
    const pos_y = flip_fluid.particles.pos_y;
    const vel_x = flip_fluid.particles.vel_x;
    const vel_y = flip_fluid.particles.vel_y;

    const trail_length: f32 = 0.01;

    for (0..count) |i| {
        const px = pos_x[i] * c_scale;
        const py = height - (pos_y[i] * c_scale);
        const vx = vel_x[i];
        const vy = vel_y[i];

        const speed_sq = vx * vx + vy * vy;
        const t = if (speed_sq > 15.0) 1.0 else speed_sq / 15.0;

        const r: u8 = @intFromFloat(50.0 + t * 205.0);
        const g: u8 = @intFromFloat(100.0 + t * 155.0);
        const b: u8 = 255;

        const _i6 = i * 6;
        const _i8 = i * 8;

        self.pos_data[_i6 + 0] = px;
        self.pos_data[_i6 + 1] = py;
        self.pos_data[_i6 + 2] = 0.0;

        self.col_data[_i8 + 0] = r;
        self.col_data[_i8 + 1] = g;
        self.col_data[_i8 + 2] = b;
        self.col_data[_i8 + 3] = 255;

        const end_x = px - (vx * trail_length * c_scale);
        var end_y = py + (vy * trail_length * c_scale);
        if (speed_sq < 0.1) end_y += 1.5;

        self.pos_data[_i6 + 3] = end_x;
        self.pos_data[_i6 + 4] = end_y;
        self.pos_data[_i6 + 5] = 0.0;

        self.col_data[_i8 + 4] = r;
        self.col_data[_i8 + 5] = g;
        self.col_data[_i8 + 6] = b;
        self.col_data[_i8 + 7] = 255;
    }

    rl.rlUpdateVertexBuffer(self.pos_buffer_id, self.pos_data.ptr, @intCast(count * 2 * 3 * @sizeOf(f32)), 0);
    rl.rlUpdateVertexBuffer(self.col_buffer_id, self.col_data.ptr, @intCast(count * 2 * 4 * @sizeOf(u8)), 0);

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

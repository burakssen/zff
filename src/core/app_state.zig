// ponytail: consolidated main application state and scene controller
const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const ParticleRenderer = @import("../graphics/particle_renderer.zig");
const FlipFluid = @import("../fluid/flip_fluid.zig");

const AppState = @This();

flip_fluid: ?FlipFluid = null,
renderer: ParticleRenderer = undefined,

camera: rl.Camera2D,
render_target: rl.RenderTexture2D,
screen_width: f32 = 1280.0,
screen_height: f32 = 720.0,
coordinate_scale: f32 = 1.0,

// Simulation parameters and obstacle state
sim_params: FlipFluid.SimParams = .{},
obstacle: FlipFluid.Obstacle = .{ .radius = 0.15 },

frame_number: i32 = 0,
paused: bool = true,
show_particles: bool = true,
show_obstacle: bool = true,

// Input state
mouse_down: bool = false,
last_mouse_position: rl.Vector2 = .{ .x = 0, .y = 0 },

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !AppState {
    rl.InitWindow(1280, 720, "FLIP Fluid (Zig + Raylib)");

    rl.SetTargetFPS(0);
    var app = AppState{
        .allocator = allocator,
        .camera = std.mem.zeroes(rl.Camera2D),
        .render_target = undefined,
    };

    app.camera.offset = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.target = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.zoom = 1.0;

    const simulation_height: f32 = 3.0;
    app.coordinate_scale = app.screen_height / simulation_height;
    const simulation_width: f32 = app.screen_width / app.coordinate_scale;

    try app.initializeScene(simulation_width, simulation_height);

    app.render_target = rl.LoadRenderTexture(@intFromFloat(app.screen_width), @intFromFloat(app.screen_height));

    return app;
}

pub fn deinit(self: *AppState) void {
    rl.UnloadRenderTexture(self.render_target);
    if (self.flip_fluid) |*f| {
        f.deinit();
    }
    self.renderer.deinit();
    rl.CloseWindow();
}

pub fn update(self: *AppState) !void {
    self.handleInput();
    if (!self.paused) {
        try self.simulateStep();
    }
    self.renderFrame();
}

fn handleInput(self: *AppState) void {
    if (rl.IsKeyPressed(rl.KEY_P)) {
        self.paused = !self.paused;
    }

    if (rl.IsKeyDown(rl.KEY_M)) {
        if (self.paused) {
            self.simulateStep() catch |err| {
                std.debug.print("Error in simulateStep: {}\n", .{err});
            };
        }
    }

    if (rl.IsMouseButtonDown(rl.MOUSE_LEFT_BUTTON)) {
        const mouse_position = rl.GetMousePosition();
        const x = mouse_position.x / self.coordinate_scale;
        const y = (self.screen_height - mouse_position.y) / self.coordinate_scale;

        if (!self.mouse_down) {
            self.setObstacle(x, y, true);
            self.mouse_down = true;
            self.paused = false;
        } else {
            self.setObstacle(x, y, false);
        }

        self.last_mouse_position = mouse_position;
    }

    if (rl.IsMouseButtonReleased(rl.MOUSE_LEFT_BUTTON)) {
        self.mouse_down = false;
        self.obstacle.vel_x = 0.0;
        self.obstacle.vel_y = 0.0;
    }
}

fn renderFrame(self: *AppState) void {
    rl.BeginTextureMode(self.render_target);
    rl.ClearBackground(rl.BLACK);

    rl.BeginMode2D(self.camera);
    self.drawScene();
    rl.EndMode2D();
    rl.EndTextureMode();

    rl.BeginDrawing();
    rl.ClearBackground(rl.BLACK);

    const source = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.render_target.texture.width), .height = -@as(f32, @floatFromInt(self.render_target.texture.height)) };
    const dest = rl.Rectangle{ .x = 0, .y = 0, .width = self.screen_width, .height = self.screen_height };
    const origin = rl.Vector2{ .x = 0, .y = 0 };
    rl.DrawTexturePro(self.render_target.texture, source, dest, origin, 0.0, rl.WHITE);

    if (self.paused) {
        rl.DrawText("PAUSED", 10, 10, 20, rl.YELLOW);
        rl.DrawText("Press P to Resume | Press M to Step Frame", 10, 35, 16, rl.LIGHTGRAY);
    } else {
        rl.DrawText("Running", 10, 10, 20, rl.GREEN);
        rl.DrawText("Press P to Pause", 10, 35, 16, rl.LIGHTGRAY);
    }

    rl.DrawFPS(@intFromFloat(self.screen_width - 100.0), 10);

    rl.EndDrawing();
}

fn initializeScene(self: *AppState, width: f32, height: f32) !void {
    const tank_height = height;
    const tank_width = width;
    const cell_size = tank_height / 100.0;
    const density = 1000.0;

    const relative_water_height = 0.8;
    const relative_water_width = 0.8;

    const particle_radius = 0.3 * cell_size;
    const delta_x = 2.0 * particle_radius;
    const delta_y = (std.math.sqrt(3.0) / 2.0) * delta_x;

    const num_particles_x: usize = @intFromFloat(std.math.floor((relative_water_width * tank_width - 2.0 * cell_size - 2.0 * particle_radius) / delta_x));
    const num_particles_y: usize = @intFromFloat(std.math.floor((relative_water_height * tank_height - 2.0 * cell_size - 2.0 * particle_radius) / delta_y));
    const max_particles = num_particles_x * num_particles_y;

    self.flip_fluid = try FlipFluid.init(self.allocator, density, tank_width, tank_height, cell_size, particle_radius, max_particles);
    self.renderer = try ParticleRenderer.init(self.allocator, max_particles);

    if (self.flip_fluid) |*f| {
        f.particles.count = num_particles_x * num_particles_y;

        var particle_index: usize = 0;
        for (0..num_particles_x) |i| {
            for (0..num_particles_y) |j| {
                const x_offset = if (j % 2 == 0) 0.0 else particle_radius;
                const float_x = @as(f32, @floatFromInt(i));
                const float_y = @as(f32, @floatFromInt(j));

                f.particles.pos_x[particle_index] = cell_size + particle_radius + delta_x * float_x + x_offset;
                f.particles.pos_y[particle_index] = cell_size + particle_radius + delta_y * float_y;

                particle_index += 1;
            }
        }

        const grid_height: usize = @intCast(f.grid_size_y);
        const grid_width: usize = @intCast(f.grid_size_x);

        for (0..grid_width) |i| {
            for (0..grid_height) |j| {
                const solid_value: f32 = if (i == 0 or i == grid_width - 1 or j == 0) 0.0 else 1.0;
                f.pressure.s[i * grid_height + j] = solid_value;
            }
        }
    }

    self.setObstacle(width / 2.0, height / 2.0, true);
}

fn setObstacle(self: *AppState, x: f32, y: f32, reset: bool) void {
    if (!reset) {
        self.obstacle.vel_x = (x - self.obstacle.x) / self.sim_params.dt;
        self.obstacle.vel_y = (y - self.obstacle.y) / self.sim_params.dt;
    }
    self.obstacle.x = x;
    self.obstacle.y = y;
    self.show_obstacle = true;
}

fn simulateStep(self: *AppState) !void {
    if (self.flip_fluid) |*f| {
        try f.simulate(self.sim_params, self.obstacle);
        self.frame_number += 1;
    }
}

fn drawScene(self: *AppState) void {
    if (self.show_particles) {
        rl.rlDrawRenderBatchActive();
        rl.rlSetBlendMode(rl.RL_BLEND_ADDITIVE);
        if (self.flip_fluid) |*f| {
            self.renderer.draw(f, self.coordinate_scale, self.screen_height);
        }
        rl.rlSetBlendMode(rl.RL_BLEND_ALPHA);
    }

    if (self.show_obstacle) {
        const screen_x = self.obstacle.x * self.coordinate_scale;
        const screen_y = self.screen_height - self.obstacle.y * self.coordinate_scale;
        const screen_radius = self.obstacle.radius * self.coordinate_scale;

        rl.DrawCircle(@intFromFloat(screen_x), @intFromFloat(screen_y), screen_radius, rl.RED);
    }
}

pub fn run(self: *AppState) !void {
    if (builtin.os.tag == .emscripten) {
        const loop = struct {
            fn runLoop(arg: ?*anyopaque) callconv(.c) void {
                const app: *AppState = @ptrCast(@alignCast(arg));
                app.update() catch |err| {
                    std.debug.print("Error in update: {}\n", .{err});
                };
            }
        }.runLoop;

        rl.emscripten_set_main_loop_arg(loop, self, 0, true);
    } else {
        while (!rl.WindowShouldClose()) {
            try self.update();
        }
    }
}

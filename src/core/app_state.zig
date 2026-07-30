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
screen_width: f32 = 1280.0,
screen_height: f32 = 720.0,
coordinate_scale: f32 = 1.0,

// Simulation parameters and obstacle state
sim_params: FlipFluid.SimParams = .{},
obstacle: FlipFluid.Obstacle = .{ .radius = 0.15 },

paused: bool = true,
show_particles: bool = true,
show_obstacle: bool = true,

// Input state
mouse_down: bool = false,

// Fixed-step clock accumulator
accumulator: f32 = 0.0,

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !AppState {
    rl.InitWindow(1280, 720, "FLIP Fluid (Zig + Raylib)");
    rl.SetTargetFPS(0);

    var app = AppState{
        .allocator = allocator,
        .camera = std.mem.zeroes(rl.Camera2D),
    };

    app.camera.offset = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.target = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.zoom = 1.0;

    const simulation_height: f32 = 3.0;
    app.coordinate_scale = app.screen_height / simulation_height;
    const simulation_width: f32 = app.screen_width / app.coordinate_scale;

    try app.initializeScene(simulation_width, simulation_height);

    return app;
}

pub fn deinit(self: *AppState) void {
    if (self.flip_fluid) |*f| {
        f.deinit();
    }
    self.renderer.deinit();
    rl.CloseWindow();
}

pub fn update(self: *AppState) !void {
    self.handleInput();
    if (!self.paused) {
        const step = self.sim_params.dt;
        const max_substeps: usize = 4;
        const frame_time = @min(rl.GetFrameTime(), step * @as(f32, @floatFromInt(max_substeps)));
        self.accumulator += frame_time;

        var substeps: usize = 0;
        while (self.accumulator >= step and substeps < max_substeps) : (substeps += 1) {
            self.simulateStep();
            self.accumulator -= step;
        }
    }
    self.renderFrame();
}

fn handleInput(self: *AppState) void {
    if (rl.IsKeyPressed(rl.KEY_P)) {
        self.paused = !self.paused;
    }

    if (rl.IsKeyPressed(rl.KEY_M)) {
        if (self.paused) {
            self.simulateStep();
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
    }

    if (rl.IsMouseButtonReleased(rl.MOUSE_LEFT_BUTTON)) {
        self.mouse_down = false;
        self.obstacle.vel_x = 0.0;
        self.obstacle.vel_y = 0.0;
    }
}

fn renderFrame(self: *AppState) void {
    // ponytail: render directly to screen buffer without intermediate FBO pass
    rl.BeginDrawing();
    rl.ClearBackground(rl.BLACK);

    rl.BeginMode2D(self.camera);
    self.drawScene();
    rl.EndMode2D();

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

const SceneFactory = @import("../fluid/scene_factory.zig");

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
    errdefer if (self.flip_fluid) |*f| f.deinit();

    self.renderer = try ParticleRenderer.init(self.allocator, max_particles);

    if (self.flip_fluid) |*f| {
        SceneFactory.setupDamBreak(f, .{
            .relative_width = relative_water_width,
            .relative_height = relative_water_height,
            .density = density,
        });
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

pub fn simulateStep(self: *AppState) void {
    if (self.flip_fluid) |*f| {
        f.simulate(self.sim_params, self.obstacle);
    }
}

fn drawScene(self: *AppState) void {
    if (self.show_particles) {
        rl.rlDrawRenderBatchActive();
        rl.rlSetBlendMode(rl.RL_BLEND_ADDITIVE);
        if (self.flip_fluid) |*f| {
            self.renderer.draw(f.particles.view(), self.coordinate_scale, self.screen_height);
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
        const emscripten_set_main_loop_arg = struct {
            extern fn emscripten_set_main_loop_arg(
                func: ?*const fn (?*anyopaque) callconv(.c) void,
                arg: ?*anyopaque,
                fps: c_int,
                simulate_infinite_loop: c_int,
            ) void;
        }.emscripten_set_main_loop_arg;

        const loop = struct {
            fn runLoop(arg: ?*anyopaque) callconv(.c) void {
                const app: *AppState = @ptrCast(@alignCast(arg));
                app.update() catch |err| {
                    std.debug.print("Error in update: {}\n", .{err});
                };
            }
        }.runLoop;

        emscripten_set_main_loop_arg(loop, self, 0, 1);
    } else {
        while (!rl.WindowShouldClose()) {
            try self.update();
        }
    }
}

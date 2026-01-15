const std = @import("std");
const builtin = @import("builtin");

const FluidScene = @import("fluid_scene.zig");

const graphics = @import("graphics");
const c = graphics.c;
const ParticleRenderer = graphics.ParticleRenderer;

const fluid = @import("fluid");
const FlipFluid = fluid.FlipFluid;

const AppState = @This();

scene: FluidScene,
camera: c.Camera2D,
render_target: c.RenderTexture2D,
screen_width: f32 = 1280.0,
screen_height: f32 = 720.0,
coordinate_scale: f32 = 1.0,

// Input state
mouse_down: bool = false,
last_mouse_position: c.Vector2 = .{ .x = 0, .y = 0 },

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !AppState {
    c.InitWindow(1280, 720, "FLIP Fluid (Zig + Raylib)");
    // Don't defer CloseWindow here, handled in deinit or main

    c.SetTargetFPS(0);
    var app = AppState{
        .allocator = allocator,
        .scene = FluidScene.init(allocator),
        .camera = std.mem.zeroes(c.Camera2D),
        .render_target = undefined,
    };

    // Camera Init
    app.camera.offset = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.target = .{ .x = app.screen_width / 2.0, .y = app.screen_height / 2.0 };
    app.camera.zoom = 1.0;

    const simulation_height: f32 = 3.0;
    app.coordinate_scale = app.screen_height / simulation_height;
    const simulation_width: f32 = app.screen_width / app.coordinate_scale;

    try app.initializeScene(simulation_width, simulation_height);

    app.render_target = c.LoadRenderTexture(@intFromFloat(app.screen_width), @intFromFloat(app.screen_height));

    return app;
}

pub fn deinit(self: *AppState) void {
    c.UnloadRenderTexture(self.render_target);
    self.scene.deinit();
    c.CloseWindow();
}

pub fn update(self: *AppState) !void {
    self.handleInput();
    if (!self.scene.paused) {
        try self.simulateStep();
    }
    self.renderFrame();
}

fn handleInput(self: *AppState) void {
    if (c.IsKeyPressed(c.KEY_P)) {
        self.scene.paused = !self.scene.paused;
    }

    if (c.IsKeyDown(c.KEY_M)) {
        if (self.scene.paused) {
            self.simulateStep() catch |err| {
                std.debug.print("Error in simulateStep: {t}\n", .{err});
            };
        }
    }

    if (c.IsMouseButtonDown(c.MOUSE_LEFT_BUTTON)) {
        const mouse_position = c.GetMousePosition();
        const x = mouse_position.x / self.coordinate_scale;
        const y = (self.screen_height - mouse_position.y) / self.coordinate_scale;

        if (!self.mouse_down) {
            self.setObstacle(x, y, true);
            self.mouse_down = true;
            self.scene.paused = false;
        } else {
            self.setObstacle(x, y, false);
        }

        self.last_mouse_position = mouse_position;
    }

    if (c.IsMouseButtonReleased(c.MOUSE_LEFT_BUTTON)) {
        self.mouse_down = false;
        self.scene.obstacle_velocity_x = 0.0;
        self.scene.obstacle_velocity_y = 0.0;
    }
}

fn renderFrame(self: *AppState) void {
    c.BeginTextureMode(self.render_target);
    c.ClearBackground(c.BLACK);

    c.BeginMode2D(self.camera);
    self.drawScene();
    c.EndMode2D();
    c.EndTextureMode();

    c.BeginDrawing();
    c.ClearBackground(c.BLACK);

    const source = c.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.render_target.texture.width), .height = -@as(f32, @floatFromInt(self.render_target.texture.height)) };
    const dest = c.Rectangle{ .x = 0, .y = 0, .width = self.screen_width, .height = self.screen_height };
    const origin = c.Vector2{ .x = 0, .y = 0 };
    c.DrawTexturePro(self.render_target.texture, source, dest, origin, 0.0, c.WHITE);

    if (self.scene.paused) {
        c.DrawText("PAUSED", 10, 10, 20, c.YELLOW);
        c.DrawText("Press P to Resume | Press M to Step Frame", 10, 35, 16, c.LIGHTGRAY);
    } else {
        c.DrawText("Running", 10, 10, 20, c.GREEN);
        c.DrawText("Press P to Pause", 10, 35, 16, c.LIGHTGRAY);
    }

    c.DrawFPS(@intFromFloat(self.screen_width - 100.0), 10);

    c.EndDrawing();
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

    const fluid_ptr = try self.allocator.create(FlipFluid);
    fluid_ptr.* = try FlipFluid.init(self.allocator, density, tank_width, tank_height, cell_size, particle_radius, max_particles);
    self.scene.flip_fluid = fluid_ptr;

    self.scene.renderer = try ParticleRenderer.init(self.allocator, max_particles);

    // Manually resize array lists
    if (self.scene.flip_fluid) |f| {
        try f.particles.pos_x.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.pos_y.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.vel_x.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.vel_y.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.color_r.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.color_g.resize(self.allocator, num_particles_x * num_particles_y);
        try f.particles.color_b.resize(self.allocator, num_particles_x * num_particles_y);
        f.particles.count = num_particles_x * num_particles_y;
    }

    var particle_index: usize = 0;
    for (0..num_particles_x) |i| {
        for (0..num_particles_y) |j| {
            const x_offset = if (j % 2 == 0) 0.0 else particle_radius;
            const float_x = @as(f32, @floatFromInt(i));
            const float_y = @as(f32, @floatFromInt(j));

            if (self.scene.flip_fluid) |f| {
                f.particles.pos_x.items[particle_index] = cell_size + particle_radius + delta_x * float_x + x_offset;
                f.particles.pos_y.items[particle_index] = cell_size + particle_radius + delta_y * float_y;
            }

            particle_index += 1;
        }
    }

    if (self.scene.flip_fluid) |f| {
        const grid_height: usize = @intCast(f.grid_size_y());
        const grid_width: usize = @intCast(f.grid_size_x());

        for (0..grid_width) |i| {
            for (0..grid_height) |j| {
                const solid_value: f32 = if (i == 0 or i == grid_width - 1 or j == 0) 0.0 else 1.0;
                f.pressure.s.items[i * grid_height + j] = solid_value;
            }
        }
    }

    self.setObstacle(width / 2.0, height / 2.0, true);
}

fn setObstacle(self: *AppState, x: f32, y: f32, reset: bool) void {
    if (!reset) {
        self.scene.obstacle_velocity_x = (x - self.scene.obstacle_x) / self.scene.dt;
        self.scene.obstacle_velocity_y = (y - self.scene.obstacle_y) / self.scene.dt;
    }
    self.scene.obstacle_x = x;
    self.scene.obstacle_y = y;
    self.scene.show_obstacle = true;
}

fn simulateStep(self: *AppState) !void {
    if (self.scene.flip_fluid) |f| {
        try f.simulate(self.scene.dt, self.scene.gravity, self.scene.flip_ratio, self.scene.num_pressure_iters, self.scene.num_particle_iters, self.scene.over_relaxation, self.scene.obstacle_x, self.scene.obstacle_y, self.scene.obstacle_radius, self.scene.obstacle_velocity_x, self.scene.obstacle_velocity_y);
        self.scene.frame_number += 1;
    }
}

fn drawScene(self: *AppState) void {
    if (self.scene.show_particles) {
        c.rlDrawRenderBatchActive();
        c.rlSetBlendMode(c.RL_BLEND_ADDITIVE);
        if (self.scene.flip_fluid) |f| {
            self.scene.renderer.draw(f, self.coordinate_scale, self.screen_height);
        }
        c.rlSetBlendMode(c.RL_BLEND_ALPHA);
    }

    if (self.scene.show_obstacle) {
        const screen_x = self.scene.obstacle_x * self.coordinate_scale;
        const screen_y = self.screen_height - self.scene.obstacle_y * self.coordinate_scale;
        const screen_radius = self.scene.obstacle_radius * self.coordinate_scale;

        c.DrawCircle(@intFromFloat(screen_x), @intFromFloat(screen_y), screen_radius, c.RED);
    }
}

pub fn run(self: *AppState) !void {
    if (builtin.os.tag == .emscripten) {
        // Emscripten specific main loop logic
        const emsdk = @cImport(@cInclude("emscripten/emscripten.h"));

        const loop = struct {
            fn runLoop(arg: ?*anyopaque) callconv(.c) void {
                const app: *AppState = @ptrCast(@alignCast(arg));
                app.update() catch |err| {
                    std.debug.print("Error in update: {}\n", .{err});
                };
            }
        }.runLoop;

        emsdk.emscripten_set_main_loop_arg(loop, self, 0, true);
    } else {
        // Desktop main loop
        while (!c.WindowShouldClose()) {
            try self.update();
        }
    }
}

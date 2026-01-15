const std = @import("std");

const fluid = @import("fluid");
const FlipFluid = fluid.FlipFluid;

const graphics = @import("graphics");
const ParticleRenderer = graphics.ParticleRenderer;

const FluidScene = @This();

gravity: f32 = -9.81,
dt: f32 = 1.0 / 60.0,
flip_ratio: f32 = 0.9,
num_pressure_iters: i32 = 20,
num_particle_iters: i32 = 2,
over_relaxation: f32 = 1.9,

frame_number: i32 = 0,
paused: bool = true,
show_particles: bool = true,

obstacle_x: f32 = 0.0,
obstacle_y: f32 = 0.0,
obstacle_radius: f32 = 0.15,
obstacle_velocity_x: f32 = 0.0,
obstacle_velocity_y: f32 = 0.0,
show_obstacle: bool = true,

flip_fluid: ?*FlipFluid = null,
renderer: ParticleRenderer = undefined,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) FluidScene {
    return FluidScene{
        .allocator = allocator,
    };
}

pub fn deinit(self: *FluidScene) void {
    if (self.flip_fluid) |f| {
        f.deinit();
        self.allocator.destroy(f);
    }
    self.renderer.deinit();
}

const std = @import("std");
const seizer = @import("seizer");
const gl = seizer.gl;
const FlatRenderer = @import("flat_render.zig").FlatRenderer;
const FontRenderer = @import("font_render.zig").FontRenderer;
const Texture = @import("texture.zig").Texture;
const math = seizer.math;
const Vec2f = math.Vec(2, f32);
const vec2f = Vec2f.init;

pub fn main() anyerror!void {
    seizer.run(.{
        .init = init,
        .deinit = deinit,
        .event = event,
        .render = render,
        .update = update,
    });
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rng: std.rand.DefaultPrng = undefined;

const particle = @import("particle.zig");
const PixelData = particle.PixelData;
const ParticleSim = particle.ParticleSim;

const Context = struct {
    allocator: *std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    flat: FlatRenderer,
    simTexture: Texture,
    simRender: PixelData,
    simData: ParticleSim,
    is_mouse_down: bool,
    place_x: u32,
    place_y: u32,
};

var ctx: Context = undefined;

fn init() !void {
    var seed: u64 = undefined;
    seizer.randomBytes(std.mem.asBytes(&seed));
    rng = std.rand.DefaultPrng.init(seed);
    var allocator = &gpa.allocator;
    var screen_size = seizer.getScreenSize().intCast(u32);
    var simRender = try PixelData.init(allocator, screen_size.x, screen_size.y);
    var simData = try ParticleSim.init(allocator, screen_size.x, screen_size.y);

    var i: usize = 0;
    while (i < simRender.data.len) : (i += 1) {
        simRender.data[i].r = 0xff;
        simRender.data[i].g = 0x00;
        simRender.data[i].b = 0x00;
        simRender.data[i].a = 0xff;
    }

    // std.log.info("{}", .{simRender});

    ctx = .{
        .allocator = allocator,
        .rng = rng,
        .flat = try FlatRenderer.init(ctx.allocator, seizer.getScreenSize().intToFloat(f32)),
        .simTexture = try Texture.initFromMemory(simRender.as_bytes(), screen_size.x, screen_size.y),
        .simRender = simRender,
        .simData = simData,
        .is_mouse_down = false,
        .place_x = 0,
        .place_y = 0,
    };
}

fn deinit() void {
    ctx.simRender.deinit();
    ctx.simData.deinit();
    ctx.flat.deinit();
    _ = gpa.deinit();
}

pub fn event(evt: seizer.event.Event) !void {
    switch (evt) {
        .Quit => seizer.quit(),
        .MouseMotion => |e| {
            if (ctx.is_mouse_down) {
                const sim_size = vec2f(@intToFloat(f32, ctx.simData.width), @intToFloat(f32, ctx.simData.height));
                const scale = sim_size.divv(seizer.getScreenSize().intToFloat(f32));
                const adjusted = e.pos.intToFloat(f32).mulv(scale).floatToInt(u32);
                ctx.place_x = adjusted.x;
                ctx.place_y = adjusted.y;
                // ctx.simData.set(x, y, .water);
            }
        },
        .MouseButtonDown => |e| {
            switch(e.button) {
                .Left => ctx.is_mouse_down = true,
                else => {},
            }
            const sim_size = vec2f(@intToFloat(f32, ctx.simData.width), @intToFloat(f32, ctx.simData.height));
            const scale = sim_size.divv(seizer.getScreenSize().intToFloat(f32));
            const adjusted = e.pos.intToFloat(f32).mulv(scale).floatToInt(u32);
            ctx.place_x = adjusted.x;
            ctx.place_y = adjusted.y;
        },
        .MouseButtonUp => |e| {
            switch(e.button) {
                .Left => ctx.is_mouse_down = false,
                else => {},
            }
            const sim_size = vec2f(@intToFloat(f32, ctx.simData.width), @intToFloat(f32, ctx.simData.height));
            const scale = sim_size.divv(seizer.getScreenSize().intToFloat(f32));
            const adjusted = e.pos.intToFloat(f32).mulv(scale).floatToInt(u32);
            ctx.place_x = adjusted.x;
            ctx.place_y = adjusted.y;
        },
        else => {},
    }
}

fn render(alpha: f64) !void {
    const screen_size = seizer.getScreenSize();
    const screen_size_f = screen_size.intToFloat(f32);

    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.viewport(0, 0, screen_size.x, screen_size.y);

    ctx.simData.render(ctx.simRender.data);
    ctx.simTexture.update(ctx.simRender.as_bytes());

    ctx.flat.setSize(screen_size_f);

    ctx.flat.drawTexture(ctx.simTexture, vec2f(0,0), screen_size_f);

    ctx.flat.flush();
}

fn update(current_time: f64, delta: f64) !void {
    ctx.simData.set(100, 10, .sand);
    ctx.simData.set(300, 10, .water);
    if (ctx.is_mouse_down) {
        var x = ctx.place_x - 10;
        while (x < ctx.place_x + 10) : (x += 1) {
            var y = ctx.place_y - 10;
            while (y < ctx.place_y + 10) : (y += 1){
                ctx.simData.set(x, y, .water);
            }
        }
    }
    ctx.simData.update();
}

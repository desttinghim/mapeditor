const std = @import("std");
const seizer = @import("seizer");
const gl = seizer.gl;
const FlatRenderer = @import("flat_render.zig").FlatRenderer;
const FontRenderer = @import("font_render.zig").FontRenderer;
const Texture = @import("texture.zig").Texture;
const RGBA = @import("texture.zig").RGBA;
const PixelData = @import("texture.zig").PixelData;
const math = seizer.math;
const Vec2f = math.Vec(2, f32);
const vec2f = Vec2f.init;
const Vec2i = math.Vec(2, i32);
const vec2i = Vec2i.init;

pub fn main() anyerror!void {
    seizer.run(.{
        .init = init,
        .deinit = deinit,
        .event = event,
        .render = render,
        .update = update,
    });
}

const Context = struct {
    allocator: *std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    flat: FlatRenderer,

    tileTex: Texture,
    tileBMP: PixelData,
    isMouseDown: bool = false,
    prevPos: Vec2i = vec2i(0, 0),
    mousePos: Vec2i = vec2i(0, 0),
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rng: std.rand.DefaultPrng = undefined;
var ctx: Context = undefined;

const tileMapSize = math.Vec(2, u32).init(1024, 1024);

fn init() !void {
    var seed: u64 = undefined;
    seizer.randomBytes(std.mem.asBytes(&seed));
    rng = std.rand.DefaultPrng.init(seed);
    var allocator = &gpa.allocator;
    var screen_size = seizer.getScreenSize().intCast(u32);

    var pixel_data = try PixelData.init(allocator, tileMapSize.x, tileMapSize.y);

    for (pixel_data.data) |*pixel, i| {
        pixel.* = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
    }

    ctx = .{
        .allocator = allocator,
        .rng = rng,
        .flat = try FlatRenderer.init(ctx.allocator, seizer.getScreenSize().intToFloat(f32)),
        .tileTex = try Texture.initFromMemory(pixel_data.asBytes(), tileMapSize.x, tileMapSize.y),
        .tileBMP = pixel_data,
    };
}

fn deinit() void {
    ctx.tileBMP.deinit();
    ctx.flat.deinit();
    _ = gpa.deinit();
}

pub fn event(evt: seizer.event.Event) !void {
    switch (evt) {
        .Quit => seizer.quit(),
        .KeyDown => |e| switch (e.key) {
            else => {},
        },
        .MouseMotion => |e| {
            if (ctx.isMouseDown) {
                ctx.mousePos = e.pos;
            }
        },
        .MouseButtonDown => |e| {
            ctx.isMouseDown = true;
            ctx.mousePos = e.pos;
            ctx.prevPos = e.pos;
        },
        .MouseButtonUp => |e| {
            ctx.isMouseDown = false;
            ctx.mousePos = e.pos;
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

    ctx.flat.setSize(screen_size_f);

    ctx.flat.drawTexture(ctx.tileTex, vec2f(0, 0), tileMapSize.intToFloat(f32));

    ctx.flat.flush();
}

fn update(current_time: f64, delta: f64) !void {
    if (ctx.isMouseDown) {
        const lpos = ctx.prevPos.intCast(u32);
        const pos = ctx.mousePos.intCast(u32);
        const i = @intCast(usize, ctx.mousePos.x + (ctx.mousePos.y * tileMapSize.x));
        const color = .{ .r = 0xFF, .g = 0x00, .b = 0x00, .a = 0xFF };
        ctx.tileBMP.drawLine(lpos.x, lpos.y, pos.x, pos.y, color);
        ctx.tileTex.updateSubImage(ctx.tileBMP.asBytes(), 0, 0, tileMapSize.x, tileMapSize.y);
        ctx.prevPos = ctx.mousePos;
    }
}

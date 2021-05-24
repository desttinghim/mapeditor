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
const Vec2u = math.Vec(2, u32);
const vec2u = Vec2u.init;
const Allocator = std.mem.Allocator;
const Rect = @import("flat_render.zig").Rect;

pub fn main() anyerror!void {
    seizer.run(.{
        .init = init,
        .deinit = deinit,
        .event = event,
        .render = render,
        .update = update,
    });
}

const TileMap = struct {
    allocator: *Allocator,
    pos: Vec2i, // top left corner of tilemap
    tile_size: Vec2u, // pixel size of tiles
    size: Vec2u, // grid size of map
    texture: Texture, // texture to use for tiles
    items: []u32,

    fn init(allocator: *Allocator, pos: Vec2i, tile_size: Vec2u, size: Vec2u, texture: Texture) !@This() {
        const self = @This(){
            .allocator = allocator,
            .pos = pos,
            .tile_size = tile_size,
            .size = size,
            .texture = texture,
            .items = try allocator.alloc(u32, @intCast(u32, size.x * size.y)),
        };

        for (self.items) |*tile, i| {
            tile.* = 0;
        }

        return self;
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.items);
    }

    fn set(self: @This(), pos: Vec2u, tile: u32) void {
        const index = pos.x + (pos.y * self.size.intCast(u32).x);
        self.items[index] = tile;
    }

    fn get(self: @This(), pos: Vec2u) u32 {
        const index = pos.x + (pos.y * self.size.intCast(u32).x);
        return self.items[index];
    }

    fn subImage(self: @This(), tile: u32) Rect {
        // The values for Rect are in texture coordinates, which range from 0 to 1
        const tilesx = @divTrunc(self.texture.size.x, self.tile_size.x);
        const tilesy = @divTrunc(self.texture.size.y, self.tile_size.y);
        const logicx = tile % tilesx;
        const logicy = @divTrunc(tile, tilesx);
        std.debug.assert(logicy < tilesy);
        var pos = vec2u(logicx * self.tile_size.x, logicy * self.tile_size.y).intToFloat(f32).divv(self.texture.size.intToFloat(f32));
        return .{
            .min = pos,
            .max = pos.addv(self.tile_size.intToFloat(f32).divv(self.texture.size.intToFloat(f32))),
        };
    }
};

const Color = struct {
    const red = RGBA{ .r = 0xFF, .g = 0x00, .b = 0x00, .a = 0xFF };
    const green = RGBA{ .r = 0x00, .g = 0xFF, .b = 0x00, .a = 0xFF };
    const blue = RGBA{ .r = 0x00, .g = 0x00, .b = 0xFF, .a = 0xFF };
    const black = RGBA{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF };
    const white = RGBA{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
};

const Pan = struct {
    mouse: Vec2i,
    map: Vec2i,
};

const Draw = struct {
    prevPos: Vec2i,
    color: RGBA,
};

const Activity = enum {
    idle,
    drawing,
    tiling,
    panning,
};

const Context = struct {
    allocator: *std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    flat: FlatRenderer,

    tileMap: TileMap,
    tileBMP: PixelData,
    mousePos: Vec2i = vec2i(0, 0),
    activity: Activity,
    drawing: Draw,
    panning: Pan,
    tiling: u32,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rng: std.rand.DefaultPrng = undefined;
var ctx: Context = undefined;

fn init() !void {
    var seed: u64 = undefined;
    seizer.randomBytes(std.mem.asBytes(&seed));
    rng = std.rand.DefaultPrng.init(seed);
    var allocator = &gpa.allocator;
    var screen_size = seizer.getScreenSize().intCast(u32);

    const tileTexSize = vec2u(1024, 1024);
    var pixel_data = try PixelData.init(allocator, tileTexSize.x, tileTexSize.y);

    for (pixel_data.data) |*pixel, i| {
        pixel.* = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
    }

    var texture = try Texture.initFromMemory(pixel_data.asBytes(), tileTexSize.x, tileTexSize.y);

    ctx = .{
        .allocator = allocator,
        .rng = rng,
        .flat = try FlatRenderer.init(ctx.allocator, seizer.getScreenSize().intToFloat(f32)),
        .tileMap = try TileMap.init(ctx.allocator, vec2i(0, 0), vec2u(32, 32), vec2u(20, 20), texture),
        .tileBMP = pixel_data,
        .activity = .idle,
        .drawing = .{ .prevPos = vec2i(0, 0), .color = Color.black },
        .panning = .{ .mouse = vec2i(0, 0), .map = vec2i(0, 0) },
        .tiling = 0,
    };
}

fn deinit() void {
    ctx.tileMap.deinit();
    ctx.tileBMP.deinit();
    ctx.flat.deinit();
    _ = gpa.deinit();
}

pub fn event(evt: seizer.event.Event) !void {
    switch (evt) {
        .Quit => seizer.quit(),
        .KeyDown => |e| {
            switch (e.key) {
                ._1 => ctx.drawing.color = Color.white,
                ._2 => ctx.drawing.color = Color.black,
                ._3 => ctx.drawing.color = Color.red,
                ._4 => ctx.drawing.color = Color.green,
                ._5 => ctx.drawing.color = Color.blue,
                else => {},
            }
        },
        .MouseWheel => |e| {
            if (e.y > 0) {
                ctx.tiling += 1;
            }
            if (e.y < 0) {
                if (ctx.tiling > 0) {
                    ctx.tiling -= 1;
                }
            }
        },
        .MouseMotion => |e| {
            ctx.mousePos = e.pos;
        },
        .MouseButtonDown => |e| {
            ctx.mousePos = e.pos;
            switch (ctx.activity) {
                .idle => {
                    switch (e.button) {
                        .Left => {
                            ctx.drawing = .{ .prevPos = e.pos, .color = Color.black };
                            ctx.activity = .drawing;
                        },
                        .Middle => {
                            ctx.panning = .{ .mouse = e.pos, .map = ctx.tileMap.pos };
                            ctx.activity = .panning;
                        },
                        .Right => {
                            ctx.activity = .tiling;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        },
        .MouseButtonUp => |e| {
            ctx.mousePos = e.pos;
            ctx.activity = .idle;
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

    var x: u32 = 0;
    while (x < ctx.tileMap.size.x) : (x += 1) {
        var y: u32 = 0;
        while (y < ctx.tileMap.size.y) : (y += 1) {
            var tile = ctx.tileMap.get(vec2u(x, y));
            var pos = ctx.tileMap.pos.intToFloat(f32).addv(ctx.tileMap.tile_size.mulv(vec2u(x, y)).intToFloat(f32));
            var rect = ctx.tileMap.subImage(tile);
            ctx.flat.drawTextureExt(ctx.tileMap.texture, pos, .{
                .size = ctx.tileMap.tile_size.intToFloat(f32),
                .rect = rect,
            });
        }
    }

    ctx.flat.flush();
}

fn update(current_time: f64, delta: f64) !void {
    const activity = ctx.activity;
    switch (activity) {
        .drawing => {
            const lpos = ctx.drawing.prevPos.intCast(u32);
            const pos = ctx.mousePos.intCast(u32);
            const color = ctx.drawing.color;
            ctx.tileBMP.drawLine(lpos.x, lpos.y, pos.x, pos.y, color);
            ctx.tileMap.texture.updateSubImage(ctx.tileBMP.asBytes(), 0, 0, ctx.tileMap.texture.size.x, ctx.tileMap.texture.size.y);
            ctx.drawing.prevPos = ctx.mousePos;
        },
        .tiling => {
            const tile_size = ctx.tileMap.tile_size.intCast(i32);
            const pos = vec2i(@divTrunc(ctx.mousePos.x, tile_size.x), @divTrunc(ctx.mousePos.y, tile_size.y)).intCast(u32);
            ctx.tileMap.set(pos, ctx.tiling);
        },
        .panning => {
            const mousePos = ctx.panning.mouse;
            const mapPos = ctx.panning.map;
            const diff = mousePos.subv(ctx.mousePos);
            ctx.tileMap.pos = mapPos.subv(diff);
        },
        .idle => {},
    }
}

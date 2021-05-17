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
        .render = render,
        .update = update,
    });
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rng: std.rand.DefaultPrng = undefined;

const Context = struct {
    allocator: *std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    flat: FlatRenderer,
    simTexture: Texture,
    simRender: PixelData,
    simData: ParticleSim,
};

const RGBA = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const PixelData = struct {
    allocator: *std.mem.Allocator,
    data: []RGBA,

    fn init(allocator: *std.mem.Allocator, width: u32, height: u32) !@This() {
        var self: @This() = undefined;
        var pixels = @intCast(usize, width * height);
        self.data = try allocator.alloc(RGBA, pixels);
        self.allocator = allocator;
        return self;
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    fn as_bytes(self: @This()) []u8 {
        var byte_ptr = @ptrCast([*]u8, self.data);
        var byte_slice = byte_ptr[0..self.data.len * @sizeOf(RGBA)];
        return byte_slice;
    }
};

const SimType = enum {
    air,
    sand,
    water,
};

const Particle = struct {
    simType: SimType,
    lifetime: u32,
    has_updated: u32,
};

const ParticleSim = struct {
    data: []Particle,
    allocator: *std.mem.Allocator,
    width: u32,
    height: u32,

    fn init(allocator: *std.mem.Allocator, width: u32, height: u32) !@This() {
        var data = try allocator.alloc(Particle, width * height);
        for (data) |*datum, i| {
            datum.* = .{.simType = .air, .lifetime = 0, .has_updated = 0};
        }
        return @This(){
            .data = data,
            .allocator = allocator,
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    fn set(self: @This(), x: u32, y: u32, simType: SimType) void {
        var i = self.get_i(x, y);
        self.data[i].simType = simType;
    }

    fn update(self: @This()) void {
        var y: usize = self.height - 2;
        while (y > 1) : (y -= 1) {
            var x: usize = 1;
            while (x < self.width - 1) : (x += 1) {
                var i = self.get_i(x, y);
                switch(self.data[i].simType) {
                    .air  => {},
                    .sand => {
                        var down = self.get_i(x, y + 1);
                        var downleft = self.get_i(x - 1, y + 1);
                        var downright = self.get_i(x + 1, y + 1);

                        if (self.data[down].simType == .air) {
                            var t = self.data[down];
                            self.data[down] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downleft].simType == .air) {
                            var t = self.data[downleft];
                            self.data[downleft] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downright].simType == .air) {
                            var t = self.data[downright];
                            self.data[downright] = self.data[i];
                            self.data[i] = t;
                        }
                    },
                    .water => {
                        var down = self.get_i(x, y + 1);
                        var left = self.get_i(x - 1, y);
                        var right = self.get_i(x + 1, y);
                        var downleft = self.get_i(x - 1, y + 1);
                        var downright = self.get_i(x + 1, y + 1);

                        if (self.data[down].simType == .air) {
                            var t = self.data[down];
                            self.data[down] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downleft].simType == .air) {
                            var t = self.data[downleft];
                            self.data[downleft] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downright].simType == .air) {
                            var t = self.data[downright];
                            self.data[downright] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[left].simType == .air) {
                            var t = self.data[left];
                            self.data[left] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[right].simType == .air) {
                            var t = self.data[right];
                            self.data[right] = self.data[i];
                            self.data[i] = t;
                        }
                    },
                }
            }
        }
    }

    /// Render sim into tex
    fn render(self: @This(), tex: []RGBA) void {
        var i: usize = 0;
        while(i < tex.len) : (i += 1) {
            var color: RGBA = switch(self.data[i].simType) {
                .air => .{.r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00},
                .sand => .{.r = 0xc2, .g = 0xb2, .b = 0x80, .a = 0xff},
                .water => .{.r = 0xc5, .g = 0xd8, .b = 0xe5, .a = 0xff},
            };
            tex[i] = color;
        }
    }

    fn get_i(self: @This(), x: usize, y: usize) usize {
        return x + y * self.width;
    }
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
    };
}

fn deinit() void {
    ctx.simRender.deinit();
    ctx.simData.deinit();
    ctx.flat.deinit();
    _ = gpa.deinit();
}

fn render(alpha: f64) !void {
    const screen_size = seizer.getScreenSize();
    const screen_size_f = screen_size.intToFloat(f32);

    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.viewport(0, 0, screen_size.x, screen_size.y);

    var i: usize = 0;
    while (i < ctx.simRender.data.len) : (i += 1) {
        ctx.simRender.data[i].r = 0x00;
        ctx.simRender.data[i].g = 0x00;
        ctx.simRender.data[i].b = 0xff;
        ctx.simRender.data[i].a = 0xff;
    }

    ctx.simData.render(ctx.simRender.data);
    ctx.simTexture.update(ctx.simRender.as_bytes());

    ctx.flat.setSize(screen_size_f);

    ctx.flat.drawTexture(ctx.simTexture, vec2f(0,0), screen_size_f);

    ctx.flat.flush();
}

fn update(current_time: f64, delta: f64) !void {
    ctx.simData.set(100, 10, .sand);
    ctx.simData.set(300, 10, .water);
    ctx.simData.update();
}

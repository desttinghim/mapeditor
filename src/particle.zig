const std = @import("std");
const seizer = @import("seizer");

pub const RGBA = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const PixelData = struct {
    allocator: *std.mem.Allocator,
    data: []RGBA,

    pub fn init(allocator: *std.mem.Allocator, width: u32, height: u32) !@This() {
        var self: @This() = undefined;
        var pixels = @intCast(usize, width * height);
        self.data = try allocator.alloc(RGBA, pixels);
        self.allocator = allocator;
        return self;
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    pub fn as_bytes(self: @This()) []u8 {
        var byte_ptr = @ptrCast([*]u8, self.data);
        var byte_slice = byte_ptr[0..self.data.len * @sizeOf(RGBA)];
        return byte_slice;
    }
};

pub const SimType = enum {
    air,
    sand,
    water,

    fn is_gas(this: @This()) bool {
        return switch (this) {
            .air => true,
            .sand => false,
            .water => false,
        };
    }

    fn is_liquid(this: @This()) bool {
        return switch (this) {
            .air => false,
            .sand => false,
            .water => true,
        };
    }

    fn is_solid(this: @This()) bool {
        return switch (this) {
            .air => false,
            .sand => true,
            .water => false,
        };
    }
};

pub const Particle = struct {
    simType: SimType,
    lifetime: u32,
    has_updated: u64,

    fn has_not_updated(self: @This(), tick: u64) bool {
        return self.lifetime < tick;
    }
};

const ReversibleIterator = struct {
    index: usize,
    min: usize,
    max: usize,
    reverse: bool,

    fn init(reverse: bool, min: usize, max: usize) @This() {
        return @This() {
            .index = if (reverse) max else min,
            .max = max,
            .min = min,
            .reverse = reverse,
        };
    }

    fn next(self: *@This()) ?usize {
        const i = self.index;
        if (i >= self.max and !self.reverse) return null;
        if (i <= self.min and self.reverse) return null;
        if (self.reverse) self.index -= 1 else self.index += 1;
        return i;
    }
};

pub const ParticleSim = struct {
    data: []Particle,
    allocator: *std.mem.Allocator,
    rng: *std.rand.DefaultPrng,
    width: u32,
    height: u32,
    tick: u64,

    pub fn init(allocator: *std.mem.Allocator, rng: *std.rand.DefaultPrng, width: u32, height: u32) !@This() {
        var data = try allocator.alloc(Particle, width * height);
        for (data) |*datum, i| {
            datum.* = .{.simType = .air, .lifetime = 0, .has_updated = 0};
        }
        return @This(){
            .data = data,
            .allocator = allocator,
            .rng = rng,
            .width = width,
            .height = height,
            .tick = 0,
        };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    pub fn set(self: *@This(), x: u32, y: u32, simType: SimType) void {
        var i = self.get_i(x, y);
        self.data[i].simType = simType;
    }

    pub fn update(self: *@This()) void {
        const preferLeft = self.rng.random.boolean();
        self.tick += 1;
        var y: usize = self.height - 2;
        while (y > 1) : (y -= 1) {
            var x_iter = ReversibleIterator.init(preferLeft, 2, self.width - 2);
            while (x_iter.next()) |x| {
                const i = self.get_i(x, y);
                const down_i = self.get_i(x, y + 1);
                const left_i = if (preferLeft) self.get_i(x - 1, y) else self.get_i(x + 1, y);
                const right_i = if (preferLeft) self.get_i(x + 1, y) else self.get_i(x - 1, y);
                const downleft_i = if (preferLeft) self.get_i(x - 1, y + 1) else self.get_i(x + 1, y +  1);
                const downright_i = if (preferLeft) self.get_i(x + 1, y + 1) else self.get_i(x - 1, y +  1);
                switch(self.data[i].simType) {
                    .air  => {},
                    .sand => {
                        const down = self.data[down_i];
                        const downleft = self.data[downleft_i];
                        const downright = self.data[downright_i];
                        if (!down.simType.is_solid() and down.has_not_updated(self.tick)) {
                            self.swap(i, down_i);
                        } else if (!downleft.simType.is_solid() and downleft.has_not_updated(self.tick)) {
                            self.swap(i, downleft_i);
                        } else if (!downright.simType.is_solid() and downright.has_not_updated(self.tick)) {
                            self.swap(i, downright_i);
                        }
                    },
                    .water => {
                        const down = self.data[down_i];
                        const downleft = self.data[downleft_i];
                        const downright = self.data[downright_i];
                        const left = self.data[left_i];
                        const right = self.data[right_i];
                        if (down.simType.is_gas() and down.has_not_updated(self.tick)) {
                            self.swap(i, down_i);
                        } else if (downleft.simType.is_gas() and downleft.has_not_updated(self.tick)) {
                            self.swap(i, downleft_i);
                        } else if (downright.simType.is_gas() and downright.has_not_updated(self.tick)) {
                            self.swap(i, downright_i);
                        } else if (left.simType.is_gas() and left.has_not_updated(self.tick)) {
                            self.swap(i, left_i);
                        } else if (right.simType.is_gas() and right.has_not_updated(self.tick)) {
                            self.swap(i, right_i);
                        }
                    },
                }
            }
        }
    }

    fn swap(self: *@This(), index1: usize, index2: usize) void {
        const t = self.data[index1];
        self.data[index1] = self.data[index2];
        self.data[index2] = t;
        self.data[index1].has_updated = self.tick;
        self.data[index2].has_updated = self.tick;
    }

    /// Render sim into tex
    pub fn render(self: @This(), tex: []RGBA) void {
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
        std.debug.assert(x <= self.width);
        std.debug.assert(y <= self.height);
        return x + y * self.width;
    }
};

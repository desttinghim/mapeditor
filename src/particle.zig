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
    has_updated: u32,
};

pub const ParticleSim = struct {
    data: []Particle,
    allocator: *std.mem.Allocator,
    width: u32,
    height: u32,
    tick: u64,

    pub fn init(allocator: *std.mem.Allocator, width: u32, height: u32) !@This() {
        var data = try allocator.alloc(Particle, width * height);
        for (data) |*datum, i| {
            datum.* = .{.simType = .air, .lifetime = 0, .has_updated = 0};
        }
        return @This(){
            .data = data,
            .allocator = allocator,
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
        const prefer = self.tick % 2;
        self.tick += 1;
        var y: usize = self.height - 2;
        while (y > 1) : (y -= 1) {
            var x: usize = 1;
            while (x < self.width - 1) : (x += 1) {
                const i = self.get_i(x, y);
                const down = self.get_i(x, y + 1);
                const left = if (prefer == 0) self.get_i(x - 1, y) else self.get_i(x + 1, y);
                const right = if (prefer == 0) self.get_i(x + 1, y) else self.get_i(x - 1, y);
                const downleft = if (prefer == 0) self.get_i(x - 1, y + 1) else self.get_i(x + 1, y +  1);
                const downright = if (prefer == 0) self.get_i(x + 1, y + 1) else self.get_i(x - 1, y +  1);
                switch(self.data[i].simType) {
                    .air  => {},
                    .sand => {
                        if (!self.data[down].simType.is_solid()) {
                            var t = self.data[down];
                            self.data[down] = self.data[i];
                            self.data[i] = t;
                        } else if (!self.data[downleft].simType.is_solid()) {
                            var t = self.data[downleft];
                            self.data[downleft] = self.data[i];
                            self.data[i] = t;
                        } else if (!self.data[downright].simType.is_solid()) {
                            var t = self.data[downright];
                            self.data[downright] = self.data[i];
                            self.data[i] = t;
                        }
                    },
                    .water => {
                        if (self.data[down].simType.is_gas()) {
                            var t = self.data[down];
                            self.data[down] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downleft].simType.is_gas()) {
                            var t = self.data[downleft];
                            self.data[downleft] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[downright].simType.is_gas()) {
                            var t = self.data[downright];
                            self.data[downright] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[left].simType.is_gas()) {
                            var t = self.data[left];
                            self.data[left] = self.data[i];
                            self.data[i] = t;
                        } else if (self.data[right].simType.is_gas()) {
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
        return x + y * self.width;
    }
};

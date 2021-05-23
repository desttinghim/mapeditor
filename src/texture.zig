const std = @import("std");
const seizer = @import("seizer");
const zigimg = @import("zigimg");
const gl = seizer.gl;
const math = seizer.math;

pub const Texture = struct {
    glTexture: gl.GLuint,
    size: math.Vec(2, u32),

    pub fn initFromFile(alloc: *std.mem.Allocator, filePath: []const u8) !@This() {
        const image_contents = try seizer.fetch(alloc, filePath, 50000);
        defer alloc.free(image_contents);

        const load_res = try zigimg.Image.fromMemory(alloc, image_contents);
        defer load_res.deinit();
        if (load_res.pixels == null) return error.ImageLoadFailed;

        var pixelData = try alloc.alloc(u8, load_res.width * load_res.height * 4);
        defer alloc.free(pixelData);

        // TODO: skip converting to RGBA and let OpenGL handle it by telling it what format it is in
        var pixelsIterator = zigimg.color.ColorStorageIterator.init(&load_res.pixels.?);

        var i: usize = 0;
        while (pixelsIterator.next()) |color| : (i += 1) {
            const integer_color = color.toIntegerColor8();
            pixelData[i * 4 + 0] = integer_color.R;
            pixelData[i * 4 + 1] = integer_color.G;
            pixelData[i * 4 + 2] = integer_color.B;
            pixelData[i * 4 + 3] = integer_color.A;
        }

        return initFromMemory(pixelData, load_res.width, load_res.height);
    }

    // Expects a byte stream
    pub fn initFromMemory(pixelData: []u8, width: u32, height: u32) !@This() {
        var tex: gl.GLuint = 0;
        gl.genTextures(1, &tex);
        if (tex == 0)
            return error.OpenGLFailure;
        gl.bindTexture(gl.TEXTURE_2D, tex);
        defer gl.bindTexture(gl.TEXTURE_2D, 0);
        const c_width = @intCast(c_int, width);
        const c_height = @intCast(c_int, height);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, c_width, c_height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

        return @This(){
            .glTexture = tex,
            .size = math.Vec(2, u32).init(width, height),
        };
    }

    pub fn updateSubImage(self: @This(), pixelData: []u8, xoffset: u32, yoffset: u32, width: u32, height: u32) void {
        const c_xoffset = @intCast(c_int, xoffset);
        const c_yoffset = @intCast(c_int, yoffset);
        const c_width = @intCast(c_int, width);
        const c_height = @intCast(c_int, height);
        gl.bindTexture(gl.TEXTURE_2D, self.glTexture);
        defer gl.bindTexture(gl.TEXTURE_2D, 0);
        gl.texSubImage2D(gl.TEXTURE_2D, 0, c_xoffset, c_yoffset, c_width, c_height, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
    }

    /// Update image assuming the new pixel data has the same dimensions
    pub fn update(self: @This(), pixelData: []u8) void {
        self.updateSubImage(pixelData, 0, 0, self.size.x, self.size.y);
    }
};

pub const RGBA = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

/// CPU Pixel buffer, can be modified
pub const PixelData = struct {
    allocator: *std.mem.Allocator,
    data: []RGBA,
    width: u32,
    height: u32,

    pub fn init(allocator: *std.mem.Allocator, width: u32, height: u32) !@This() {
        var pixels = @intCast(usize, width * height);
        return @This(){
            .allocator = allocator,
            .data = try allocator.alloc(RGBA, pixels),
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    pub fn asBytes(self: @This()) []u8 {
        var byte_ptr = @ptrCast([*]u8, self.data);
        var byte_slice = byte_ptr[0 .. self.data.len * @sizeOf(RGBA)];
        return byte_slice;
    }

    pub fn drawPixel(self: @This(), x: u32, y: u32, color: RGBA) void {
        const index = x + (y * self.width);
        self.data[index] = color;
    }

    fn _drawPixel(self: @This(), x: i32, y: i32, color: RGBA) void {
        const index = @intCast(u32, x) + (@intCast(u32, y) * self.width);
        self.data[index] = color;
    }

    pub fn drawLine(self: @This(), x0: u32, y0: u32, x1: u32, y1: u32, color: RGBA) void {
        const xmin = @intCast(i32, std.math.min(x0, x1));
        const xmax = @intCast(i32, std.math.max(x0, x1));
        const ymin = @intCast(i32, std.math.min(y0, y1));
        const ymax = @intCast(i32, std.math.max(y0, y1));
        const x0i = @intCast(i32, x0);
        const x1i = @intCast(i32, x1);
        const y0i = @intCast(i32, y0);
        const y1i = @intCast(i32, y1);

        if (ymax - ymin < xmax - xmin) {
            if (x0 > x1) {
                self._drawLineLow(x1i, y1i, x0i, y0i, color);
            } else {
                self._drawLineLow(x0i, y0i, x1i, y1i, color);
            }
        } else {
            if (y0 > y1) {
                self._drawLineHigh(x1i, y1i, x0i, y0i, color);
            } else {
                self._drawLineHigh(x0i, y0i, x1i, y1i, color);
            }
        }
    }

    fn _drawLineLow(self: @This(), xmin: i32, ymin: i32, xmax: i32, ymax: i32, color: RGBA) void {
        var dx = xmax - xmin;
        var dy = ymax - ymin;

        var yi: i32 = 1;
        if (dy < 0) {
            yi = -1;
            dy = -dy;
        }

        var D = 2 * dy - dx;
        var y: i32 = ymin;
        var x: i32 = xmin;
        while (x < xmax) : (x += 1) {
            self._drawPixel(x, y, color);
            if (D > 0) {
                y += yi;
                D += (2 * (dy - dx));
            } else {
                D += 2 * dy;
            }
        }
    }

    fn _drawLineHigh(self: @This(), xmin: i32, ymin: i32, xmax: i32, ymax: i32, color: RGBA) void {
        var dx = xmax - xmin;
        var dy = ymax - ymin;

        var xi: i32 = 1;
        if (dx < 0) {
            xi = -1;
            dx = -dx;
        }

        var D = 2 * dx - dy;
        var y: i32 = ymin;
        var x: i32 = xmin;
        while (y < ymax) : (y += 1) {
            self._drawPixel(x, y, color);
            if (D > 0) {
                x += xi;
                D += (2 * (dx - dy));
            } else {
                D += 2 * dx;
            }
        }
    }
};

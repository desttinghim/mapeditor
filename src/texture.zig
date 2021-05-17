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

        // var tex: gl.GLuint = 0;
        // gl.genTextures(1, &tex);
        // if (tex == 0)
        //     return error.OpenGLFailure;

        // gl.bindTexture(gl.TEXTURE_2D, tex);
        // defer gl.bindTexture(gl.TEXTURE_2D, 0);
        // const width = @intCast(c_int, load_res.width);
        // const height = @intCast(c_int, load_res.height);
        // gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

        // return @This(){
        //     .glTexture = tex,
        //     .size = math.Vec(2, usize).init(load_res.width, load_res.height),
        // };
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

    // pub fn updateFromMemory(self: @This(), pixelData: []u8, width: u32, height: u32) !@This() {
    //     gl.bindTexture(gl.TEXTURE_2D, tex);
    //     defer gl.bindTexture(gl.TEXTURE_2D, 0);
    //     gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
    // }

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

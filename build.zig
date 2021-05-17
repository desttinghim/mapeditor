const std = @import("std");
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("sand", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();

    const sdl_sdk_path_opt = b.option([]const u8, "sdl-sdk", "The path to the SDL2 sdk") orelse null;
    if (sdl_sdk_path_opt) |sdk_path| {
        exe.linkSystemLibraryName("SDL2");
        exe.addIncludeDir(b.fmt("{s}/include", .{sdk_path}));

        const lib_dir = b.fmt("{s}/lib", .{sdk_path});
        exe.addLibPath(lib_dir);
    } else {
        exe.linkSystemLibrary("SDL2");
    }
    pkgs.addAllTo(exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

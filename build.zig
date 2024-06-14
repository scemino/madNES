const std = @import("std");
const builtin = @import("builtin");

pub const SokolBackend = enum {
    auto, // Windows: D3D11, macOS/iOS: Metal, otherwise: GL
    d3d11,
    metal,
    gl,
    gles3,
    wgpu,
};

// helper function to resolve .auto backend based on target platform
pub fn resolveSokolBackend(backend: SokolBackend, target: std.Target) SokolBackend {
    if (backend != .auto) {
        return backend;
    } else if (target.isDarwin()) {
        return .metal;
    } else if (target.os.tag == .windows) {
        return .d3d11;
    } else if (target.isWasm()) {
        return .gles3;
    } else if (target.isAndroid()) {
        return .gles3;
    } else {
        return .gl;
    }
}

pub fn build(b: *std.Build) void {
    const opt_use_gl = b.option(bool, "gl", "Force OpenGL (default: false)") orelse false;
    const opt_use_wgpu = b.option(bool, "wgpu", "Force WebGPU (default: false, web only)") orelse false;
    const sokol_backend: SokolBackend = if (opt_use_gl) .gl else if (opt_use_wgpu) .wgpu else .auto;

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize });

    // create file tree for sokol
    const sokol_wf = b.addNamedWriteFiles("sokol");
    _ = sokol_wf.addCopyDirectory(dep_sokol.path(""), "", .{});
    const sokol_root = sokol_wf.getDirectory();

    // build sokol as C/C++ library
    const lib_sokol = b.addStaticLibrary(.{
        .name = "sokol_lib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_sokol.installHeadersDirectory(dep_sokol.path(""), "", .{
        .include_extensions = &.{".h"},
    });
    lib_sokol.addIncludePath(sokol_root);
    b.installArtifact(lib_sokol);

    // lib compilation depends on file tree
    lib_sokol.step.dependOn(&sokol_wf.step);

    const dep_chips = b.dependency("chips", .{ .target = target, .optimize = optimize });

    // create file tree for chips
    const chips_wf = b.addNamedWriteFiles("chips");
    _ = chips_wf.addCopyDirectory(dep_chips.path(""), "", .{});
    const chips_root = chips_wf.getDirectory();

    // build chips as C/C++ library
    const lib_chips = b.addStaticLibrary(.{
        .name = "chips_lib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_chips.installHeadersDirectory(dep_chips.path(""), "", .{
        .include_extensions = &.{".h"},
    });
    lib_chips.addIncludePath(chips_root);
    b.installArtifact(lib_chips);

    // lib compilation depends on file tree
    lib_chips.step.dependOn(&chips_wf.step);

    const dep_imgui = b.dependency("imgui", .{ .target = target, .optimize = optimize });

    // create file tree for imgui
    const wf = b.addNamedWriteFiles("imgui");
    _ = wf.addCopyDirectory(dep_imgui.path(""), "imgui/imgui", .{});
    const imgui_root = wf.getDirectory();

    const cppflags: []const []const u8 = &.{
        "-std=c++20",
        "-pedantic",
        "-Wall",
        "-W",
        "-Wno-missing-field-initializers",
        "-fno-sanitize=undefined",
    };

    // build imgui as C/C++ library
    const lib_imgui = b.addStaticLibrary(.{
        .name = "imgui_lib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_imgui.addCSourceFiles(.{
        .root = imgui_root,
        .files = &.{
            b.pathJoin(&.{ "imgui", "imgui", "imgui.cpp" }),
            b.pathJoin(&.{ "imgui", "imgui", "imgui_widgets.cpp" }),
            b.pathJoin(&.{ "imgui", "imgui", "imgui_draw.cpp" }),
            b.pathJoin(&.{ "imgui", "imgui", "imgui_tables.cpp" }),
            b.pathJoin(&.{ "imgui", "imgui", "imgui_demo.cpp" }),
        },
        .flags = cppflags,
    });
    lib_imgui.addIncludePath(imgui_root);
    b.installArtifact(lib_imgui);

    // lib compilation depends on file tree
    lib_imgui.step.dependOn(&wf.step);

    // resolve .auto backend into specific backend by platform
    // platform specific compile and link options
    const common = b.addStaticLibrary(.{
        .name = "common",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    //common.step.dependOn(buildShaders(b));
    const backend = resolveSokolBackend(sokol_backend, common.rootModuleTarget());
    const backend_cflags = switch (backend) {
        .d3d11 => "-DSOKOL_D3D11",
        .metal => "-DSOKOL_METAL",
        .gl => "-DSOKOL_GLCORE",
        .gles3 => "-DSOKOL_GLES3",
        .wgpu => "-DSOKOL_WGPU",
        else => @panic("unknown sokol backend"),
    };
    const cflags: []const []const u8 = &.{
        if (common.rootModuleTarget().isDarwin()) "-ObjC" else "",
        "-DIMPL",
        backend_cflags,
        "-std=c11",
    };
    const common_cppflags: []const []const u8 = &.{
        "-std=c++20",
        "-pedantic",
        "-Wall",
        "-W",
        "-Wno-missing-field-initializers",
        "-fno-sanitize=undefined",
        "-DIMPL",
        backend_cflags,
    };
    const common_c_sources = [_][]const u8{
        "common/clock.c",
        "common/fs.c",
        "common/gfx.c",
        "common/keybuf.c",
        "common/prof.c",
        "common/sokol.c",
        "common/clock.c",
    };
    const common_cpp_sources = [_][]const u8{"common/ui.cc"};
    inline for (common_c_sources) |csrc| {
        common.addCSourceFile(.{
            .file = b.path(csrc),
            .flags = cflags,
        });
    }
    inline for (common_cpp_sources) |csrc| {
        common.addCSourceFile(.{
            .file = b.path(csrc),
            .flags = common_cppflags,
        });
    }
    common.addIncludePath(sokol_root);
    common.addIncludePath(dep_imgui.path(""));
    common.addIncludePath(chips_root);
    common.addIncludePath(imgui_root);

    if (common.rootModuleTarget().isDarwin()) {
        const imgui_frameworks = [_][]const u8{
            "Cocoa",
            "Foundation",
            "AudioToolbox",
            "Metal",
            "MetalKit",
            "QuartzCore",
        };
        inline for (imgui_frameworks) |fw| {
            common.linkFramework(fw);
        }
    }

    const exe = b.addExecutable(.{
        .name = "madNES",
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .cwd_relative = "common" });
    exe.addIncludePath(chips_root);
    exe.addIncludePath(dep_imgui.path(""));
    exe.addIncludePath(sokol_root);
    exe.linkLibrary(common);
    exe.linkLibrary(lib_imgui);
    exe.linkLibCpp();
    if (exe.rootModuleTarget().os.tag == .windows) {
        const win_libs = [_][]const u8{
            "ole32",
            "gdi32",
            "D3D11",
        };
        inline for (win_libs) |win_lib| {
            exe.linkSystemLibrary(win_lib);
        }
    }
    exe.addCSourceFiles(.{ .files = &.{"src/nes.c"}, .flags = &.{
        "-std=c99",
        "-DCHIPS_USE_UI",
    } });
    exe.addCSourceFiles(.{ .files = &.{"src/nes-ui-impl.cc"}, .flags = &.{
        "-std=c++20",
        "-Wno-missing-field-initializers",
        "-fno-sanitize=undefined",
        "-DCHIPS_USE_UI",
    } });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

// a separate step to compile shaders, expects the shader compiler in deps/sokol-tools-bin/
fn buildShaders(b: *std.Build) *std.Build.Step {
    const sokol_tools_bin_dir = "deps/sokol-tools-bin/bin/";
    const shaders_dir = "common/";
    const shaders = .{
        "shaders.glsl",
    };
    const optional_shdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };
    if (optional_shdc == null) {
        std.log.warn("unsupported host platform, skipping shader compiler step", .{});
        return;
    }
    const shdc_path = sokol_tools_bin_dir ++ optional_shdc.?;
    var shdc_step = b.step("shaders", "Compile shaders (needs deps/sokol-tools-bin)");
    const slang = "glsl330:metal_macos:hlsl5:glsl300es:wgsl";
    inline for (shaders) |shader| {
        const cmd = b.addSystemCommand(&.{
            shdc_path,
            "-i",
            shaders_dir ++ shader,
            "-o",
            shaders_dir ++ shader ++ ".h",
            "-l",
            slang,
        });
        shdc_step.dependOn(&cmd.step);
    }
    return shdc_step;
}

const std = @import("std");
const manifest = @import("build.zig.zon");

pub const Platform = enum {
    /// Linux, FreeBSD, OpenBSD, NetBSD
    unix,
    /// Google Android
    android,
    /// Microsoft Windows
    win32,
    /// Apple MacOS
    macos,
};

const Backend = enum {
    vulkan,
    opengl,
};

pub fn build(b: *std.Build) !void {
    const backend = b.option(
        Backend,
        "zora_backend",
        "Selects zora's backend.",
    ) orelse .vulkan;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const platform: Platform = switch (target.result.os.tag) {
        .windows => .win32,
        .freebsd, .netbsd, .dragonfly, .openbsd => .unix,
        .linux => if (target.result.abi.isAndroid()) .android else .unix,
        .macos => .macos,
        else => @panic("unknown os"),
    };

    const config = b.addOptions();
    config.addOption(Backend, "backend", backend);
    config.addOption(Platform, "platform", platform);

    config.addOption(
        bool,
        "debug",
        optimize == .Debug or optimize == .ReleaseSafe,
    );

    config.addOption(
        std.SemanticVersion,
        "version",
        try std.SemanticVersion.parse(manifest.version),
    );

    const zora = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,

        .imports = &.{
            .{
                .name = "config",
                .module = config.createModule(),
            },
            .{
                .name = @tagName(backend),
                .module = addTranslateHeaders(
                    b,
                    target,
                    optimize,
                    platform,
                    backend,
                ),
            },
        },

        // On Windows, linking libc is always required.
        .link_libc = target.result.os.tag == .windows,
    });

    const mod_tests = b.addTest(.{ .root_module = zora });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    addExample(b, target, optimize, zora);
}

fn addTranslateHeaders(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    platform: Platform,
    backend: Backend,
) *std.Build.Module {
    const use_gles = b.option(
        bool,
        "zora_opengl_use_gles",
        "Selects OpenGLES 2.0 instead of OpenGL 3.3 Core.",
    ) orelse (platform == .android);

    const translate = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(b.fmt("headers/{s}/{s}.h", .{
            @tagName(backend),
            @tagName(backend),
        })),
    });
    translate.addIncludePath(b.path(b.fmt("headers/{s}", .{
        @tagName(backend),
    })));

    if (use_gles) {
        translate.defineCMacro("OPENGL_USE_GLES", null);
    }

    return translate.createModule();
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zora: *std.Build.Module,
) void {
    const example = b.addExecutable(.{
        .name = "example",
        .use_llvm = true,

        .root_module = b.createModule(.{
            .root_source_file = b.path("example/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zora", .module = zora }},
            .link_libc = true,
        }),
    });

    example.root_module.dwarf_format = .@"64";
    example.root_module.linkSystemLibrary("sdl3", .{ .needed = true });

    const run_step = b.step("example", "Run the example");
    const run_cmd = b.addRunArtifact(example);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    b.installArtifact(example);
}

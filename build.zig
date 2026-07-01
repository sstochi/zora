const std = @import("std");

const BackendType = enum {
    vulkan,
    opengl,
};

pub fn build(b: *std.Build) void {
    const backend = b.option(
        BackendType,
        "zora_backend",
        "Selects zora's backend.",
    ) orelse .vulkan;

    const options = b.addOptions();
    options.addOption(BackendType, "backend", backend);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_headers = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(b.fmt("headers/{s}/{s}.h", .{
            @tagName(backend),
            @tagName(backend),
        })),
    });

    translate_headers.addIncludePath(b.path(b.fmt("headers/{s}", .{
        @tagName(backend),
    })));

    const zora = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,

        .imports = &.{
            .{ .name = "options", .module = options.createModule() },

            .{
                .name = "manifest",
                .module = b.createModule(.{
                    .root_source_file = b.path("build.zig.zon"),
                }),
            },

            .{
                .name = @tagName(backend),
                .module = translate_headers.createModule(),
            },
        },

        // On Windows, linking libc is always required.
        .link_libc = target.result.os.tag == .windows,
    });

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

    b.installArtifact(example);

    const run_step = b.step("example", "Run the example");
    const run_cmd = b.addRunArtifact(example);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = zora,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

const std = @import("std");

const BackendType = enum {
    vulkan,
    opengl,
};

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend = b.option(BackendType, "zora_backend", "Selects zora's backend.") orelse .vulkan;
    const link_libvulkan = b.option(bool, "zora_link_libvulkan", "Whether to link against libvulkan or use dynamic loader.") orelse true;

    options.addOption(BackendType, "backend", backend);
    options.addOption(bool, "link_libvulkan", link_libvulkan);

    const translate_headers = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path(b.fmt("headers/{s}.h", .{@tagName(backend)})),
    });

    const zora = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .imports = &.{
            .{ .name = "manifest", .module = b.createModule(.{ .root_source_file = b.path("build.zig.zon") }) },
            .{ .name = "options", .module = options.createModule() },
            .{ .name = @tagName(backend), .module = translate_headers.createModule() },
        },
    });

    switch (backend) {
        .vulkan => {
            if (link_libvulkan) zora.linkSystemLibrary("vulkan", .{ .needed = true });
        },
        .opengl => {},
    }

    const example = b.addExecutable(.{
        .name = "example",
        .use_llvm = true,

        .root_module = b.createModule(.{
            .root_source_file = b.path("example/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zora", .module = zora }},
        }),
    });

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

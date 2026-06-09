const std = @import("std");
const options = @import("options");
const builtin = @import("builtin");
const manifest = @import("manifest");

pub const Backend = @TypeOf(options.backend);
pub const backend: Backend = options.backend;
pub const debug: bool = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
pub const version: std.SemanticVersion = std.SemanticVersion.parse(manifest.version) catch @compileError("failed to parse version");

pub const Platform = enum {
    // Tier 1
    unix,
    windows,

    // Tier 2
    macos,
    android,
};

pub const platform: Platform = switch (builtin.os.tag) {
    .macos, .freebsd, .netbsd, .dragonfly, .openbsd => .unix,
    .linux => if (builtin.abi.isAndroid()) .android else .unix,
    .windows => .windows,
    else => @panic("unknown os"),
};

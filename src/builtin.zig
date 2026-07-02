const std = @import("std");
const options = @import("options");
const builtin = @import("builtin");
const manifest = @import("manifest");

pub const Backend = @TypeOf(options.backend);
pub const Target = enum {
    // Tier 1

    /// Linux, FreeBSD, OpenBSD, NetBSD
    unix,
    /// Google Android
    android,
    /// Microsoft Windows
    win32,

    // Tier 2

    /// Apple MacOS
    macos,
};

pub const backend: Backend = options.backend;
pub const debug: bool = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

pub const version: std.SemanticVersion = std.SemanticVersion.parse(
    manifest.version,
) catch @compileError("failed to parse version");

pub const target: Target = switch (builtin.os.tag) {
    .windows => .win32,
    .freebsd, .netbsd, .dragonfly, .openbsd => .unix,
    .linux => if (builtin.abi.isAndroid()) .android else .unix,
    .macos => .macos,
    else => @panic("unknown os"),
};

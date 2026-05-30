const std = @import("std");
const build_options = @import("options");
const manifest = @import("manifest");
const builtin = @import("builtin");

const backend = switch (build_options.backend) {
    .vulkan => @import("vulkan/backend.zig"),
    else => @compileError("unknown backend"),
};

pub const BackendType = @TypeOf(build_options.backend);
pub const build_debug: bool = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
pub const build_backend: BackendType = build_options.backend;
pub const build_version: std.SemanticVersion = std.SemanticVersion.parse(manifest.version) catch @compileError("failed to parse version");

pub const Adapter = struct {
    pub const Impl = backend.AdapterImpl;
    pub const CreateError = error{NoViableAdapter};
    pub const TextureCreateError = error{};
    pub const SamplerCreateError = error{};

    pub const VsyncMode = enum { auto, disabled, enabled, adaptive };
    pub const PowerMode = enum { integrated, discrete };

    pub const CreateTextureOptions = Texture.Info;
    pub const CreateSamplerOptions = Sampler.Info;

    pub const Info = struct {
        vram_mb: ?u32,
        device_id: u32,
        vendor_id: u32,
        max_samplers: u32,
        max_texture_1d: u32,
        max_texture_2d: u32,
        max_texture_3d: u32,
        max_texture_array: u32,
        power_mode: PowerMode,
    };

    pub const CreateOptions = struct {
        power_mode: PowerMode = .integrated,
        vsync_mode: VsyncMode = .enabled,
    };

    impl: Impl,

    /// Attempts to find an adapter matching `preferred_options`.
    /// This function should only be called on main thread.
    pub inline fn open(preferred_options: CreateOptions) CreateError!Adapter {
        return .{ .impl = try Impl.open(preferred_options) };
    }

    /// This function should only be called on main thread.
    pub inline fn close(self: *Adapter) void {
        self.impl.close();
    }

    /// This function should only be called on main thread.
    pub inline fn createSampler(self: *Adapter, options: CreateSamplerOptions) SamplerCreateError!Sampler {
        return try self.impl.createSampler(options);
    }

    /// This function should only be called on main thread.
    pub inline fn createTexture(self: *Adapter, options: CreateTextureOptions) TextureCreateError!Texture {
        return try self.impl.createTexture(options);
    }

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Adapter) *const Info {
        return self.impl.info();
    }
};

pub const Texture = struct {
    pub const Usage = packed struct {
        read: bool,
        write: bool,
        output_target: bool = false,
    };

    pub const Info = struct {
        pub const Format = enum { rgba8, bgra8 };

        usage: Usage,
        format: Format,
        width: u32,
        height: u32 = 0,
        depth: u32 = 0,
    };

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Texture) *const Info {
        return self.impl.info();
    }
};

pub const Sampler = struct {
    pub const Info = struct {
        pub const Filter = enum { linear, nearest };
        pub const AddressMode = enum { clamp, repeat };

        addr_mode_u: AddressMode = .clamp,
        addr_mode_v: AddressMode = .clamp,
        addr_mode_w: AddressMode = .clamp,
        min_filter: Filter = .linear,
        mag_filter: Filter = .linear,
        lod_min: f64 = 0.0,
        lod_max: f64 = 1.0,
    };

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Sampler) *const Info {
        return self.impl.info();
    }
};

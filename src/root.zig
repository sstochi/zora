const std = @import("std");
const build_options = @import("options");
const manifest = @import("manifest");
const builtin = @import("builtin");

pub const BackendType = @TypeOf(build_options.backend);
pub const build_debug: bool = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
pub const build_backend: BackendType = build_options.backend;
pub const build_version: std.SemanticVersion = std.SemanticVersion.parse(manifest.version) catch @compileError("failed to parse version");

const backend = switch (build_options.backend) {
    .vulkan => @import("vulkan/backend.zig"),
    else => @compileError("unknown backend"),
};

pub const VsyncMode = enum { auto, disabled, enabled, adaptive };
pub const PowerMode = enum { integrated, discrete };

pub const WindowInfoWin32 = struct {
    hinstance: ?*anyopaque,
    hwnd: ?*anyopaque,
};

pub const WindowInfoUnix = union(enum) {
    xlib: struct { display: ?*anyopaque, window: c_ulong },
    xcb: struct { connection: ?*anyopaque, window: u32 },
    wayland: struct { display: ?*anyopaque, surface: ?*anyopaque },
};

pub const WindowInfo = switch (builtin.target.os.tag) {
    .windows => WindowInfoWin32,
    .linux, .freebsd => WindowInfoUnix,
    else => @compileError("unknown os"),
};

pub const Instance = struct {
    pub const InnerType = backend.Instance;
    pub const CreateInstanceError = error{UnableToCreateInstance};

    inner: InnerType,

    /// This function should only be called on main thread.
    pub inline fn create() !Instance {
        return .{ .inner = try InnerType.create() };
    }

    /// This function should only be called on main thread.
    pub inline fn destroy(self: *Instance) void {
        self.inner.destroy();
    }
};

/// Must never outlive parent `Instance`.
pub const Adapter = struct {
    pub const Impl = backend.Adapter;

    pub const CreateSwapchainOptions = Swapchain.Info;
    pub const CreateTextureOptions = Texture.Info;
    pub const CreateSamplerOptions = Sampler.Info;

    pub const CreateError = error{ UnableToCreateSurface, NoViableAdapter };
    pub const SwapchainError = error{UnableToCreateSwapchain};
    pub const TextureCreateError = error{};
    pub const SamplerCreateError = error{};

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

    inner: Impl,

    /// Attempts to find an adapter matching `preferred_options`.
    /// This function should only be called on main thread.
    pub inline fn open(
        instance: *Instance,
        window_info: WindowInfo,
        power_mode: PowerMode,
    ) CreateError!Adapter {
        return .{ .inner = try Impl.open(instance, window_info, power_mode) };
    }

    /// This function should only be called on main thread.
    pub inline fn close(self: *Adapter) void {
        self.inner.close();
    }

    /// This function should only be called on main thread.
    pub inline fn createSwapchain(
        self: *Adapter,
        options: CreateSwapchainOptions,
    ) SwapchainError!Swapchain {
        return .{ .inner = try self.inner.createSwapchain(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn createSampler(
        self: *Adapter,
        options: CreateSamplerOptions,
    ) SamplerCreateError!Sampler {
        return .{ .inner = try self.inner.createSampler(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn createTexture(
        self: *Adapter,
        options: CreateTextureOptions,
    ) TextureCreateError!Texture {
        return .{ .inner = try self.inner.createTexture(options) };
    }

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Adapter) *const Info {
        return self.inner.info();
    }
};

/// Must never outlive parent `Adapter`.
pub const Swapchain = struct {
    pub const InnerType = backend.Swapchain;

    pub const Info = struct {
        vsync_mode: VsyncMode = .enabled,
        width: u32,
        height: u32,
    };

    inner: InnerType,

    /// This function should only be called on main thread.
    pub inline fn destroy(self: *Swapchain) void {
        self.inner.destroy();
    }

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Swapchain) *const Info {
        return self.inner.info();
    }
};

/// Must never outlive parent `Adapter`.
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
        return self.inner.info();
    }
};

/// Must never outlive parent `Adapter`.
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
        return self.inner.info();
    }
};

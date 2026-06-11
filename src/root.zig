const std = @import("std");

pub const builtin = @import("builtin.zig");
pub const backend = switch (builtin.backend) {
    .vulkan => @import("vulkan/backend.zig"),
    else => @compileError("unknown backend"),
};

pub const GenericError = error{
    AllocationFailed,
    LoaderFailed,
};

pub const Instance = struct {
    pub const InnerType = backend.Instance;

    pub const Error = error{
        InstanceCreationFailed,
    } || GenericError;

    pub const Options = struct {};

    inner: InnerType,

    /// This function should only be called on main thread.
    pub inline fn create(options: Options) !Instance {
        return .{ .inner = try InnerType.create(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn destroy(self: *Instance) void {
        self.inner.destroy();
    }
};

/// Must never outlive parent `Instance`.
pub const Adapter = struct {
    pub const Impl = backend.Adapter;

    pub const Error = error{
        AdapterAcquisitionFailed,
        SurfaceCreationFailed,
    } || GenericError;

    pub const Options = struct {
        window_info: WindowInfo,
        power_mode: PowerMode,
    };

    pub const Info = struct {
        vram_mb: ?u64,
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
        options: Options,
    ) Error!Adapter {
        return .{ .inner = try Impl.open(instance, options) };
    }

    /// This function should only be called on main thread.
    pub inline fn close(self: *Adapter) void {
        self.inner.close();
    }

    /// This function should only be called on main thread.
    pub inline fn createSwapchain(
        self: *Adapter,
        options: Swapchain.Options,
    ) Swapchain.Error!Swapchain {
        return .{ .inner = try self.inner.createSwapchain(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn createShader(
        self: *Adapter,
        options: Shader.Options,
    ) Shader.Error!Shader {
        return .{ .inner = try self.inner.createShader(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn createSampler(
        self: *Adapter,
        options: Sampler.Options,
    ) Sampler.Error!Sampler {
        return .{ .inner = try self.inner.createSampler(options) };
    }

    /// This function should only be called on main thread.
    pub inline fn createTexture(
        self: *Adapter,
        options: Texture.Options,
    ) Texture.Error!Texture {
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
    pub const Options = Info;

    pub const Error = error{
        SwapchainCreationFailed,
    } || GenericError;

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

    /// This function should only be called on main thread.
    pub inline fn present(self: *Swapchain) void {
        self.inner.present();
    }

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Swapchain) *const Info {
        return self.inner.info();
    }
};

/// Must never outlive parent `Adapter`.
pub const Shader = struct {
    pub const InnerType = backend.Shader;
    pub const Error = error{
        ShaderCreationFailed,
        CompilationFailed,
    } || GenericError;

    pub const Bind = struct {
        location: u32,

        value: union(enum) {
            /// Must remain valid for the lifetime of the `Shader`.
            sampler: *const Sampler,
            /// Must remain valid for the lifetime of the `Shader`.
            texture: *const Texture,
        },
    };

    pub const Stage = struct {
        /// SpirV bytecode is required to be aligned to `u32`.
        /// Must remain valid for the lifetime of the `Shader`.
        spirv: []align(@alignOf(u32)) const u8,

        /// Name of the entrypoint.
        /// Must remain valid for the lifetime of the `Shader`.
        entrypoint: [:0]const u8 = "main",

        /// Binding layout.
        /// Must remain valid for the lifetime of the `Shader`.
        binds: []const Bind = &.{},

        /// Optional, improves compatability with OpenGL.
        /// If not null, must remain valid for the lifetime of the `Shader`.
        glsl: ?[]const u8 = null,
    };

    pub const Options = struct {
        vertex: ?Stage = null,
        fragment: ?Stage = null,
        compute: ?Stage = null,
    };

    pub const Info = struct {};

    inner: InnerType,

    /// This function should only be called on main thread.
    pub inline fn destroy(self: *Shader) void {
        self.inner.destroy();
    }

    /// This function is safe to call on any thread.
    pub inline fn info(self: *const Shader) *const Info {
        return self.inner.info();
    }
};

/// Must never outlive parent `Adapter`.
pub const Texture = struct {
    pub const Error = error{} || GenericError;
    pub const Options = Info;

    pub const Format = enum {
        rgba8,
        bgra8,
    };

    pub const Usage = packed struct {
        read: bool,
        write: bool,
        output_target: bool = false,
    };

    pub const Info = struct {
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
    pub const Error = error{} || GenericError;
    pub const Options = Info;

    pub const Filter = enum { linear, nearest };
    pub const AddressMode = enum { clamp, repeat };

    pub const Info = struct {
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

pub const WindowInfo = switch (builtin.platform) {
    .win32 => struct {
        hinstance: ?*anyopaque,
        hwnd: ?*anyopaque,
    },

    .unix => union(enum) {
        xlib: struct { display: ?*anyopaque, window: c_ulong },
        xcb: struct { connection: ?*anyopaque, window: u32 },
        wayland: struct { display: ?*anyopaque, surface: ?*anyopaque },
    },

    .android => struct {
        window: ?*anyopaque,
    },

    else => @compileError("unknown os"),
};

pub const PowerMode = enum { integrated, discrete };
pub const VsyncMode = enum { disabled, enabled, adaptive, mailbox };

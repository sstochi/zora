const std = @import("std");
const vk = @import("vulkan");
const config = @import("config");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const log = std.log.scoped(.adapter);

const Self = @This();
const Instance = @import("Instance.zig");
const Swapchain = @import("Swapchain.zig");
const Shader = @import("Shader.zig");

const Error = zora.Adapter.Error;
const GenericError = zora.GenericError;
const Options = zora.Adapter.Options;
const Info = zora.Adapter.Info;
const Delegate = utils.Delegate;

const GetDeviceProcAddr = Delegate("vkGetDeviceProcAddr");

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const Vtable = utils.Vtable(&.{
    "vkGetDeviceQueue",

    "vkCreateShaderModule",
    "vkCreateSemaphore",
    "vkCreateSwapchainKHR",

    "vkDestroyShaderModule",
    "vkDestroySemaphore",
    "vkDestroySwapchainKHR",

    "vkDeviceWaitIdle",
    "vkAcquireNextImageKHR",
    "vkQueuePresentKHR",
});

const PhysicalDevice = struct {
    name: [256]u8,
    info: Info,
    handle: vk.VkPhysicalDevice,
    graphics_queue_idx: u32,
    surface_queue_idx: u32,

    pub fn query(
        instance: *const Instance,
        handle: vk.VkPhysicalDevice,
        surface: vk.VkSurfaceKHR,
    ) ?PhysicalDevice {
        const max_queues: u32 = 64;
        const max_extensions: u32 = 256;
        const bytes_in_mb = 1000 * 1000;

        const vtable = &instance.vtable;

        // prepare buffers for queues
        var prop: vk.VkPhysicalDeviceProperties = undefined;
        var mem_prop: vk.VkPhysicalDeviceMemoryProperties = undefined;

        // query info about the device
        vtable.call("vkGetPhysicalDeviceProperties", .{ handle, &prop });
        vtable.call("vkGetPhysicalDeviceMemoryProperties", .{ handle, &mem_prop });

        var ext_buffer: [max_extensions]vk.VkExtensionProperties = undefined;
        var queue_buffer: [max_queues]vk.VkQueueFamilyProperties = undefined;
        var ext_count = max_extensions;
        var queue_count = max_queues;

        // finally, query its queue family props...
        vtable.call("vkGetPhysicalDeviceQueueFamilyProperties", .{
            handle,
            &queue_count,
            &queue_buffer,
        });

        // ... and its extensions
        if (vtable.callResult("vkEnumerateDeviceExtensionProperties", .{
            handle,
            null,
            &ext_count,
            &ext_buffer,
        }).fatal()) {
            return null;
        }

        // we search for required extensions
        for (extensions) |ext| {
            for (0..ext_count) |j| {
                const name: [*:0]const u8 = @ptrCast(&ext_buffer[j].extensionName);
                if (std.mem.orderZ(u8, ext, name) == .eq) break;
            } else {
                // bail if haven't found even one
                return null;
            }
        }

        var graphics_queue_idx: ?u32 = null;
        var surface_queue_idx: ?u32 = null;
        var supports_surface: vk.VkBool32 = 0;

        for (0..queue_count) |j| {
            if (vtable.callResult("vkGetPhysicalDeviceSurfaceSupportKHR", .{
                handle,
                @as(u32, @intCast(j)),
                surface,
                &supports_surface,
            }).fatal()) {
                continue;
            }

            // check if queue supprots graphics
            if ((queue_buffer[j].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) {
                graphics_queue_idx = @intCast(j);
            }

            // check if queue supports our surface
            if (supports_surface != 0) {
                surface_queue_idx = @intCast(j);
            }
        }

        return .{
            .graphics_queue_idx = graphics_queue_idx orelse return null,
            .surface_queue_idx = surface_queue_idx orelse return null,

            .name = prop.deviceName,
            .handle = handle,

            .info = .{
                .device_id = prop.deviceID,
                .vendor_id = prop.vendorID,
                .max_samplers = prop.limits.maxSamplerAllocationCount,
                .max_texture_1d = prop.limits.maxImageDimension1D,
                .max_texture_2d = prop.limits.maxImageDimension2D,
                .max_texture_3d = prop.limits.maxImageDimension3D,
                .max_texture_array = prop.limits.maxImageArrayLayers,

                .vram_mb = blk: {
                    var vram_bytes: u64 = 0;
                    for (mem_prop.memoryHeaps[0..mem_prop.memoryHeapCount]) |heap| {
                        if ((heap.flags & vk.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0) {
                            vram_bytes += heap.size;
                        }
                    }
                    break :blk vram_bytes / bytes_in_mb;
                },

                .power_mode = switch (prop.deviceType) {
                    vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => .discrete,
                    else => .integrated,
                },
            },
        };
    }

    pub fn score(self: *const PhysicalDevice, power_mode: zora.PowerMode) u64 {
        var total = @as(u64, @intFromBool(self.info.power_mode == power_mode));
        total *= std.math.maxInt(u32);
        total += self.info.vram_mb.?;
        return total;
    }

    pub fn compareGreaterThan(
        power_mode: zora.PowerMode,
        a: PhysicalDevice,
        b: PhysicalDevice,
    ) bool {
        return b.score(power_mode) < a.score(power_mode);
    }
};

vtable: Vtable,
phy_device: PhysicalDevice,
instance: *const Instance,
get_proc_addr: GetDeviceProcAddr,
handle: vk.VkDevice,
surface: vk.VkSurfaceKHR,
graphics_queue: vk.VkQueue,
surface_queue: vk.VkQueue,

pub fn open(instance_outer: *zora.Instance, options: Options) Error!Self {
    const priority: f32 = 1.0;
    const instance = &instance_outer.inner;

    // load vkGetDeviceProcAddr
    const get_proc_addr = try utils.getProcAddr(
        "vkGetDeviceProcAddr",
        instance.get_proc_addr,
        instance.handle,
    );

    // create surface & regsiter errdefer
    const surface = try createSurface(&instance_outer.inner, options.window_info);
    errdefer instance.vtable.call("vkDestroySurfaceKHR", .{
        instance.handle,
        surface,
        null,
    });

    // rank physical devices and pick one
    const phy_device = try findDevice(instance, surface, options.power_mode);

    const infos = [_]vk.VkDeviceQueueCreateInfo{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = phy_device.graphics_queue_idx,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = phy_device.surface_queue_idx,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        },
    };

    const features = vk.VkPhysicalDeviceFeatures{};
    const create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pEnabledFeatures = &features,

        .pQueueCreateInfos = &infos,
        .queueCreateInfoCount = @as(u32, @intFromBool(
            phy_device.surface_queue_idx != phy_device.graphics_queue_idx,
        )) + 1,

        .ppEnabledExtensionNames = if (extensions.len == 0) null else extensions.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
    };

    log.debug("creating vulkan device ...", .{});
    var device: vk.VkDevice = null;

    // create vulkan device
    try instance.vtable.callError(
        .default,
        "vkCreateDevice",
        error.AdapterAcquisitionFailed,
        .{ phy_device.handle, &create_info, null, &device },
    );

    const destroy_device = try instance.getProcAddr("vkDestroyDevice");
    errdefer destroy_device(device, null);

    const vtable = try Vtable.load(get_proc_addr, device);
    var graphics_queue: vk.VkQueue = null;
    var surface_queue: vk.VkQueue = null;

    // query both queues
    vtable.call("vkGetDeviceQueue", .{
        device,
        phy_device.graphics_queue_idx,
        0,
        &graphics_queue,
    });

    vtable.call("vkGetDeviceQueue", .{
        device,
        phy_device.surface_queue_idx,
        0,
        &surface_queue,
    });

    return .{
        .phy_device = phy_device,
        .vtable = vtable,
        .instance = &instance_outer.inner,
        .get_proc_addr = get_proc_addr,
        .surface = surface,
        .handle = device,
        .graphics_queue = graphics_queue,
        .surface_queue = surface_queue,
    };
}

pub fn close(self: *Self) void {
    log.debug("destroying vulkan surface ...", .{});
    self.instance.vtable.call("vkDestroySurfaceKHR", .{
        self.instance.handle,
        self.surface,
        null,
    });

    log.debug("destroying vulkan device ...", .{});
    self.instance.vtable.call("vkDestroyDevice", .{ self.handle, null });
}

pub inline fn createSwapchain(
    self: *Self,
    options: zora.Swapchain.Options,
) zora.Swapchain.Error!Swapchain {
    return try Swapchain.create(self, options);
}

pub inline fn createShader(
    self: *Self,
    options: zora.Shader.Options,
) zora.Shader.Error!Shader {
    return try Shader.create(self, options);
}

pub fn info(self: *const Self) *const Info {
    return &self.phy_device.info;
}

pub fn getProcAddr(
    self: *const Self,
    comptime name: [:0]const u8,
) GenericError!Delegate(name) {
    return try utils.getProcAddr(
        name,
        self.get_proc_addr,
        self.handle,
    );
}

fn createSurface(
    instance: *const Instance,
    window_info: zora.WindowInfo,
) Error!vk.VkSurfaceKHR {
    log.debug("creating vulkan surface ...", .{});

    return try switch (config.platform) {
        .win32 => createSurfaceGeneric(
            "vkCreateWin32SurfaceKHR",
            instance,
            vk.VkWin32SurfaceCreateInfoKHR{
                .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                .hinstance = @ptrCast(@alignCast(window_info.hinstance)),
                .hwnd = @ptrCast(@alignCast(window_info.hwnd)),
            },
        ),

        .unix => switch (window_info) {
            .xlib => |xlib| createSurfaceGeneric(
                "vkCreateXlibSurfaceKHR",
                instance,
                vk.VkXlibSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
                    .dpy = @ptrCast(@alignCast(xlib.display)),
                    .window = @intCast(xlib.window),
                },
            ),

            .xcb => |xcb| createSurfaceGeneric(
                "vkCreateXcbSurfaceKHR",
                instance,
                vk.VkXcbSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                    .connection = @ptrCast(xcb.connection),
                    .window = @intCast(xcb.window),
                },
            ),

            .wayland => |wayland| createSurfaceGeneric(
                "vkCreateWaylandSurfaceKHR",
                instance,
                vk.VkWaylandSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                    .display = @ptrCast(@alignCast(wayland.display)),
                    .surface = @ptrCast(@alignCast(wayland.surface)),
                },
            ),
        },

        .android => createSurfaceGeneric(
            "vkCreateAndroidSurfaceKHR",
            instance,
            vk.VkAndroidSurfaceCreateInfoKHR{
                .sType = vk.VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR,
                .window = @ptrCast(@alignCast(window_info.window)),
            },
        ),

        else => @compileError("unknown window info"),
    };
}

inline fn createSurfaceGeneric(
    comptime name: [:0]const u8,
    instance: *const Instance,
    create_info: anytype,
) Error!vk.VkSurfaceKHR {
    log.debug("loading delegate \"{s}\" ...", .{name});

    var surface: vk.VkSurfaceKHR = undefined;
    try utils.callError(
        .default,
        try instance.getProcAddr(name),
        error.SurfaceCreationFailed,
        .{ instance.handle, &create_info, null, &surface },
    );

    return surface;
}

fn findDevice(
    instance: *const Instance,
    surface: vk.VkSurfaceKHR,
    power_mode: zora.PowerMode,
) zora.Adapter.Error!PhysicalDevice {
    const max_devices: u32 = 128;

    var device_buffer: [max_devices]PhysicalDevice = undefined;
    var handle_buffer: [max_devices]vk.VkPhysicalDevice = undefined;
    var device_count: usize = 0;
    var handle_count: u32 = max_devices;

    log.debug("querying vulkan physical devices ...", .{});

    // enumerate all physical devices
    try instance.vtable.callError(
        .default,
        "vkEnumeratePhysicalDevices",
        error.AdapterAcquisitionFailed,
        .{ instance.handle, &handle_count, &handle_buffer },
    );

    for (0..handle_count) |i| {
        device_buffer[device_count] = PhysicalDevice.query(
            instance,
            handle_buffer[i],
            surface,
        ) orelse continue;
        device_count += 1;
    }

    // sort the devices using a scoring algorithm
    const slice = device_buffer[0..device_count];
    std.mem.sort(PhysicalDevice, slice, power_mode, PhysicalDevice.compareGreaterThan);

    log.info("available devices:", .{});
    for (slice) |*phy| {
        log.info(" \"{s}\" (vram {?}MB, vendor_id 0x{x}, device_id 0x{x})", .{
            std.mem.sliceTo(&phy.name, 0),
            phy.info.vram_mb,
            phy.info.vendor_id,
            phy.info.device_id,
        });
    }

    // finally, return the best match
    return if (device_count != 0) device_buffer[0] else error.AdapterAcquisitionFailed;
}

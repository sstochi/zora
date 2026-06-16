const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const log = std.log.scoped(.adapter);

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const Self = @This();
const Instance = @import("Instance.zig");
const Swapchain = @import("Swapchain.zig");
const Shader = @import("Shader.zig");

const Error = zora.Adapter.Error;
const GenericError = zora.GenericError;
const Options = zora.Adapter.Options;
const Info = zora.Adapter.Info;

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
        const max_queues: u32 = 32;
        const max_extensions: u32 = 256;
        const bytes_in_mb = 1000 * 1000;

        // prepare buffers for queues
        var prop: vk.VkPhysicalDeviceProperties = undefined;
        var mem_prop: vk.VkPhysicalDeviceMemoryProperties = undefined;

        // query info about the device
        instance.vtable.getPhysicalDeviceProperties(handle, &prop);
        instance.vtable.getPhysicalDeviceMemoryProperties(handle, &mem_prop);

        var ext_buffer: [max_extensions]vk.VkExtensionProperties = undefined;
        var queue_buffer: [max_queues]vk.VkQueueFamilyProperties = undefined;
        var ext_count = max_extensions;
        var queue_count = max_queues;

        // finally, query its queue family props...
        instance.vtable.getPhysicalDeviceQueueFamilyProperties(
            handle,
            &queue_count,
            &queue_buffer,
        );

        // ... and its extensions
        utils.call(instance.vtable.enumerateDeviceExtensionProperties, .{
            handle,
            null,
            &ext_count,
            &ext_buffer,
        }, error.Failed) catch return null;

        // we search for required extensions
        search: for (extensions) |ext| {
            const ext_name = std.mem.span(ext);
            for (0..ext_count) |j| {
                const name = std.mem.sliceTo(&ext_buffer[j].extensionName, 0);
                if (std.mem.eql(u8, ext_name, name)) continue :search;
            }

            // bail if haven't found even one
            return null;
        }

        var graphics_queue_idx: ?u32 = null;
        var surface_queue_idx: ?u32 = null;
        var supports_surface: vk.VkBool32 = 0;
        for (0..queue_count) |j| {
            utils.call(instance.vtable.getPhysicalDeviceSurfaceSupportKHR, .{
                handle,
                @as(u32, @intCast(j)),
                surface,
                &supports_surface,
            }, error.Failed) catch continue;

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

    pub fn compareLessThan(
        power_mode: zora.PowerMode,
        a: PhysicalDevice,
        b: PhysicalDevice,
    ) bool {
        return b.score(power_mode) < a.score(power_mode);
    }
};

const Vtable = struct {
    getDeviceQueue: *const @TypeOf(vk.vkGetDeviceQueue),

    createShaderModule: *const @TypeOf(vk.vkCreateShaderModule),
    createSemaphore: *const @TypeOf(vk.vkCreateSemaphore),
    createSwapchainKHR: *const @TypeOf(vk.vkCreateSwapchainKHR),

    destroyShaderModule: *const @TypeOf(vk.vkDestroyShaderModule),
    destroySemaphore: *const @TypeOf(vk.vkDestroySemaphore),
    destroySwapchainKHR: *const @TypeOf(vk.vkDestroySwapchainKHR),

    deviceWaitIdle: *const @TypeOf(vk.vkDeviceWaitIdle),
    acquireNextImageKHR: *const @TypeOf(vk.vkAcquireNextImageKHR),
    queuePresentKHR: *const @TypeOf(vk.vkQueuePresentKHR),
};

vtable: Vtable,
phy_device: PhysicalDevice,
instance: *const Instance,
handle: vk.VkDevice,
surface: vk.VkSurfaceKHR,
graphics_queue: vk.VkQueue,
surface_queue: vk.VkQueue,

pub fn open(instance_outer: *zora.Instance, options: Options) Error!Self {
    const priority: f32 = 1.0;
    const instance = &instance_outer.inner;

    const surface = try createSurface(&instance_outer.inner, options.window_info);
    errdefer instance.vtable.destroySurfaceKHR(instance.handle, surface, null);

    const phy_device = try findPhyDevice(instance, surface, options.power_mode);
    const info_count = 1 + @as(u32, @intFromBool(
        phy_device.surface_queue_idx != phy_device.graphics_queue_idx,
    ));

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
        .pQueueCreateInfos = &infos,
        .queueCreateInfoCount = info_count,
        .pEnabledFeatures = &features,
        .ppEnabledExtensionNames = if (extensions.len == 0) null else extensions.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
    };

    // create vulkan device
    log.debug("creating vulkan device ...", .{});
    var device: vk.VkDevice = null;
    try utils.call(instance.vtable.createDevice, .{
        phy_device.handle,
        &create_info,
        null,
        &device,
    }, error.AdapterAcquisitionFailed);

    const destroy_device = try instance.getProcAddr(
        *const @TypeOf(vk.vkDestroyDevice),
        "vkDestroyDevice",
    );
    errdefer destroy_device(device, null);

    const vtable = utils.loadVtable(
        Vtable,
        instance.vtable.getDeviceProcAddr,
        device,
    ) orelse return error.LoaderFailed;

    // retrieve graphics and surface queues for later use
    var graphics_queue: vk.VkQueue = null;
    var surface_queue: vk.VkQueue = null;
    vtable.getDeviceQueue(device, phy_device.graphics_queue_idx, 0, &graphics_queue);
    vtable.getDeviceQueue(device, phy_device.surface_queue_idx, 0, &surface_queue);

    return .{
        .phy_device = phy_device,
        .vtable = vtable,
        .instance = &instance_outer.inner,
        .surface = surface,
        .handle = device,
        .graphics_queue = graphics_queue,
        .surface_queue = surface_queue,
    };
}

pub fn close(self: *Self) void {
    log.debug("destroying vulkan surface ...", .{});
    self.instance.vtable.destroySurfaceKHR(
        self.instance.handle,
        self.surface,
        null,
    );

    log.debug("destroying vulkan device ...", .{});
    self.instance.vtable.destroyDevice(self.handle, null);
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
    comptime F: type,
    comptime name: [:0]const u8,
) GenericError!F {
    return @ptrCast(self.instance.vtable.getDeviceProcAddr(self.handle, name.ptr) orelse
        return error.LoaderFailed);
}

fn createSurface(
    instance: *const Instance,
    window_info: zora.WindowInfo,
) Error!vk.VkSurfaceKHR {
    log.debug("creating vulkan surface ...", .{});
    return try switch (zora.builtin.target) {
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

fn createSurfaceGeneric(
    comptime name: [*:0]const u8,
    instance: *const Instance,
    create_info: anytype,
) Error!vk.VkSurfaceKHR {
    log.debug("loading delegate \"{s}\" ...", .{name});
    const F = ?*const fn (
        vk.VkInstance,
        ?*const @TypeOf(create_info),
        ?*const vk.VkAllocationCallbacks,
        ?*vk.VkSurfaceKHR,
    ) callconv(.c) vk.VkResult;

    var surface: vk.VkSurfaceKHR = undefined;
    const create_surface = @as(F, @ptrCast(
        instance.get_proc_addr(instance.handle, name),
    )) orelse return error.LoaderFailed;

    try utils.call(
        create_surface,
        .{
            instance.handle,
            &create_info,
            null,
            &surface,
        },
        error.SurfaceCreationFailed,
    );

    return surface;
}

fn findPhyDevice(
    instance: *const Instance,
    surface: vk.VkSurfaceKHR,
    power_mode: zora.PowerMode,
) zora.Adapter.Error!PhysicalDevice {
    const max_devices: u32 = 32;

    var device_buffer: [max_devices]PhysicalDevice = undefined;
    var handle_buffer: [max_devices]vk.VkPhysicalDevice = undefined;
    var device_count: usize = 0;
    var handle_count: u32 = max_devices;

    log.debug("querying vulkan physical devices ...", .{});

    // enumerate all physical devices
    try utils.call(instance.vtable.enumeratePhysicalDevices, .{
        instance.handle,
        &handle_count,
        &handle_buffer,
    }, error.AdapterAcquisitionFailed);

    for (0..handle_count) |i| {
        device_buffer[device_count] = PhysicalDevice.query(
            instance,
            handle_buffer[i],
            surface,
        ) orelse continue;
        device_count += 1;
    }

    const slice = device_buffer[0..device_count];
    std.mem.sort(PhysicalDevice, slice, power_mode, PhysicalDevice.compareLessThan);

    log.info("available devices:", .{});
    for (slice) |*phy| {
        log.info(" \"{s}\" (vram {?}MB, vendor_id 0x{x}, device_id 0x{x})", .{
            std.mem.sliceTo(&phy.name, 0),
            phy.info.vram_mb,
            phy.info.vendor_id,
            phy.info.device_id,
        });
    }

    return if (device_count != 0) device_buffer[0] else error.AdapterAcquisitionFailed;
}

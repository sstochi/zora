const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Self = @This();
const Instance = @import("Instance.zig");
const Swapchain = @import("Swapchain.zig");

const Error = zora.Adapter.Error;
const SwapchainError = zora.Swapchain.Error;
const GenericError = zora.GenericError;

const Options = zora.Adapter.Options;
const SwapchainOptions = zora.Swapchain.Options;

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const PhysicalDevice = struct {
    name: [256]u8,
    info: zora.Adapter.Info,
    handle: vk.VkPhysicalDevice,
    graphics_queue_idx: u32,
    surface_queue_idx: u32,

    pub fn create(
        instance: *const Instance,
        adapter: vk.VkPhysicalDevice,
        graphics_queue_idx: u32,
        surface_queue_idx: u32,
    ) PhysicalDevice {
        const bytes_in_mb = 1000 * 1000;
        var prop: vk.VkPhysicalDeviceProperties = undefined;
        var mem_prop: vk.VkPhysicalDeviceMemoryProperties = undefined;

        // query info about the device
        instance.vtable.getPhysicalDeviceProperties(adapter, &prop);
        instance.vtable.getPhysicalDeviceMemoryProperties(adapter, &mem_prop);

        // calculate total vram
        var vram_bytes: u64 = 0;
        for (mem_prop.memoryHeaps[0..mem_prop.memoryHeapCount]) |heap| {
            if ((heap.flags & vk.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0) {
                vram_bytes += heap.size;
            }
        }

        return .{
            .name = prop.deviceName,
            .info = .{
                .vram_mb = @intCast(vram_bytes / bytes_in_mb),
                .device_id = prop.deviceID,
                .vendor_id = prop.vendorID,

                .max_samplers = prop.limits.maxSamplerAllocationCount,
                .max_texture_1d = prop.limits.maxImageDimension1D,
                .max_texture_2d = prop.limits.maxImageDimension2D,
                .max_texture_3d = prop.limits.maxImageDimension3D,
                .max_texture_array = prop.limits.maxImageArrayLayers,

                .power_mode = switch (prop.deviceType) {
                    vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => .discrete,
                    else => .integrated,
                },
            },
            .handle = adapter,
            .graphics_queue_idx = graphics_queue_idx,
            .surface_queue_idx = surface_queue_idx,
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

pub fn open(
    instance_outer: *zora.Instance,
    options: Options,
) Error!Self {
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
    var device: vk.VkDevice = null;
    const result = instance.vtable.createDevice(phy_device.handle, &create_info, null, &device);
    try utils.except(result, error.AdapterAcquisitionFailed);

    const vtable = utils.loadVtable(
        Vtable,
        instance.vtable.getDeviceProcAddr,
        device,
    ) orelse return error.LoaderFailed;

    const destroy_device = try instance.getProcAddr(
        *const @TypeOf(vk.vkDestroyDevice),
        "vkDestroyDevice",
    );
    errdefer destroy_device(device, null);

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
    self.instance.vtable.destroySurfaceKHR(
        self.instance.handle,
        self.surface,
        null,
    );
    self.instance.vtable.destroyDevice(self.handle, null);
}

pub inline fn createSwapchain(
    self: *Self,
    options: SwapchainOptions,
) SwapchainError!Swapchain {
    const max_formats: u32 = 128;
    const max_modes: u32 = 8;

    var capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
    var format_buffer: [max_formats]vk.VkSurfaceFormatKHR = undefined;
    var mode_buffer: [max_modes]vk.VkPresentModeKHR = undefined;
    var format_count = max_formats;
    var mode_count = max_modes;

    try utils.except(self.instance.vtable.getPhysicalDeviceSurfaceCapabilitiesKHR(
        self.phy_device.handle,
        self.surface,
        &capabilities,
    ), error.SwapchainCreationFailed);

    try utils.except(self.instance.vtable.getPhysicalDeviceSurfacePresentModesKHR(
        self.phy_device.handle,
        self.surface,
        &mode_count,
        &mode_buffer,
    ), error.SwapchainCreationFailed);

    try utils.except(self.instance.vtable.getPhysicalDeviceSurfaceFormatsKHR(
        self.phy_device.handle,
        self.surface,
        &format_count,
        &format_buffer,
    ), error.SwapchainCreationFailed);

    const target_mode: vk.VkPresentModeKHR = switch (options.vsync_mode) {
        .auto, .enabled => vk.VK_PRESENT_MODE_FIFO_KHR,
        .adaptive => vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
        .disabled => vk.VK_PRESENT_MODE_IMMEDIATE_KHR,
    };

    std.mem.sort(vk.VkPresentModeKHR, mode_buffer[0..mode_count], target_mode, presentModeCompareLessThan);
    std.mem.sort(vk.VkSurfaceFormatKHR, format_buffer[0..format_count], {}, formatCompareLessThan);

    std.log.debug("surface formats:", .{});
    for (0..format_count) |i| {
        std.log.debug("\t{?s}", .{std.enums.tagName(utils.Format, @enumFromInt(format_buffer[i].format))});
    }

    std.log.debug("surface modes:", .{});
    for (0..mode_count) |i| {
        std.log.debug("\t{?s}", .{std.enums.tagName(utils.PresentMode, @enumFromInt(mode_buffer[i]))});
    }

    const same_queue = self.phy_device.graphics_queue_idx == self.phy_device.surface_queue_idx;
    const queue_indicies: [2]u32 = .{
        self.phy_device.graphics_queue_idx,
        self.phy_device.surface_queue_idx,
    };

    if (capabilities.maxImageCount == 0) {
        capabilities.maxImageCount = std.math.maxInt(u32);
    }

    const create_info = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = self.surface,
        .minImageCount = @min(capabilities.minImageCount + 1, capabilities.maxImageCount),

        .presentMode = mode_buffer[0],
        .imageFormat = format_buffer[0].format,
        .imageColorSpace = format_buffer[0].colorSpace,
        .imageExtent = vk.VkExtent2D{
            .width = @min(options.width, capabilities.maxImageExtent.width),
            .height = @min(options.height, capabilities.maxImageExtent.height),
        },
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = if (same_queue) vk.VK_SHARING_MODE_EXCLUSIVE else vk.VK_SHARING_MODE_CONCURRENT,

        .pQueueFamilyIndices = if (same_queue) null else &queue_indicies,
        .queueFamilyIndexCount = if (same_queue) 0 else @intCast(queue_indicies.len),

        .preTransform = capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .clipped = vk.VK_TRUE,
    };

    // create swapchain khr
    var swapchain: vk.VkSwapchainKHR = null;
    const result = self.vtable.createSwapchainKHR(self.handle, &create_info, null, &swapchain);
    try utils.except(result, error.SwapchainCreationFailed);
    errdefer self.vtable.destroySwapchainKHR(self.handle, swapchain, null);

    // create actual swapchain object
    return try Swapchain.create(
        self,
        swapchain,
        .{
            .width = options.width,
            .height = options.height,
            .vsync_mode = switch (mode_buffer[0]) {
                vk.VK_PRESENT_MODE_FIFO_KHR => .enabled,
                vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR => .adaptive,
                else => .disabled,
            },
        },
    );
}

pub fn info(self: *const Self) *const zora.Adapter.Info {
    return &self.phy_device.info;
}

pub fn getProcAddr(self: *const Self, comptime F: type, comptime name: [:0]const u8) GenericError!F {
    return @ptrCast(self.instance.vtable.getDeviceProcAddr(self.handle, name.ptr) orelse
        return error.LoaderFailed);
}

fn createSurface(
    instance: *const Instance,
    window_info: zora.WindowInfo,
) Error!vk.VkSurfaceKHR {
    return try switch (@TypeOf(window_info)) {
        zora.WindowInfoWin32 => createSurfaceGeneric(
            "vkCreateWin32SurfaceKHR",
            instance,
            vk.VkWin32SurfaceCreateInfoKHR{
                .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                .hinstance = @ptrCast(@alignCast(window_info.hinstance)),
                .hwnd = @ptrCast(@alignCast(window_info.hwnd)),
            },
        ),

        zora.WindowInfoUnix => switch (window_info) {
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

        else => @compileError("unknown window info"),
    };
}

fn createSurfaceGeneric(
    comptime name: [*:0]const u8,
    instance: *const Instance,
    create_info: anytype,
) Error!vk.VkSurfaceKHR {
    const F = ?*const fn (
        vk.VkInstance,
        ?*const @TypeOf(create_info),
        ?*const vk.VkAllocationCallbacks,
        ?*vk.VkSurfaceKHR,
    ) callconv(.c) vk.VkResult;

    var surface: vk.VkSurfaceKHR = null;
    const create_surface = @as(F, @ptrCast(
        instance.proc_addr_fn_ptr(instance.handle, name),
    )) orelse return error.LoaderFailed;

    try utils.except(
        create_surface(
            instance.handle,
            &create_info,
            null,
            &surface,
        ),
        error.SurfaceCreationFailed,
    );

    return surface;
}

fn findPhyDevice(
    instance: *const Instance,
    surface: vk.VkSurfaceKHR,
    power_mode: zora.PowerMode,
) zora.Adapter.Error!PhysicalDevice {
    const max_extensions: u32 = 128;
    const max_devices: u32 = 16;

    var ext_buffer: [max_extensions]vk.VkExtensionProperties = undefined;
    var device_buffer: [max_devices]vk.VkPhysicalDevice = undefined;
    var device_count: u32 = max_devices;

    // enumerate all physical devices
    try utils.except(instance.vtable.enumeratePhysicalDevices(
        instance.handle,
        &device_count,
        &device_buffer,
    ), error.AdapterAcquisitionFailed);

    // prepare buffers for queues
    var queue_buffer: [max_devices]vk.VkQueueFamilyProperties = undefined;
    var infos: [max_devices]PhysicalDevice = undefined;
    var supports_surface: vk.VkBool32 = 0;
    var info_count: usize = 0;

    outer: for (0..device_count) |i| {
        const device = device_buffer[i];
        var queue_count = max_devices;
        var ext_count = max_extensions;

        // finally, query its queue family props...
        instance.vtable.getPhysicalDeviceQueueFamilyProperties(
            device,
            &queue_count,
            &queue_buffer,
        );

        // ... and its extensions
        utils.except(instance.vtable.enumerateDeviceExtensionProperties(
            device,
            null,
            &ext_count,
            &ext_buffer,
        ), error.Failed) catch continue;

        // we search for required extensions
        search: for (extensions) |ext| {
            const ext_name = std.mem.span(ext);
            for (0..ext_count) |j| {
                const name = std.mem.sliceTo(&ext_buffer[j].extensionName, 0);
                if (std.mem.eql(u8, ext_name, name)) continue :search;
            }

            // bail if haven't found even one
            continue :outer;
        }

        var graphics_queue_idx: ?u32 = null;
        var surface_queue_idx: ?u32 = null;
        for (0..queue_count) |j| {
            utils.except(instance.vtable.getPhysicalDeviceSurfaceSupportKHR(
                device,
                @intCast(j),
                surface,
                &supports_surface,
            ), error.Failed) catch continue;

            // check if queue supprots graphics
            if ((queue_buffer[j].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) {
                graphics_queue_idx = @intCast(j);
            }

            // check if queue supports our surface
            if (supports_surface != 0) {
                surface_queue_idx = @intCast(j);
            }
        }

        // if it doesn't support either of those, we bail
        infos[info_count] = PhysicalDevice.create(
            instance,
            device,
            graphics_queue_idx orelse continue,
            surface_queue_idx orelse continue,
        );
        info_count += 1;
    }

    const slice = infos[0..info_count];
    std.mem.sort(PhysicalDevice, slice, power_mode, PhysicalDevice.compareLessThan);

    std.log.debug("list of vulkan adapters:", .{});
    for (slice) |*phy| {
        std.log.debug("\t\"{s}\" ({?} mb, vendor_id 0x{x}, device_id 0x{x})", .{
            std.mem.sliceTo(&phy.name, 0),
            phy.info.vram_mb,
            phy.info.vendor_id,
            phy.info.device_id,
        });
    }

    return if (info_count != 0) infos[0] else error.AdapterAcquisitionFailed;
}

fn formatCompareLessThan(_: void, a: vk.VkSurfaceFormatKHR, b: vk.VkSurfaceFormatKHR) bool {
    const score_fn = struct {
        pub fn impl(self: vk.VkSurfaceFormatKHR) u32 {
            const format_score: u32 = switch (@as(utils.Format, @enumFromInt(self.format))) {
                .b8g8r8a8_srgb, .r8g8b8a8_srgb => 2,
                .b8g8r8a8_unorm, .r8g8b8a8_unorm => 1,
                else => 0,
            };

            const colorspace_score: u32 = switch (@as(utils.ColorSpace, @enumFromInt(self.colorSpace))) {
                // .extended_srgb_linear_ext => 20,
                // .hdr10_st2084_ext, .hdr10_hlg_ext => 20,
                .srgb_nonlinear_khr => 10,
                else => 0,
            };

            return format_score + colorspace_score;
        }
    }.impl;

    return score_fn(b) < score_fn(a);
}

fn presentModeCompareLessThan(target: vk.VkPresentModeKHR, a: vk.VkPresentModeKHR, b: vk.VkPresentModeKHR) bool {
    const score_a = @intFromBool(a == target);
    const score_b = @intFromBool(b == target);
    return score_b < score_a;
}

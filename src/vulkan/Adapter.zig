const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Instance = @import("Instance.zig");
const Swapchain = @import("Swapchain.zig");

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

        instance.vtable.getPhysicalDeviceProperties(
            adapter,
            &prop,
        );

        instance.vtable.getPhysicalDeviceMemoryProperties(
            adapter,
            &mem_prop,
        );

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
    createSemaphore: *const @TypeOf(vk.vkCreateSemaphore),
    createSwapchainKHR: *const @TypeOf(vk.vkCreateSwapchainKHR),

    destroySemaphore: *const @TypeOf(vk.vkDestroySemaphore),
    destroySwapchainKHR: *const @TypeOf(vk.vkDestroySwapchainKHR),

    acquireNextImageKHR: *const @TypeOf(vk.vkAcquireNextImageKHR),
    queuePresentKHR: *const @TypeOf(vk.vkQueuePresentKHR),
};

const Self = @This();

vtable: Vtable,
phy_device: PhysicalDevice,
instance: *const Instance,
handle: vk.VkDevice,
surface: vk.VkSurfaceKHR,
graphics_queue: vk.VkQueue,
surface_queue: vk.VkQueue,

pub fn open(
    instance: *zora.Instance,
    window_info: zora.WindowInfo,
    power_mode: zora.PowerMode,
) zora.Adapter.CreateError!Self {
    const priority: f32 = 1.0;
    const inner = &instance.inner;

    const surface = try createSurface(&instance.inner, window_info);
    errdefer inner.vtable.destroySurfaceKHR(inner.handle, surface, null);

    const phy_device = try findPhyDevice(inner, surface, power_mode);
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
        .ppEnabledExtensionNames = extensions.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
    };

    var device: vk.VkDevice = null;
    const result = inner.vtable.createDevice(
        phy_device.handle,
        &create_info,
        null,
        &device,
    );

    if (!utils.success(result)) {
        return error.NoViableAdapter;
    }

    const vtable = utils.loadVtable(
        Vtable,
        inner.vtable.getDeviceProcAddr,
        device,
    ) orelse return error.NoViableAdapter;

    var graphics_queue: vk.VkQueue = null;
    var surface_queue: vk.VkQueue = null;
    vtable.getDeviceQueue(device, phy_device.graphics_queue_idx, 0, &graphics_queue);
    vtable.getDeviceQueue(device, phy_device.surface_queue_idx, 0, &surface_queue);

    return .{
        .phy_device = phy_device,
        .vtable = vtable,
        .instance = &instance.inner,
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
    options: zora.Adapter.CreateSwapchainOptions,
) zora.Adapter.SwapchainError!Swapchain {
    const max_formats: u32 = 128;
    const max_modes: u32 = 8;

    var capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
    var format_buffer: [max_formats]vk.VkSurfaceFormatKHR = undefined;
    var mode_buffer: [max_modes]vk.VkPresentModeKHR = undefined;
    var format_count = max_formats;
    var mode_count = max_modes;

    if (!utils.success(self.instance.vtable.getPhysicalDeviceSurfaceCapabilitiesKHR(
        self.phy_device.handle,
        self.surface,
        &capabilities,
    ))) {
        return error.UnableToCreateSwapchain;
    }

    if (capabilities.maxImageCount == 0) {
        capabilities.maxImageCount = std.math.maxInt(u32);
    }

    if (!utils.success(self.instance.vtable.getPhysicalDeviceSurfacePresentModesKHR(
        self.phy_device.handle,
        self.surface,
        &mode_count,
        &mode_buffer,
    ))) {
        return error.UnableToCreateSwapchain;
    }

    if (!utils.success(self.instance.vtable.getPhysicalDeviceSurfaceFormatsKHR(
        self.phy_device.handle,
        self.surface,
        &format_count,
        &format_buffer,
    ))) {
        return error.UnableToCreateSwapchain;
    }

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

    var swapchain: vk.VkSwapchainKHR = undefined;
    const result = self.vtable.createSwapchainKHR(self.handle, &create_info, null, &swapchain);
    if (!utils.success(result)) return error.UnableToCreateSwapchain;
    errdefer self.vtable.destroySwapchainKHR(self.handle, swapchain, null);

    return Swapchain.create(
        self,
        swapchain,
        options,
    ) orelse return error.UnableToCreateSwapchain;
}

pub fn info(self: *const Self) *const zora.Adapter.Info {
    return &self.phy_device.info;
}

fn createSurface(
    instance: *const Instance,
    window_info: zora.WindowInfo,
) zora.Adapter.CreateError!vk.VkSurfaceKHR {
    return switch (@TypeOf(window_info)) {
        zora.WindowInfoWin32 => createSurfaceGeneric(
            "vkCreateWin32SurfaceKHR",
            instance,
            vk.VkWin32SurfaceCreateInfoKHR{
                .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                .hinstance = window_info.hinstance,
                .hwnd = window_info.hwnd,
            },
        ),

        zora.WindowInfoUnix => switch (window_info) {
            .xlib => |xlib| createSurfaceGeneric(
                "vkCreateXlibSurfaceKHR",
                instance,
                vk.VkXlibSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
                    .dpy = @ptrCast(xlib.display),
                    .window = xlib.window,
                },
            ),

            .xcb => |xcb| createSurfaceGeneric(
                "vkCreateXcbSurfaceKHR",
                instance,
                vk.VkXcbSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                    .connection = @ptrCast(xcb.connection),
                    .window = xcb.window,
                },
            ),

            .wayland => |wayland| createSurfaceGeneric(
                "vkCreateWaylandSurfaceKHR",
                instance,
                vk.VkWaylandSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                    .display = @ptrCast(wayland.display),
                    .surface = @ptrCast(wayland.surface),
                },
            ),
        },

        else => @compileError("unknown window info"),
    } orelse return error.UnableToCreateSurface;
}

fn createSurfaceGeneric(
    comptime name: [*:0]const u8,
    instance: *const Instance,
    create_info: anytype,
) ?vk.VkSurfaceKHR {
    const F = ?*const fn (
        vk.VkInstance,
        ?*const @TypeOf(create_info),
        ?*const vk.VkAllocationCallbacks,
        ?*vk.VkSurfaceKHR,
    ) callconv(.c) vk.VkResult;

    var surface: vk.VkSurfaceKHR = null;
    const create_surface = @as(F, @ptrCast(
        instance.get_proc_addr(instance.handle, name),
    )) orelse return null;

    const result = create_surface(instance.handle, &create_info, null, &surface);
    return if (utils.success(result)) surface else null;
}

fn findPhyDevice(
    instance: *const Instance,
    surface: vk.VkSurfaceKHR,
    power_mode: zora.PowerMode,
) zora.Adapter.CreateError!PhysicalDevice {
    const max_extensions: u32 = 128;
    const max_devices: u32 = 16;

    var result: vk.VkResult = undefined;
    var ext_buffer: [max_extensions]vk.VkExtensionProperties = undefined;
    var device_buffer: [max_devices]vk.VkPhysicalDevice = undefined;
    var device_count: u32 = max_devices;

    // enumerate all physical devices
    result = instance.vtable.enumeratePhysicalDevices(
        instance.handle,
        &device_count,
        &device_buffer,
    );

    if (!utils.success(result)) {
        return error.NoViableAdapter;
    }

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
        result = instance.vtable.enumerateDeviceExtensionProperties(
            device,
            null,
            &ext_count,
            &ext_buffer,
        );

        if (!utils.success(result)) {
            continue;
        }

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
            if (instance.vtable.getPhysicalDeviceSurfaceSupportKHR(
                device,
                @intCast(j),
                surface,
                &supports_surface,
            ) != vk.VK_SUCCESS) {
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

    return if (info_count != 0) infos[0] else error.NoViableAdapter;
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

const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Instance = @import("Instance.zig");

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const PhysicalDevice = struct {
    name: [256]u8,
    info: zora.Adapter.Info,
    device: vk.VkPhysicalDevice,
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
            .device = adapter,
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
        return a.score(power_mode) > b.score(power_mode);
    }
};

const Vtable = struct {
    getDeviceQueue: *const @TypeOf(vk.vkGetDeviceQueue),
};

const Self = @This();

vtable: Vtable,
instance: *const Instance,
surface: vk.VkSurfaceKHR,
device: vk.VkDevice,
graphics_queue: vk.VkQueue,
surface_queue: vk.VkQueue,
phy_device: PhysicalDevice,

pub fn open(
    instance: *zora.Instance,
    window_info: zora.WindowInfo,
    power_mode: zora.PowerMode,
) zora.Adapter.CreateError!Self {
    const priority: f32 = 1.0;

    const surface = try createSurface(&instance.inner, window_info);
    errdefer instance.inner.vtable.destroySurfaceKHR(
        instance.inner.handle,
        surface,
        null,
    );

    const phy_device = try findPhyDevice(&instance.inner, surface, power_mode);
    const info_count = 1 + @intFromBool(
        phy_device.surface_queue_idx != phy_device.graphics_queue_idx,
    );

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
    const result = instance.inner.vtable.createDevice(
        phy_device.device,
        &create_info,
        null,
        &device,
    );

    if (result != vk.VK_SUCCESS) {
        return error.NoViableAdapter;
    }

    const vtable = utils.loadVtable(
        Vtable,
        instance.inner.vtable.getDeviceProcAddr,
        device,
    ) orelse return error.NoViableAdapter;

    var graphics_queue: vk.VkQueue = null;
    var surface_queue: vk.VkQueue = null;
    vtable.getDeviceQueue(device, phy_device.graphics_queue_idx, 0, &graphics_queue);
    vtable.getDeviceQueue(device, phy_device.surface_queue_idx, 0, &surface_queue);

    return .{
        .vtable = vtable,
        .instance = &instance.inner,
        .surface = surface,
        .device = device,
        .graphics_queue = graphics_queue,
        .surface_queue = surface_queue,
        .phy_device = phy_device,
    };
}

pub fn close(self: *Self) void {
    self.instance.vtable.destroySurfaceKHR(
        self.instance.handle,
        self.surface,
        null,
    );
    self.instance.vtable.destroyDevice(self.device, null);
}

// pub inline fn createSwapchain(
//     self: *zora.Adapter,
//     options: zora.Adapter.CreateSwapchainOptions,
// ) zora.Adapter.SwapchainError!zora.Swapchain {}

pub fn info(self: *const Self) *const zora.Adapter.Info {
    return &self.phy_device.info;
}

fn createSurface(
    instance: *const Instance,
    window_info: zora.WindowInfo,
) zora.Adapter.CreateError!vk.VkSurfaceKHR {
    return switch (@TypeOf(window_info)) {
        zora.WindowInfoWin32 => try createSurfaceGeneric(
            "vkCreateWin32SurfaceKHR",
            instance,
            vk.VkWin32SurfaceCreateInfoKHR{
                .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
                .hinstance = window_info.hinstance,
                .hwnd = window_info.hwnd,
            },
        ),

        zora.WindowInfoUnix => switch (window_info) {
            .xlib => |xlib| try createSurfaceGeneric(
                "vkCreateXlibSurfaceKHR",
                instance,
                vk.VkXlibSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
                    .dpy = @ptrCast(xlib.display),
                    .window = xlib.window,
                },
            ),

            .xcb => |xcb| try createSurfaceGeneric(
                "vkCreateXcbSurfaceKHR",
                instance,
                vk.VkXcbSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
                    .connection = @ptrCast(xcb.connection),
                    .window = xcb.window,
                },
            ),

            .wayland => |wayland| try createSurfaceGeneric(
                "vkCreateWaylandSurfaceKHR",
                instance,
                vk.VkWaylandSurfaceCreateInfoKHR{
                    .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                    .display = @ptrCast(wayland.display),
                    .surface = @ptrCast(wayland.surface),
                },
            ),
        },

        else => return error.UnableToCreateSurface,
    };
}

fn createSurfaceGeneric(
    comptime name: [*:0]const u8,
    instance: *const Instance,
    create_info: anytype,
) zora.Adapter.CreateError!vk.VkSurfaceKHR {
    const F = ?*const fn (
        vk.VkInstance,
        ?*const @TypeOf(create_info),
        ?*const vk.VkAllocationCallbacks,
        ?*vk.VkSurfaceKHR,
    ) callconv(.c) vk.VkResult;

    var surface: vk.VkSurfaceKHR = null;
    const create_surface = @as(F, @ptrCast(
        instance.get_proc_addr(instance.handle, name),
    )) orelse return error.UnableToCreateSurface;

    const result = create_surface(instance.handle, &create_info, null, &surface);
    return if (result == vk.VK_SUCCESS) surface else error.UnableToCreateSurface;
}

fn findPhyDevice(
    instance: *const Instance,
    surface: vk.VkSurfaceKHR,
    power_mode: zora.PowerMode,
) zora.Adapter.CreateError!PhysicalDevice {
    const max_extensions: u32 = 128;
    const max_devices: u32 = 16;

    // prepare buffers for vulkan
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

    if (result != vk.VK_SUCCESS and result != vk.VK_INCOMPLETE) {
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

        if (result != vk.VK_SUCCESS and result != vk.VK_INCOMPLETE) {
            continue;
        }

        search: for (extensions) |ext| {
            const ext_name = std.mem.span(ext);
            for (0..ext_count) |j| {
                const name = std.mem.sliceTo(&ext_buffer[j].extensionName, 0);
                if (std.mem.eql(u8, ext_name, name)) continue :search;
            }
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
                graphics_queue_idx = @intCast(i);
            }

            // check if queue supports our surface
            if (supports_surface != 0) {
                surface_queue_idx = @intCast(i);
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

const std = @import("std");
const vk = @import("vulkan");
const zora = @import("../root.zig");

const validation_layers: []const [*:0]const u8 = if (zora.build_debug) &[_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
} else &.{};

const extensions: []const [*:0]const u8 = &[_][*:0]const u8{};

const Device = struct {
    name: [256]u8,
    info: zora.Adapter.Info,
    device: vk.VkPhysicalDevice,

    pub fn create(device: vk.VkPhysicalDevice) Device {
        const bytes_in_mb = 1000 * 1000;

        var prop: vk.VkPhysicalDeviceProperties = undefined;
        var mem_prop: vk.VkPhysicalDeviceMemoryProperties = undefined;

        vk.vkGetPhysicalDeviceProperties(device, &prop);
        vk.vkGetPhysicalDeviceMemoryProperties(device, &mem_prop);

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
            .device = device,
        };
    }

    pub fn score(self: *const Device, options: zora.Adapter.CreateOptions) u64 {
        var total = @as(u64, @intFromBool(self.info.power_mode == options.power_mode)) * std.math.maxInt(u32);
        total += self.info.vram_mb.?;
        return total;
    }

    pub fn compareLessThan(options: zora.Adapter.CreateOptions, a: Device, b: Device) bool {
        return a.score(options) > b.score(options);
    }
};

const Self = @This();

instance: vk.VkInstance,
device: Device,

pub fn open(options: zora.Adapter.CreateOptions) zora.Adapter.CreateError!Self {
    const version = vk.VK_MAKE_VERSION(zora.build_version.major, zora.build_version.minor, zora.build_version.patch);

    const app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "zora Application",
        .applicationVersion = version,
        .pEngineName = "zora",
        .engineVersion = version,
        .apiVersion = vk.VK_API_VERSION_1_0,
    };

    const create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .ppEnabledLayerNames = validation_layers.ptr,
        .ppEnabledExtensionNames = extensions.ptr,
        .enabledLayerCount = @intCast(validation_layers.len),
        .enabledExtensionCount = @intCast(extensions.len),
    };

    var instance: vk.VkInstance = null;
    errdefer vk.vkDestroyInstance(instance, null);

    const result = vk.vkCreateInstance(&create_info, null, &instance);
    if (result != vk.VK_SUCCESS) {
        return error.NoViableAdapter;
    }

    return .{
        .instance = instance,
        .device = try findMatchingAdapter(instance, options),
    };
}

pub fn close(self: *Self) void {
    vk.vkDestroyInstance(self.instance, null);
}

pub fn info(self: *const Self) *const zora.Adapter.Info {
    return &self.device.info;
}

inline fn findMatchingAdapter(instance: vk.VkInstance, options: zora.Adapter.CreateOptions) zora.Adapter.CreateError!Device {
    const device_max_count: u32 = 32;

    var device_buffer: [device_max_count]Device = undefined;
    var device_enum_buffer: [device_max_count]vk.VkPhysicalDevice = undefined;
    var device_enum_count: u32 = device_max_count;

    const result = vk.vkEnumeratePhysicalDevices(instance, &device_enum_count, &device_enum_buffer);
    if (result != vk.VK_SUCCESS and result != vk.VK_INCOMPLETE) {
        return error.NoViableAdapter;
    }

    const device_slice = device_buffer[0..device_enum_count];
    for (0..device_enum_count) |i| {
        device_slice[i] = Device.create(device_enum_buffer[i]);
    }

    std.mem.sort(Device, device_slice, options, Device.compareLessThan);

    std.log.debug("List of vulkan adapters:", .{});
    for (device_slice) |*device| {
        std.log.debug("\t\"{s}\" ({?} mb, vendor_id 0x{x}, device_id 0x{x})", .{
            std.mem.sliceTo(&device.name, 0),
            device.info.vram_mb,
            device.info.vendor_id,
            device.info.device_id,
        });
    }

    return if (device_enum_count != 0) device_buffer[0] else error.NoViableAdapter;
}

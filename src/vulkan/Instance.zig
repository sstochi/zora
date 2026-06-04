const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const validation_layers: []const [*:0]const u8 = switch (zora.build_debug) {
    true => &.{"VK_LAYER_KHRONOS_validation"},
    false => &.{},
};

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SURFACE_EXTENSION_NAME,
};

const optional_extensions: []const [*:0]const u8 = switch (builtin.os.tag) {
    .windows => &.{
        vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    },

    .linux, .freebsd => &.{
        vk.VK_KHR_XLIB_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_XCB_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
    },

    else => @compileError("unknown os"),
};
const max_optional_extensions = 4;

const vulkan_lib_name = switch (builtin.os.tag) {
    .windows => "vulkan-1.dll",
    .linux, .freebsd => "libvulkan.so",
    .macos => "libvulkan.dylib",
    else => @compileError("unknown os"),
};

const Vtable = struct {
    getDeviceProcAddr: *const @TypeOf(vk.vkGetDeviceProcAddr),

    createDevice: *const @TypeOf(vk.vkCreateDevice),

    destroyInstance: *const @TypeOf(vk.vkDestroyInstance),
    destroyDevice: *const @TypeOf(vk.vkDestroyDevice),
    destroySurfaceKHR: *const @TypeOf(vk.vkDestroySurfaceKHR),

    enumeratePhysicalDevices: *const @TypeOf(vk.vkEnumeratePhysicalDevices),
    enumerateDeviceExtensionProperties: *const @TypeOf(vk.vkEnumerateDeviceExtensionProperties),

    getPhysicalDeviceQueueFamilyProperties: *const @TypeOf(vk.vkGetPhysicalDeviceQueueFamilyProperties),
    getPhysicalDeviceSurfaceSupportKHR: *const @TypeOf(vk.vkGetPhysicalDeviceSurfaceSupportKHR),
    getPhysicalDeviceSurfaceCapabilitiesKHR: *const @TypeOf(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR),
    getPhysicalDeviceSurfaceFormatsKHR: *const @TypeOf(vk.vkGetPhysicalDeviceSurfaceFormatsKHR),
    getPhysicalDeviceSurfacePresentModesKHR: *const @TypeOf(vk.vkGetPhysicalDeviceSurfacePresentModesKHR),
    getPhysicalDeviceProperties: *const @TypeOf(vk.vkGetPhysicalDeviceProperties),
    getPhysicalDeviceMemoryProperties: *const @TypeOf(vk.vkGetPhysicalDeviceMemoryProperties),

    queuePresentKHR: *const @TypeOf(vk.vkQueuePresentKHR),
};

const Self = @This();

vtable: Vtable,
handle: vk.VkInstance,
get_proc_addr: *const @TypeOf(vk.vkGetInstanceProcAddr),
loader_handle: std.DynLib,

pub fn create() zora.Instance.CreateInstanceError!Self {
    const max_properties = 128;

    const version = vk.VK_MAKE_VERSION(
        zora.build_version.major,
        zora.build_version.minor,
        zora.build_version.patch,
    );

    const app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "zora Application",
        .applicationVersion = version,
        .pEngineName = "zora",
        .engineVersion = version,
        .apiVersion = vk.VK_API_VERSION_1_0,
    };

    var result: vk.VkResult = undefined;
    var query_buffer: [max_properties]vk.VkExtensionProperties = undefined;
    var query_count: u32 = max_properties;

    // load vulkan lib
    var loader_handle = std.DynLib.open(vulkan_lib_name) catch
        return error.UnableToCreateInstance;
    errdefer loader_handle.close();

    const get_instance_proc_addr = loader_handle.lookup(
        *const @TypeOf(vk.vkGetInstanceProcAddr),
        "vkGetInstanceProcAddr",
    ) orelse return error.UnableToCreateInstance;

    const enum_extensions: *const @TypeOf(vk.vkEnumerateInstanceExtensionProperties) = @ptrCast(
        get_instance_proc_addr(null, "vkEnumerateInstanceExtensionProperties") orelse
            return error.UnableToCreateInstance,
    );

    const createInstance: *const @TypeOf(vk.vkCreateInstance) = @ptrCast(
        get_instance_proc_addr(null, "vkCreateInstance") orelse
            return error.UnableToCreateInstance,
    );

    // query all extensions
    result = enum_extensions(null, &query_count, &query_buffer);
    if (!utils.success(result)) {
        return error.UnableToCreateInstance;
    }

    // create initial extension list
    var ext_buffer: [max_optional_extensions + extensions.len][*:0]const u8 = undefined;
    var ext_count = extensions.len;
    @memcpy(ext_buffer[0..extensions.len], extensions);

    std.log.debug("vulkan instance extensions:", .{});
    for (extensions) |ext| {
        const name = std.mem.span(ext);
        std.log.debug("\t\"{s}\"", .{name});
    }

    // enable supported optional extensions
    for (optional_extensions) |ext| {
        const opt_name = std.mem.span(ext);

        for (0..query_count) |i| {
            const name = std.mem.sliceTo(&query_buffer[i].extensionName, 0);
            if (std.mem.eql(u8, name, opt_name)) {
                std.log.debug("\t\"{s}\"", .{name});
                ext_buffer[ext_count] = ext;
                ext_count += 1;
                break;
            }
        }
    }

    const create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .ppEnabledLayerNames = validation_layers.ptr,
        .ppEnabledExtensionNames = &ext_buffer,
        .enabledLayerCount = @intCast(validation_layers.len),
        .enabledExtensionCount = @intCast(ext_count),
    };

    // create vulkan instance
    var instance: vk.VkInstance = null;
    result = createInstance(&create_info, null, &instance);
    if (!utils.success(result)) return error.UnableToCreateInstance;

    return .{
        // load virtual functions
        .vtable = utils.loadVtable(
            Vtable,
            get_instance_proc_addr,
            instance,
        ) orelse return error.UnableToCreateInstance,

        .handle = instance,
        .loader_handle = loader_handle,
        .get_proc_addr = get_instance_proc_addr,
    };
}

pub fn destroy(self: *Self) void {
    self.vtable.destroyInstance(self.handle, null);
    self.loader_handle.close();
}

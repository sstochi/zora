const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
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

const Self = @This();

handle: vk.VkInstance,

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

    // query all extensions
    result = vk.vkEnumerateInstanceExtensionProperties(
        null,
        &query_count,
        &query_buffer,
    );

    if (result != vk.VK_SUCCESS and result != vk.VK_INCOMPLETE) {
        return error.UnableToCreateInstance;
    }

    // create initial extension list
    var ext_buffer: [max_optional_extensions + extensions.len][*:0]const u8 = undefined;
    var ext_count = extensions.len;
    @memcpy(ext_buffer[0..extensions.len], extensions);

    // enable supported optional extensions
    std.log.debug("vulkan instance extensions:", .{});
    for (extensions) |ext| {
        const name = std.mem.span(ext);
        std.log.debug("\t\"{s}\"", .{name});
    }

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
    result = vk.vkCreateInstance(&create_info, null, &instance);
    if (result != vk.VK_SUCCESS) return error.UnableToCreateInstance;

    return .{ .handle = instance };
}

pub fn destroy(self: *Self) void {
    vk.vkDestroyInstance(self.handle, null);
}

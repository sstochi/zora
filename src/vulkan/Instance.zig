const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const log = std.log.scoped(.instance);

const Self = @This();
const Error = zora.Instance.Error;
const GenericError = zora.GenericError;
const Options = zora.Instance.Options;
const Delegate = utils.Delegate;
const DynLib = utils.DynLib;

const GetInstanceProcAddr = Delegate("vkGetInstanceProcAddr");
const DestroyDebugUtilsMessenger = Delegate("vkDestroyDebugUtilsMessengerEXT");

const total_extensions = required_extensions.len + optional_extensions.len;
const optional_extensions: []const [*:0]const u8 = optional_debug_extensions ++ optional_target_extensions;

const required_extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SURFACE_EXTENSION_NAME,
};

const optional_debug_extensions: []const [*:0]const u8 = &.{
    vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
};

const optional_target_extensions: []const [*:0]const u8 = switch (zora.builtin.target) {
    .win32 => &.{
        vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    },

    .unix => &.{
        vk.VK_KHR_XLIB_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_XCB_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
    },

    .android => &.{
        vk.VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
    },

    else => @compileError("unknown os"),
};

const validation_layers: []const [*:0]const u8 = switch (zora.builtin.debug) {
    true => &.{"VK_LAYER_KHRONOS_validation"},
    false => &.{},
};

const Vtable = utils.Vtable(&.{
    "vkCreateDevice",
    "vkDestroyInstance",
    "vkDestroyDevice",
    "vkDestroySurfaceKHR",

    "vkEnumeratePhysicalDevices",
    "vkEnumerateDeviceExtensionProperties",

    "vkGetPhysicalDeviceQueueFamilyProperties",
    "vkGetPhysicalDeviceSurfaceSupportKHR",
    "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
    "vkGetPhysicalDeviceSurfaceFormatsKHR",
    "vkGetPhysicalDeviceSurfacePresentModesKHR",
    "vkGetPhysicalDeviceProperties",
    "vkGetPhysicalDeviceMemoryProperties",

    "vkQueuePresentKHR",
});

const Diagnostic = struct {
    // configure create info for diagnostic logger
    pub const create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,

        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,

        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT |
            // only enable verbose logging in debug
            (vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT * @intFromBool(zora.builtin.debug)),

        .pfnUserCallback = messageCallback,
    };

    instance: vk.VkInstance,
    handle: vk.VkDebugUtilsMessengerEXT,
    destroy_messenger: DestroyDebugUtilsMessenger,

    pub fn create(
        instance: vk.VkInstance,
        get_proc_addr: GetInstanceProcAddr,
    ) ?Diagnostic {
        const create_messenger = utils.getProcAddr(
            "vkCreateDebugUtilsMessengerEXT",
            get_proc_addr,
            instance,
        ) catch return null;

        const destroy_messenger = utils.getProcAddr(
            "vkDestroyDebugUtilsMessengerEXT",
            get_proc_addr,
            instance,
        ) catch return null;

        var handle: vk.VkDebugUtilsMessengerEXT = null;
        const result = utils.callResult(
            create_messenger,
            .{ instance, &create_info, null, &handle },
        );

        return if (result == .success) .{
            .instance = instance,
            .handle = handle,
            .destroy_messenger = destroy_messenger,
        } else null;
    }

    pub fn destroy(self: *const Diagnostic) void {
        self.destroy_messenger(self.instance, self.handle, null);
    }

    fn messageCallback(
        severity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
        _: vk.VkDebugUtilsMessageTypeFlagsEXT,
        message_data: ?*const vk.VkDebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(.c) vk.VkBool32 {
        const scoped = std.log.scoped(.diagnostic);
        const data = message_data orelse return vk.VK_FALSE;

        switch (severity) {
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
            => scoped.debug("{s}", .{std.mem.sliceTo(data.pMessage, 0)}),

            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
            => scoped.info("{s}", .{std.mem.sliceTo(data.pMessage, 0)}),

            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
            => scoped.warn("{s}", .{std.mem.sliceTo(data.pMessage, 0)}),

            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            => scoped.err("{s}", .{std.mem.sliceTo(data.pMessage, 0)}),

            else => unreachable,
        }

        return vk.VK_FALSE;
    }
};

vtable: Vtable,
diagnostic: ?Diagnostic,
handle: vk.VkInstance,
get_proc_addr: GetInstanceProcAddr,
loader: DynLib,

pub fn create(_: Options) Error!Self {
    const max_extensions: u32 = 1024;

    // load vulkan lib
    log.info("loading vulkan lib ...", .{});
    var loader = try DynLib.open();
    errdefer loader.close();

    log.debug("loading essential delegates ...", .{});
    const get_proc_addr = try loader.lookup(
        GetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    );

    const enum_extensions = try utils.getProcAddr(
        "vkEnumerateInstanceExtensionProperties",
        get_proc_addr,
        null,
    );

    // query all extensions
    var query_buffer: [max_extensions]vk.VkExtensionProperties = undefined;
    var query_count = max_extensions;
    try utils.callError(
        .default,
        enum_extensions,
        error.InstanceCreationFailed,
        .{ null, &query_count, &query_buffer },
    );

    // create initial extension list
    var ext_buffer: [total_extensions][*:0]const u8 = undefined;
    var ext_count = required_extensions.len;
    @memcpy(ext_buffer[0..required_extensions.len], required_extensions);

    log.info("required extensions:", .{});
    for (required_extensions) |ext| {
        log.info(" \"{s}\"", .{std.mem.span(ext)});
    }

    // enable supported optional extensions
    log.info("supported optional extensions:", .{});
    for (optional_extensions) |ext| {
        for (0..query_count) |i| {
            const name: [*:0]const u8 = @ptrCast(&query_buffer[i].extensionName);

            if (std.mem.orderZ(u8, ext, name) == .eq) {
                log.info(" \"{s}\"", .{name});
                ext_buffer[ext_count] = ext;
                ext_count += 1;
            }
        }
    }

    // check if diagnostic logging is supported
    const enable_diag = zora.builtin.debug and blk: {
        for (0..ext_count) |i| {
            if (std.mem.orderZ(
                u8,
                ext_buffer[i],
                vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
            ) == .eq) break :blk true;
        }
        break :blk false;
    };

    const version = vk.VK_MAKE_VERSION(
        zora.builtin.version.major,
        zora.builtin.version.minor,
        zora.builtin.version.patch,
    );

    const app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "zora Application",
        .applicationVersion = version,
        .pEngineName = "zora",
        .engineVersion = version,
        .apiVersion = vk.VK_API_VERSION_1_0,
    };

    var create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,

        // enable diagnostic if supported
        .pNext = if (enable_diag) @ptrCast(&Diagnostic.create_info) else null,

        .pApplicationInfo = &app_info,
        .ppEnabledLayerNames = validation_layers.ptr,
        .ppEnabledExtensionNames = &ext_buffer,
        .enabledLayerCount = @intCast(validation_layers.len),
        .enabledExtensionCount = @intCast(ext_count),
    };

    // create vulkan instance
    log.debug("creating vulkan instance ...", .{});
    var handle: vk.VkInstance = null;

    const create_instance = try utils.getProcAddr(
        "vkCreateInstance",
        get_proc_addr,
        null,
    );

    while (true) {
        switch (utils.callResult(create_instance, .{ &create_info, null, &handle })) {
            .success => break,

            .layer_not_present => {
                log.warn("one or more validation layer(s) not supported, disabling all of them.", .{});
                create_info.ppEnabledLayerNames = null;
                create_info.enabledLayerCount = 0;
            },

            else => return error.InstanceCreationFailed,
        }
    }

    // load destroy and setup defer
    const destroy_instance = try utils.getProcAddr(
        "vkDestroyInstance",
        get_proc_addr,
        handle,
    );
    errdefer destroy_instance(handle, null);

    return .{
        .diagnostic = Diagnostic.create(handle, get_proc_addr),

        // load virtual functions
        .vtable = try Vtable.load(get_proc_addr, handle),

        .handle = handle,
        .loader = loader,
        .get_proc_addr = get_proc_addr,
    };
}

pub fn destroy(self: *Self) void {
    log.debug("destroying vulkan instance ...", .{});

    if (self.diagnostic) |*diag| {
        diag.destroy();
    }

    self.vtable.call("vkDestroyInstance", .{ self.handle, null });
    self.loader.close();
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

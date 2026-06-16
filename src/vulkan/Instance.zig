const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const log = std.log.scoped(.instance);
const required_extensions = extensions ++ debug_extensions;
const max_optional_extensions = 4;

const library_name: [:0]const u8 = switch (zora.builtin.target) {
    .win32 => "vulkan-1.dll",
    .unix, .android => "libvulkan.so",
    .macos => "libvulkan.dylib",
};

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SURFACE_EXTENSION_NAME,
};

const debug_extensions: []const [*:0]const u8 = switch (zora.builtin.debug) {
    true => &.{vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME},
    false => &.{},
};

const optional_extensions: []const [*:0]const u8 = switch (zora.builtin.target) {
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

const Self = @This();
const Error = zora.Instance.Error;
const GenericError = zora.GenericError;
const Options = zora.Instance.Options;

const VulkanLoader = switch (zora.builtin.target) {
    // zig 0.16.0 removed windows from std.DynLib... Thanks, Andrew!
    .win32 => struct {
        const BOOL = c_int;
        const HMODULE = ?*anyopaque;
        const FARPROC = ?*const fn () callconv(.c) c_int;

        extern fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.c) HMODULE;
        extern fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8) callconv(.c) FARPROC;
        extern fn FreeLibrary(hLibModule: HMODULE) callconv(.c) BOOL;

        hmodule: HMODULE,

        pub fn open() Error!VulkanLoader {
            return .{
                .hmodule = LoadLibraryA(
                    library_name.ptr,
                ) orelse return error.LoaderFailed,
            };
        }

        pub fn close(self: *VulkanLoader) void {
            _ = FreeLibrary(self.hmodule);
        }

        pub fn lookup(self: *VulkanLoader, comptime T: type, name: [:0]const u8) ?T {
            return @ptrCast(GetProcAddress(self.hmodule, name.ptr));
        }
    },

    else => struct {
        handle: std.DynLib,

        pub fn open() Error!VulkanLoader {
            return .{
                .handle = std.DynLib.open(
                    library_name,
                ) catch return error.LoaderFailed,
            };
        }

        pub fn close(self: *VulkanLoader) void {
            self.handle.close();
        }

        pub fn lookup(self: *VulkanLoader, comptime T: type, name: [:0]const u8) ?T {
            return @ptrCast(self.handle.lookup(T, name));
        }
    },
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

vtable: Vtable,
handle: vk.VkInstance,
messenger_handle: vk.VkDebugUtilsMessengerEXT,
get_proc_addr: *const @TypeOf(vk.vkGetInstanceProcAddr),
destroy_messenger: *const @TypeOf(vk.vkDestroyDebugUtilsMessengerEXT),
loader: VulkanLoader,

pub fn create(_: Options) Error!Self {
    const max_properties = 128;

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

    var query_buffer: [max_properties]vk.VkExtensionProperties = undefined;
    var query_count: u32 = max_properties;

    // load vulkan lib
    log.info("loading vulkan lib ...", .{});
    var loader = try VulkanLoader.open();
    errdefer loader.close();

    log.debug("loading essential delegates ...", .{});
    const get_proc_addr = loader.lookup(
        *const @TypeOf(vk.vkGetInstanceProcAddr),
        "vkGetInstanceProcAddr",
    ) orelse return error.LoaderFailed;

    const enum_extensions: *const @TypeOf(vk.vkEnumerateInstanceExtensionProperties) = @ptrCast(
        get_proc_addr(null, "vkEnumerateInstanceExtensionProperties") orelse
            return error.LoaderFailed,
    );

    const create_instance: *const @TypeOf(vk.vkCreateInstance) = @ptrCast(
        get_proc_addr(null, "vkCreateInstance") orelse
            return error.LoaderFailed,
    );

    // query all extensions
    try utils.call(enum_extensions, .{
        null,
        &query_count,
        &query_buffer,
    }, error.InstanceCreationFailed);

    // create initial extension list
    var ext_buffer: [max_optional_extensions + required_extensions.len][*:0]const u8 = undefined;
    var ext_count = required_extensions.len;
    @memcpy(ext_buffer[0..required_extensions.len], required_extensions);

    log.info("required extensions:", .{});
    for (required_extensions) |ext| {
        log.info(" \"{s}\"", .{std.mem.span(ext)});
    }

    // enable supported optional extensions
    log.info("supported optional extensions:", .{});
    for (optional_extensions) |ext| {
        const opt_name = std.mem.span(ext);

        for (0..query_count) |i| {
            const name = std.mem.sliceTo(&query_buffer[i].extensionName, 0);
            if (std.mem.eql(u8, name, opt_name)) {
                log.info(" \"{s}\"", .{name});
                ext_buffer[ext_count] = ext;
                ext_count += 1;
                break;
            }
        }
    }

    const messenger_create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = diagnosticCallback,
    };

    const create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = if (zora.builtin.debug) @ptrCast(&messenger_create_info) else null,
        .pApplicationInfo = &app_info,
        .ppEnabledLayerNames = validation_layers.ptr,
        .ppEnabledExtensionNames = &ext_buffer,
        .enabledLayerCount = @intCast(validation_layers.len),
        .enabledExtensionCount = @intCast(ext_count),
    };

    // create vulkan instance
    log.debug("creating vulkan instance ...", .{});
    var handle: vk.VkInstance = null;
    try utils.call(create_instance, .{
        &create_info,
        null,
        &handle,
    }, error.InstanceCreationFailed);

    // load destroy and setup defer
    const destroy_instance: *const @TypeOf(vk.vkDestroyInstance) = @ptrCast(
        get_proc_addr(handle, "vkDestroyInstance") orelse
            return error.LoaderFailed,
    );
    errdefer destroy_instance(handle, null);

    // try to setup a diagnostic messenger
    var messenger_handle: vk.VkDebugUtilsMessengerEXT = null;
    const destroy_messenger = switch (zora.builtin.debug) {
        true => try setupDiagnosticMessenger(
            handle,
            get_proc_addr,
            &messenger_create_info,
            &messenger_handle,
        ),
        false => null,
    };

    return .{
        // load virtual functions
        .vtable = utils.loadVtable(
            Vtable,
            get_proc_addr,
            handle,
        ) orelse return error.LoaderFailed,

        .handle = handle,
        .messenger_handle = messenger_handle,
        .destroy_messenger = destroy_messenger,
        .loader = loader,
        .get_proc_addr = get_proc_addr,
    };
}

pub fn destroy(self: *Self) void {
    log.debug("destroying vulkan instance ...", .{});

    if (zora.builtin.debug) {
        self.destroy_messenger(self.handle, self.messenger_handle, null);
    }

    self.vtable.destroyInstance(self.handle, null);
    self.loader.close();
}

pub fn getProcAddr(
    self: *const Self,
    comptime F: type,
    comptime name: [:0]const u8,
) GenericError!F {
    return @ptrCast(self.get_proc_addr(self.handle, name.ptr) orelse
        return error.LoaderFailed);
}

fn setupDiagnosticMessenger(
    instance: vk.VkInstance,
    get_proc_addr: *const @TypeOf(vk.vkGetInstanceProcAddr),
    create_info: *const vk.VkDebugUtilsMessengerCreateInfoEXT,
    handle: *vk.VkDebugUtilsMessengerEXT,
) Error!*const @TypeOf(vk.vkDestroyDebugUtilsMessengerEXT) {
    const create_messenger: *const @TypeOf(vk.vkCreateDebugUtilsMessengerEXT) = @ptrCast(
        get_proc_addr(instance, "vkCreateDebugUtilsMessengerEXT") orelse
            return error.LoaderFailed,
    );

    const destroy_messenger: *const @TypeOf(vk.vkDestroyDebugUtilsMessengerEXT) = @ptrCast(
        get_proc_addr(instance, "vkDestroyDebugUtilsMessengerEXT") orelse
            return error.LoaderFailed,
    );

    try utils.call(create_messenger, .{
        instance,
        create_info,
        null,
        handle,
    }, error.LoaderFailed);

    return destroy_messenger;
}

fn diagnosticCallback(
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

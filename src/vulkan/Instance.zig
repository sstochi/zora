const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Self = @This();
const Error = zora.Instance.Error;
const GenericError = zora.GenericError;
const Options = zora.Instance.Options;

const extensions: []const [*:0]const u8 = &.{
    vk.VK_KHR_SURFACE_EXTENSION_NAME,
};

const optional_extensions: []const [*:0]const u8 = switch (zora.builtin.platform) {
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
const max_optional_extensions = 4;

const validation_layers: []const [*:0]const u8 = switch (zora.builtin.debug) {
    true => &.{"VK_LAYER_KHRONOS_validation"},
    false => &.{},
};

const library_name: [:0]const u8 = switch (zora.builtin.platform) {
    .win32 => "vulkan-1.dll",
    .unix, .android => "libvulkan.so",
    .macos => "libvulkan.dylib",
};

const VulkanLoader = switch (zora.builtin.platform) {
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
proc_addr_fn_ptr: *const @TypeOf(vk.vkGetInstanceProcAddr),
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
    var loader = try VulkanLoader.open();
    errdefer loader.close();

    const get_proc_addr = loader.lookup(
        *const @TypeOf(vk.vkGetInstanceProcAddr),
        "vkGetInstanceProcAddr",
    ) orelse return error.LoaderFailed;

    const enum_extensions: *const @TypeOf(vk.vkEnumerateInstanceExtensionProperties) = @ptrCast(
        get_proc_addr(null, "vkEnumerateInstanceExtensionProperties") orelse
            return error.LoaderFailed,
    );

    const createInstance: *const @TypeOf(vk.vkCreateInstance) = @ptrCast(
        get_proc_addr(null, "vkCreateInstance") orelse
            return error.LoaderFailed,
    );

    // query all extensions
    try utils.except(enum_extensions(
        null,
        &query_count,
        &query_buffer,
    ), error.InstanceCreationFailed);

    // create initial extension list
    var ext_buffer: [max_optional_extensions + extensions.len][*:0]const u8 = undefined;
    var ext_count = extensions.len;
    @memcpy(ext_buffer[0..extensions.len], extensions);

    std.log.debug("vulkan instance extensions:", .{});
    for (extensions) |ext| {
        std.log.debug("\t\"{s}\"", .{std.mem.span(ext)});
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
    try utils.except(
        createInstance(&create_info, null, &instance),
        error.InstanceCreationFailed,
    );

    // load destroy and setup defer
    const destroy_instance: *const @TypeOf(vk.vkDestroyInstance) = @ptrCast(
        get_proc_addr(instance, "vkDestroyInstance") orelse
            return error.LoaderFailed,
    );
    errdefer destroy_instance(instance, null);

    return .{
        // load virtual functions
        .vtable = utils.loadVtable(
            Vtable,
            get_proc_addr,
            instance,
        ) orelse return error.LoaderFailed,

        .handle = instance,
        .loader = loader,
        .proc_addr_fn_ptr = get_proc_addr,
    };
}

pub fn destroy(self: *Self) void {
    self.vtable.destroyInstance(self.handle, null);
    self.loader.close();
}

pub fn getProcAddr(
    self: *const Self,
    comptime F: type,
    comptime name: [:0]const u8,
) GenericError!F {
    return @ptrCast(self.proc_addr_fn_ptr(self.handle, name.ptr) orelse
        return error.LoaderFailed);
}

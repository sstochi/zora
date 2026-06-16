const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const log = std.log.scoped(.swapchain);

const Instance = @import("Instance.zig");
const Adapter = @import("Adapter.zig");

const Self = @This();
const Error = zora.Swapchain.Error;
const Options = zora.Swapchain.Options;
const Info = zora.Swapchain.Info;

chain_info: zora.Swapchain.Options,
adapter: *const Adapter,
handle: vk.VkSwapchainKHR,
acquire_image_sem: vk.VkSemaphore,
present_sem: vk.VkSemaphore,

pub fn create(adapter: *const Adapter, options: Options) Error!Self {
    const max_formats: u32 = 128;
    const max_modes: u32 = 32;

    const instance = adapter.instance;
    const phy_device = &adapter.phy_device;

    var capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
    var format_buffer: [max_formats]vk.VkSurfaceFormatKHR = undefined;
    var mode_buffer: [max_modes]vk.VkPresentModeKHR = undefined;
    var format_count = max_formats;
    var mode_count = max_modes;

    log.debug("querying supported properties ...", .{});

    // query capabilities
    try instance.vtable.callResult("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", .{
        phy_device.handle,
        adapter.surface,
        &capabilities,
    }, error.SwapchainCreationFailed);

    // ... surface formats...
    try instance.vtable.callResult("vkGetPhysicalDeviceSurfacePresentModesKHR", .{
        phy_device.handle,
        adapter.surface,
        &mode_count,
        &mode_buffer,
    }, error.SwapchainCreationFailed);

    // ... and present modes
    try instance.vtable.callResult("vkGetPhysicalDeviceSurfaceFormatsKHR", .{
        phy_device.handle,
        adapter.surface,
        &format_count,
        &format_buffer,
    }, error.SwapchainCreationFailed);

    // decide on the target present mode
    const target_mode: vk.VkPresentModeKHR = switch (options.vsync_mode) {
        .disabled => vk.VK_PRESENT_MODE_IMMEDIATE_KHR,
        .enabled => vk.VK_PRESENT_MODE_FIFO_KHR,
        .adaptive => vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
        .mailbox => vk.VK_PRESENT_MODE_MAILBOX_KHR,
    };

    // sort based on favourability
    std.mem.sort(
        vk.VkPresentModeKHR,
        mode_buffer[0..mode_count],
        target_mode,
        presentModeCompareLessThan,
    );

    std.mem.sort(
        vk.VkSurfaceFormatKHR,
        format_buffer[0..format_count],
        {},
        formatCompareLessThan,
    );

    log.info("surface formats:", .{});
    for (0..format_count) |i| {
        log.info(" {?s}", .{std.enums.tagName(utils.Format, @enumFromInt(format_buffer[i].format))});
    }

    log.info("present modes:", .{});
    for (0..mode_count) |i| {
        log.info(" {?s}", .{std.enums.tagName(utils.PresentMode, @enumFromInt(mode_buffer[i]))});
    }

    const max_image_count = switch (capabilities.maxImageCount) {
        0 => std.math.maxInt(u32), // in vulkan, 0 means "unlimited"
        else => capabilities.maxImageCount,
    };

    const same_queue = phy_device.graphics_queue_idx == phy_device.surface_queue_idx;
    const queue_indicies = [_]u32{ phy_device.graphics_queue_idx, phy_device.surface_queue_idx };

    const create_info = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .clipped = vk.VK_TRUE,

        .pQueueFamilyIndices = if (same_queue) null else &queue_indicies,
        .queueFamilyIndexCount = if (same_queue) 0 else @intCast(queue_indicies.len),

        .minImageCount = @min(capabilities.minImageCount + 1, max_image_count),
        .imageExtent = vk.VkExtent2D{
            .width = @min(options.width, capabilities.maxImageExtent.width),
            .height = @min(options.height, capabilities.maxImageExtent.height),
        },
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = if (same_queue) vk.VK_SHARING_MODE_EXCLUSIVE else vk.VK_SHARING_MODE_CONCURRENT,
        .imageFormat = format_buffer[0].format,
        .imageColorSpace = format_buffer[0].colorSpace,
        .imageArrayLayers = 1,

        .surface = adapter.surface,
        .presentMode = mode_buffer[0],
        .preTransform = capabilities.currentTransform,
    };

    // create swapchain khr
    log.debug("creating vulkan swapchain ...", .{});
    var handle: vk.VkSwapchainKHR = undefined;

    try adapter.vtable.callResult("vkCreateSwapchainKHR", .{
        adapter.handle,
        &create_info,
        null,
        &handle,
    }, error.SwapchainCreationFailed);

    errdefer adapter.vtable.call("vkDestroySwapchainKHR", .{
        adapter.handle,
        handle,
        null,
    });

    var acquire_image_sem: vk.VkSemaphore = undefined;
    var present_sem: vk.VkSemaphore = undefined;

    const sem_create_info = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    try adapter.vtable.callResult("vkCreateSemaphore", .{
        adapter.handle,
        &sem_create_info,
        null,
        &acquire_image_sem,
    }, error.SwapchainCreationFailed);

    try adapter.vtable.callResult("vkCreateSemaphore", .{
        adapter.handle,
        &sem_create_info,
        null,
        &present_sem,
    }, error.SwapchainCreationFailed);

    return .{
        .chain_info = .{
            .width = options.width,
            .height = options.height,
            .vsync_mode = switch (mode_buffer[0]) {
                vk.VK_PRESENT_MODE_FIFO_KHR => .enabled,
                vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR => .adaptive,
                vk.VK_PRESENT_MODE_MAILBOX_KHR => .mailbox,
                else => .disabled,
            },
        },

        .adapter = adapter,
        .handle = handle,
        .acquire_image_sem = acquire_image_sem,
        .present_sem = present_sem,
    };
}

pub fn destroy(self: *Self) void {
    _ = self.adapter.vtable.call("vkDeviceWaitIdle", .{self.adapter.handle});

    log.debug("destroying vulkan swapchain ...", .{});
    self.adapter.vtable.call("vkDestroySwapchainKHR", .{
        self.adapter.handle,
        self.handle,
        null,
    });
}

pub fn present(self: *Self) void {
    // WIP: currently this code does nothing and is in fact incorrect
    // it's simply here to submite changes to wayland :)
    var idx: u32 = undefined;

    self.adapter.vtable.callResult("vkAcquireNextImageKHR", .{
        self.adapter.handle,
        self.handle,
        std.math.maxInt(u64),
        self.acquire_image_sem,
        null,
        &idx,
    }, error.Failed) catch @panic(":(");

    var handles: [1]vk.VkSwapchainKHR = .{self.handle};
    var semaphores: [1]vk.VkSemaphore = .{self.acquire_image_sem};

    const create_info = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pImageIndices = &idx,
        .pSwapchains = &handles,
        .swapchainCount = @intCast(handles.len),
        .pWaitSemaphores = &semaphores,
        .waitSemaphoreCount = @intCast(semaphores.len),
    };

    _ = self.adapter.vtable.call("vkQueuePresentKHR", .{
        self.adapter.surface_queue,
        &create_info,
    });
}

pub fn info(self: *const Self) *const Info {
    return &self.chain_info;
}

fn formatCompareLessThan(
    _: void,
    a: vk.VkSurfaceFormatKHR,
    b: vk.VkSurfaceFormatKHR,
) bool {
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

fn presentModeCompareLessThan(
    target: vk.VkPresentModeKHR,
    a: vk.VkPresentModeKHR,
    b: vk.VkPresentModeKHR,
) bool {
    // TODO: if user requests any kind of vsync (mailbox, adaptive, regular), we probably want to offer the
    // next best match (ex. if user requested mailbox/adaptive, but only regular is available, choose it)
    return @intFromBool(b == target) < @intFromBool(a == target);
}

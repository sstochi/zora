const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Instance = @import("Instance.zig");
const Adapter = @import("Adapter.zig");

const Self = @This();
const Error = zora.Swapchain.Error;
const Options = zora.Swapchain.Options;

chain_info: zora.Swapchain.Options,
adapter: *const Adapter,
handle: vk.VkSwapchainKHR,
acquire_image_sem: vk.VkSemaphore,
present_sem: vk.VkSemaphore,

pub fn create(
    adapter: *const Adapter,
    handle: vk.VkSwapchainKHR,
    options: Options,
) Error!Self {
    var acquire_image_sem: vk.VkSemaphore = undefined;
    var present_sem: vk.VkSemaphore = undefined;

    const create_info = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    try utils.except(adapter.vtable.createSemaphore(
        adapter.handle,
        &create_info,
        null,
        &acquire_image_sem,
    ), error.SwapchainCreationFailed);

    try utils.except(adapter.vtable.createSemaphore(
        adapter.handle,
        &create_info,
        null,
        &present_sem,
    ), error.SwapchainCreationFailed);

    return .{
        .chain_info = options,
        .adapter = adapter,
        .handle = handle,
        .acquire_image_sem = acquire_image_sem,
        .present_sem = present_sem,
    };
}

pub fn destroy(self: *Self) void {
    self.adapter.vtable.destroySwapchainKHR(
        self.adapter.handle,
        self.handle,
        null,
    );
}

pub fn present(self: *Self) void {
    var idx: u32 = undefined;

    utils.except(self.adapter.vtable.acquireNextImageKHR(
        self.adapter.handle,
        self.handle,
        std.math.maxInt(u64),
        self.acquire_image_sem,
        null,
        &idx,
    ), error.Failed) catch @panic("balls");

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

    _ = self.adapter.vtable.queuePresentKHR(self.adapter.surface_queue, &create_info);
}

pub fn info(self: *const Self) *const zora.Swapchain.Options {
    return &self.chain_info;
}

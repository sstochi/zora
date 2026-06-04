const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Instance = @import("Instance.zig");
const Adapter = @import("Adapter.zig");

chain_info: zora.Swapchain.Info,
adapter: *const Adapter,
handle: vk.VkSwapchainKHR,
acquire_image_sem: vk.VkSemaphore,
present_sem: vk.VkSemaphore,

const Self = @This();

pub fn create(
    adapter: *const Adapter,
    handle: vk.VkSwapchainKHR,
    chain_info: zora.Swapchain.Info,
) ?Self {
    var result: vk.VkResult = undefined;
    var acquire_image_sem: vk.VkSemaphore = undefined;
    var present_sem: vk.VkSemaphore = undefined;

    const create_info = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    result = adapter.vtable.createSemaphore(
        adapter.handle,
        &create_info,
        null,
        &acquire_image_sem,
    );
    if (!utils.success(result)) return null;

    result = adapter.vtable.createSemaphore(
        adapter.handle,
        &create_info,
        null,
        &present_sem,
    );
    if (!utils.success(result)) return null;

    return .{
        .chain_info = chain_info,
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

    if (!utils.success(self.adapter.vtable.acquireNextImageKHR(
        self.adapter.handle,
        self.handle,
        std.math.maxInt(u64),
        self.acquire_image_sem,
        null,
        &idx,
    ))) {
        @panic("balls");
    }

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

pub fn info(self: *const Self) *const zora.Swapchain.Info {
    return &self.chain_info;
}

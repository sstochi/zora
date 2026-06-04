const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Adapter = @import("Adapter.zig");

chain_info: zora.Swapchain.Info,
adapter: *const Adapter,
handle: vk.VkSwapchainKHR,

const Self = @This();

pub fn destroy(self: *Self) void {
    self.adapter.vtable.destroySwapchainKHR(
        self.adapter.handle,
        self.handle,
        null,
    );
}

pub fn info(self: *const Self) *const zora.Swapchain.Info {
    return &self.chain_info;
}

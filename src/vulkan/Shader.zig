const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Adapter = @import("Adapter.zig");

const Self = @This();
const Error = zora.Shader.Error;
const Options = zora.Shader.Options;
const Info = zora.Shader.Info;

adapter: *const Adapter,
handle: vk.VkShaderModule,

pub fn create(adapter: *const Adapter, options: Options) Error!Self {
    const create_info = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pCode = @ptrCast(options.spirv.ptr),
        .codeSize = options.spirv.len,
    };

    var handle: vk.VkShaderModule = undefined;
    try utils.except(
        adapter.vtable.createShaderModule(adapter.handle, &create_info, null, &handle),
    );

    return .{
        .adapter = adapter,
        .handle = handle,
    };
}

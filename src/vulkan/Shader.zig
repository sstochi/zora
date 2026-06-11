const std = @import("std");
const vk = @import("vulkan");
const utils = @import("utils.zig");
const zora = @import("../root.zig");

const Adapter = @import("Adapter.zig");

const Self = @This();
const Error = zora.Shader.Error;
const Options = zora.Shader.Options;
const Info = zora.Shader.Info;

const Stage = struct {
    create_info: vk.VkPipelineShaderStageCreateInfo,
    handle: vk.VkShaderModule,
};

stages: [3]Stage,
stage_count: usize,
adapter: *const Adapter,

pub fn create(adapter: *const Adapter, options: Options) Error!Self {
    const stage_types = struct {
        pub const vertex = vk.VK_SHADER_STAGE_VERTEX_BIT;
        pub const fragment = vk.VK_SHADER_STAGE_FRAGMENT_BIT;
        pub const compute = vk.VK_SHADER_STAGE_COMPUTE_BIT;
    };

    var stages: [3]Stage = undefined;
    var stage_count: usize = 0;

    // cleanup properly on errdefer
    errdefer for (0..stage_count) |i| {
        adapter.vtable.destroyShaderModule(
            adapter.handle,
            stages[i].handle,
            null,
        );
    };

    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |*field| blk: {
        const stage = @field(options, field.name) orelse break :blk;

        const create_info = vk.VkShaderModuleCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pCode = @ptrCast(stage.spirv.ptr),
            .codeSize = stage.spirv.len,
        };

        var handle: vk.VkShaderModule = undefined;
        try utils.except(
            adapter.vtable.createShaderModule(adapter.handle, &create_info, null, &handle),
            error.ShaderCreationFailed,
        );

        stages[stage_count] = .{
            // prepare create info, useful later when (re)creating the pipeline
            .create_info = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = @field(stage_types, field.name),
                .module = handle,
                .pName = stage.entrypoint,
            },
            .handle = handle,
        };
        stage_count += 1;
    }

    return .{
        .stages = stages,
        .stage_count = stage_count,
        .adapter = adapter,
    };
}

pub fn destroy(self: *Self) void {
    for (0..self.stage_count) |i| {
        self.adapter.vtable.destroyShaderModule(
            self.adapter.handle,
            self.stages[i].handle,
            null,
        );
    }
}

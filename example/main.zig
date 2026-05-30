const std = @import("std");
const zora = @import("zora");

pub fn main(_: std.process.Init) !void {
    var adapter = try zora.Adapter.open(.{});
    defer adapter.close();

    const info = adapter.info();
    std.debug.print("{any}\n", .{info});

    // const texture = try adapter.createTexture(.{
    //     .usage = .{ .read = true, .write = true },
    //     .format = .bgra8,
    //     .width = 4,
    //     .height = 4,
    //     .data = null,
    // });
    // defer texture.destroy();

    // const vertex_buffer = try adapter.createBuffer(.{
    //     .usage = .{ .read = true, .write = true },
    //     .size = 2048,
    //     .data = null,
    // });

    // const shader = try adapter.createShader(.{
    //     .data = @embedFile("test.spv"),

    //     .vertex = .{
    //         .entry = "vs_main",
    //         .bind_layout = .{},
    //     },

    //     .fragment = .{
    //         .entry = "fs_main",
    //         .bind_layout = .{},
    //     },
    // });

    // const data: [4 * 4]u32 = undefined;

    // var queue = try adapter.createQueue();
    // queue.submit(zora.UploadTexturePass{ .target = texture, .data = &data });
}

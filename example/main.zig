const std = @import("std");
const zora = @import("zora");
const sdl = @cImport(@cInclude("SDL3/SDL.h"));

pub fn main(_: std.process.Init) !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return error.SDLFailed;
    const window = sdl.SDL_CreateWindow("Test", 640, 360, sdl.SDL_WINDOW_RESIZABLE) orelse return error.SDLFailed;
    defer sdl.SDL_DestroyWindow(window);

    const driver_name = std.mem.span(sdl.SDL_GetCurrentVideoDriver());
    const props = sdl.SDL_GetWindowProperties(window);

    var instance = try zora.Instance.create();
    defer instance.destroy();

    var adapter = if (std.mem.eql(u8, driver_name, "x11")) blk: {
        const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
        const window_handle = sdl.SDL_GetNumberProperty(props, sdl.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        break :blk try zora.Adapter.open(&instance, .{ .xlib = .{ .display = display, .window = @intCast(window_handle) } }, .discrete);
    } else if (std.mem.eql(u8, driver_name, "wayland")) blk: {
        const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
        const surface = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
        break :blk try zora.Adapter.open(&instance, .{ .wayland = .{ .display = display, .surface = surface } }, .discrete);
    } else return error.InvalidBackend;
    defer adapter.close();

    var swapchain = try adapter.createSwapchain(.{ .width = 640, .height = 360, .vsync_mode = .adaptive });
    defer swapchain.destroy();

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

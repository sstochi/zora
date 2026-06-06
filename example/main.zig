const std = @import("std");
const zora = @import("zora");
const sdl = @cImport(@cInclude("SDL3/SDL.h"));
const builtin = @import("builtin");

pub fn main(_: std.process.Init) !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return error.SDLFailed;
    const window = sdl.SDL_CreateWindow("Test", 640, 360, sdl.SDL_WINDOW_RESIZABLE) orelse return error.SDLFailed;
    defer sdl.SDL_DestroyWindow(window);

    const driver_name = std.mem.span(sdl.SDL_GetCurrentVideoDriver());
    const props = sdl.SDL_GetWindowProperties(window);

    var instance = try zora.Instance.create();
    defer instance.destroy();

    var adapter = if (builtin.os.tag != .windows) outer: {
        break :outer if (std.mem.eql(u8, driver_name, "x11")) blk: {
            const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
            const window_handle = sdl.SDL_GetNumberProperty(props, sdl.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
            break :blk try zora.Adapter.open(&instance, .{ .xlib = .{ .display = display, .window = @intCast(window_handle) } }, .discrete);
        } else if (std.mem.eql(u8, driver_name, "wayland")) blk: {
            const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
            const surface = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
            break :blk try zora.Adapter.open(&instance, .{ .wayland = .{ .display = display, .surface = surface } }, .discrete);
        } else return error.InvalidBackend;
    } else outer: {
        const hinstance = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER, null);
        const hwnd = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
        break :outer try zora.Adapter.open(&instance, .{ .hinstance = hinstance, .hwnd = hwnd }, .discrete);
    };
    defer adapter.close();

    var swapchain = try adapter.createSwapchain(.{ .width = 640, .height = 360, .vsync_mode = .adaptive });
    defer swapchain.destroy();

    const info = adapter.info();
    std.debug.print("{any}\n", .{info});

    var event: sdl.SDL_Event = undefined;
    blk: while (true) {
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => break :blk,
                else => {},
            }
        }

        swapchain.present();
    }
}

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

    var instance = try zora.Instance.create(.{});
    defer instance.destroy();

    var adapter = try outer: switch (zora.builtin.target) {
        .win32 => {
            const hinstance = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER, null);
            const hwnd = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
            break :outer zora.Adapter.open(&instance, .{
                .power_mode = .discrete,
                .window_info = .{
                    .hinstance = hinstance,
                    .hwnd = hwnd,
                },
            });
        },

        .unix => {
            const window_info: zora.WindowInfo = if (std.mem.eql(u8, driver_name, "x11")) blk: {
                const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
                const handle = sdl.SDL_GetNumberProperty(props, sdl.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
                break :blk .{ .xlib = .{
                    .display = display,
                    .window = @intCast(handle),
                } };
            } else if (std.mem.eql(u8, driver_name, "wayland")) blk: {
                const display = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
                const surface = sdl.SDL_GetPointerProperty(props, sdl.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
                break :blk .{ .wayland = .{
                    .display = display,
                    .surface = surface,
                } };
            } else return error.InvalidBackend;

            break :outer zora.Adapter.open(&instance, .{
                .power_mode = .discrete,
                .window_info = window_info,
            });
        },

        else => @compileError("unsupported os"),
    };
    defer adapter.close();

    var shader = try adapter.createShader(.{
        .vertex = .{
            .entrypoint = "main",
            .spirv = @alignCast(@embedFile("test.vert.spv")),
            .glsl = @alignCast(@embedFile("test.vert.glsl")),
        },

        .fragment = .{
            .entrypoint = "main",
            .spirv = @alignCast(@embedFile("test.frag.spv")),
            .glsl = @alignCast(@embedFile("test.frag.glsl")),
        },
    });
    defer shader.destroy();

    var swapchain = try adapter.createSwapchain(.{
        .width = 640,
        .height = 360,
        .vsync_mode = .mailbox,
    });
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

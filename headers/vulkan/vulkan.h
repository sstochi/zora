// Replacement for vulkan's
#include <vulkan/vk_platform.h>
#include <vulkan/vulkan_core.h>

#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <vulkan/vulkan_win32.h>
#elif defined(__ANDROID__)
    struct ANativeWindow;
    struct AHardwareBuffer;

    #include <vulkan/vulkan_android.h>
#elif defined(__unix__)
    #include <stdint.h>

    typedef unsigned long XID;
    typedef struct _XDisplay Display;
    typedef XID Window;
    typedef XID VisualID;

    typedef struct xcb_connection_t xcb_connection_t;
    typedef uint32_t xcb_window_t;
    typedef uint32_t xcb_visualid_t;

    struct wl_display;
    struct wl_surface;

    #include <vulkan/vulkan_xcb.h>
    #include <vulkan/vulkan_wayland.h>
    #include <vulkan/vulkan_xlib.h>
#endif

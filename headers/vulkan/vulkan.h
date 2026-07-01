// Replacement for vulkan's
#include "vk_platform.h"
#include "vulkan_core.h"

#if defined(_WIN32)
    typedef unsigned long DWORD;
    typedef wchar_t* LPCWSTR;
    typedef void* HINSTANCE;
    typedef void* HMODULE;
    typedef void* HANDLE;
    typedef void* HMONITOR;
    typedef struct _HWND* HWND;
    typedef struct _SECURITY_ATTRIBUTES SECURITY_ATTRIBUTES;

    #include "vulkan_win32.h"
#elif defined(__ANDROID__)
    struct ANativeWindow;
    struct AHardwareBuffer;

    #include "vulkan_android.h"
#elif defined(__unix__)
    #include <stdint.h>

    typedef struct _XDisplay Display;
    typedef unsigned long Window;
    typedef unsigned long VisualID;
    typedef struct xcb_connection_t xcb_connection_t;
    typedef uint32_t xcb_window_t;
    typedef uint32_t xcb_visualid_t;
    struct wl_display;
    struct wl_surface;

    #include "vulkan_xcb.h"
    #include "vulkan_wayland.h"
    #include "vulkan_xlib.h"
#endif

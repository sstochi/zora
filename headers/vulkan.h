// #define VK_NO_PROTOTYPES
#include "vulkan/vk_platform.h"
#include "vulkan/vulkan_core.h"

#if defined(__unix__)
#include <stdint.h>

// Xlib
typedef struct _XDisplay Display;
typedef unsigned long Window;
typedef unsigned long VisualID;

// Xcb
typedef struct xcb_connection_t xcb_connection_t;
typedef uint32_t xcb_window_t;
typedef uint32_t xcb_visualid_t;

// Wayland
struct wl_display;
struct wl_surface;

#include "vulkan/vulkan_xcb.h"
#include "vulkan/vulkan_wayland.h"
#include "vulkan/vulkan_xlib.h"

#elif defined(_WIN32)

typedef struct HINSTANCE__ *HINSTANCE;
typedef struct HWND__ *HWND;

#include "vulkan_win32.h"

#endif

#include "vulkan/vulkan.h"

// for unix platforms, we always want to have EGL
// at the very least for wayland support
#if !defined(_WIN32)
    #include <EGL/egl.h>
#endif

#ifndef OPENGL_USE_GLES
    #define GL_GLEXT_PROTOTYPES
    #include <GL/glcorearb.h>
#else
    #define GL_GLES_PROTOTYPES
    #include <GLES2/gl2.h>
#endif

#if defined(_WIN32)
    #define WGL_WGLEXT_PROTOTYPES
    #include <GL/wglext.h>
#elif defined(__unix__) && !defined(OPENGL_USE_GLES)
    #define GLX_GLXEXT_PROTOTYPES
    #define Bool int
    #define Status int

    typedef unsigned long XID;
    typedef struct _XDisplay Display;
    typedef struct _XVisualInfo XVisualInfo;
    typedef XID Window;
    typedef XID VisualID;
    typedef XID Pixmap;
    typedef XID Colormap;

    typedef struct __GLXcontextRec *GLXContext;
    typedef XID GLXPixmap;
    typedef XID GLXDrawable;

    typedef struct __GLXFBConfigRec *GLXFBConfig;
    typedef XID GLXFBConfigID;
    typedef XID GLXContextID;
    typedef XID GLXWindow;
    typedef XID GLXPbuffer;

    #include <GL/glxext.h>
#endif

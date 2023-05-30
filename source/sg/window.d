module sg.window;

import bindbc.glfw;
import bindbc.loader.sharedlib;
import bindbc.opengl;
import btl.autoptr.common;
import btl.autoptr.intrusive_ptr;
import sg.visitors.oglhelper;
import sg;
import std.concurrency : thisTid;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writeln;

void loadBindBCGlfw()
{
    const result = loadGLFW();
    writeln(result);
    if (result != glfwSupport)
    {
        foreach (info; bindbc.loader.sharedlib.errors)
        {
            writeln("error: ", info.message);
        }
        throw new Exception("Cannot load glfw");
    }
}

void loadBindBCOpenGL()
{
    const result = loadOpenGL();
    writeln(result);
    version (Default)
    {
        (result == GLSupport.gl21).enforce("need opengl 2.1 support");
    }
    version (GL_33)
    {
        (result == GLSupport.gl33).enforce("need opengl 3.3 support");
    }
}

/++
 + https://discourse.glfw.org/t/multithreading-glfw/573/5
 +/
class Window
{
    Scene scene;
    GLFWwindow* window;
    int width;
    int height;

    struct ScrollInfo
    {
        double xOffset;
        double yOffset;
        void reset()
        {
            xOffset = 0;
            yOffset = 0;
        }
    }

    ScrollInfo scroll;
    alias KeyCallback = void delegate(Window w, int key, int scancode, int action, int mods);
    KeyCallback keyCallback;
    this(Scene scene, int width, int height, KeyCallback keyCallback)
    {
        this.scene = scene;
        scroll.reset;
        scene.get.setRenderThread(thisTid);
        this.keyCallback = keyCallback;
        loadBindBCGlfw();
        glfwInit();
        version (GL_33)
        {
            glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
            glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
            glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
            glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        }
        window = glfwCreateWindow(width, height, "test", null, null);
        window.glfwSetWindowUserPointer(cast(void*) this);
        window.glfwSetKeyCallback(&staticKeyCallback);
        window.glfwSetFramebufferSizeCallback(&staticSizeCallback);
        window.glfwSetWindowSize(width, height);
        window.glfwSetScrollCallback(&staticScrollCallback);

        int w, h;
        window.glfwGetFramebufferSize(&w, &h);
        staticSizeCallback(window, w, h);

        window.glfwMakeContextCurrent();
        loadBindBCOpenGL();
        writeln("OGLVendor:        ", glGetString(GL_VENDOR).to!string);
        writeln("OGLRenderer:      ", glGetString(GL_RENDERER).to!string);
        writeln("OGLVersion:       ", glGetString(GL_VERSION).to!string);
        version (Default)
        {
            writeln("OGLExt:           ", glGetString(GL_EXTENSIONS).to!string);
        }
        writeln("MAX_TEXTURE_SIZE: ", glGetInt(GL_MAX_TEXTURE_SIZE).to!string);
    }

    ~this()
    {
        glfwTerminate();
    }

    void sizeCallback(int width, int height)
    {
        this.width = width;
        this.height = height;
        //writeln("width=", this.width, " height=", this.height);
    }

    void scrollCallback(double xOffset, double yOffset)
    {
        this.scroll.xOffset = -xOffset;
        this.scroll.yOffset = -yOffset;
    }

    ScrollInfo getAndResetScrollInfo()
    {
        ScrollInfo res = scroll;
        scroll.reset;
        return res;
    }

    int getWidth()
    {
        return cast(int)(width);
    }

    int getHeight()
    {
        return cast(int)(height);
    }

    struct MouseInfo
    {
        int x;
        int y;
        ubyte button;
    }

    MouseInfo getMouseInfo()
    {
        double mouseX;
        double mouseY;
        window.glfwGetCursorPos(&mouseX, &mouseY);

        static double mouseXToWindowFactor = 0;
        static double mouseYToWindowFactor = 0;
        if (mouseXToWindowFactor == 0) // need to initialize
        {
            int virtualWindowWidth;
            int virtualWindowHeight;
            window.glfwGetWindowSize(&virtualWindowWidth, &virtualWindowHeight);
            if (virtualWindowWidth != 0 && virtualWindowHeight != 0)
            {
                int frameBufferWidth;
                int frameBufferHeight;
                window.glfwGetFramebufferSize(&frameBufferWidth, &frameBufferHeight);
                mouseXToWindowFactor = double(frameBufferWidth) / virtualWindowWidth;
                mouseYToWindowFactor = double(frameBufferHeight) / virtualWindowHeight;
            }
        }
        mouseX *= mouseXToWindowFactor;
        mouseY *= mouseYToWindowFactor;

        ubyte buttonState = 0;
        buttonState |= window.glfwGetMouseButton(GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS ? 0x1 : 0x0;
        buttonState |= window.glfwGetMouseButton(GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS ? 0x2 : 0x0;
        return MouseInfo(cast(int) mouseX, getHeight - cast(int) mouseY, buttonState);
    }
}

extern (C)
{
    void staticKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer();
            w.keyCallback(w, key, scancode, action, mods);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }

    void staticSizeCallback(GLFWwindow* window, int width, int height) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer();
            w.sizeCallback(width, height);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }

    void staticScrollCallback(GLFWwindow* window, double xOffset, double yOffset) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer;
            w.scrollCallback(xOffset, yOffset);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }
}

module sg.window;
import std;
import sg;
import btl.autoptr.common;
import btl.autoptr.intrusive_ptr;

public import bindbc.glfw;
import glfwloader = bindbc.loader.sharedlib;
public import bindbc.opengl;

void loadBindBCGlfw()
{
    const result = loadGLFW();
    if (result != glfwSupport)
    {
        foreach (info; glfwloader.errors)
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
        if (result == GLSupport.gl33)
            .enforce("need opengl 3.3 support");
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
    alias KeyCallback = void delegate(Window w, int key, int scancode, int action, int mods);
    KeyCallback keyCallback;
    this(Scene scene, int width, int height, KeyCallback keyCallback)
    {
        this.scene = scene;
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
        int w, h;
        window.glfwGetFramebufferSize(&w, &h);
        staticSizeCallback(window, w, h);

        window.glfwMakeContextCurrent();
        loadBindBCOpenGL();
        writeln("Use opengl");
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
        writeln("width=", this.width, " height=", this.height);
    }

    int getWidth()
    {
        return cast(int)(width);
    }

    int getHeight()
    {
        return cast(int)(height);
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
        }
    }

    void staticSizeCallback(GLFWwindow* window, int width, int height) nothrow
    {
        try
        {
            auto w = cast(Window) glfwGetWindowUserPointer(window);
            w.sizeCallback(width, height);
        }
        catch (Throwable t)
        {
        }
    }
}

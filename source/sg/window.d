module sg.window;
import std;
import sg;

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
    if (result == GLSupport.gl21)
    {
    }
    else
    {
        throw new Exception("need opengl 2.1 support");
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
    float xscale;
    float yscale;
    alias KeyCallback = void delegate(Window w, int key, int scancode, int action, int mods);
    KeyCallback keyCallback;
    // dfmt off
    this(Scene scene,
         int width,
         int height,
         KeyCallback keyCallback)
      // dfmt on
    {
        this.scene = scene;
        scene.bind(thisTid);
        this.keyCallback = keyCallback;
        loadBindBCGlfw();
        glfwInit();
        window = glfwCreateWindow(width, height, "test", null, null);
        glfwSetWindowUserPointer(window, cast(void*) this);
        glfwSetKeyCallback(window, &staticKeyCallback);
        glfwSetWindowSizeCallback(window, &staticSizeCallback);
        glfwGetWindowContentScale(window, &xscale, &yscale);
        staticSizeCallback(window, width, height);
        glfwMakeContextCurrent(window);
        loadBindBCOpenGL();
        writeln("Use opengl");
        writeln("OGLVendor:        ", glGetString(GL_VENDOR).to!string);
        writeln("OGLRenderer:      ", glGetString(GL_RENDERER).to!string);
        writeln("OGLVersion:       ", glGetString(GL_VERSION).to!string);
        writeln("OGLExt:           ", glGetString(GL_EXTENSIONS).to!string);
        writeln("MAX_TEXTURE_SIZE: ", glGetInt(GL_MAX_TEXTURE_SIZE).to!string);
    }

    ~this()
    {
        glfwTerminate();
    }

    void sizeCallback(int width, int height)
    {
        this.width = cast(int)(width * xscale);
        this.height = cast(int)(height * yscale);
        writeln("width=", this.width, " height=", this.height);
    }

    int getWidth()
    {
        return cast(int)(width * xscale);
    }

    int getHeight()
    {
        return cast(int)(height * yscale);
    }
}

extern (C)
{
    void staticKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
    {
        try
        {
            Window w = cast(Window) glfwGetWindowUserPointer(window);
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
            Window w = cast(Window) glfwGetWindowUserPointer(window);
            w.sizeCallback(width, height);
        }
        catch (Throwable t)
        {
        }
    }
}

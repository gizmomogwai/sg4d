module window;
import std;
import sg;

public import bindbc.glfw;
import glfwloader = bindbc.loader.sharedlib;
public import bindbc.opengl;

void loadBindBCGlfw() {
    auto result = loadGLFW();
    if(result != glfwSupport) {
        foreach(info; glfwloader.errors) {
            writeln("error: ", info.message);
        }
        throw new Exception("Cannot load glfw");
    }
}

void loadBindBCOpenGL() {
    auto result = loadOpenGL();
    if (result == GLSupport.gl21) {
    }  else {
        throw new Exception("need opengl 2.1 support");
    }
}


class Window {
    Observer observer;
    GLFWwindow* window;
    private int width;
    private int height;
    float xscale;
    float yscale;
    this(Observer observer) {
        this.observer = observer;
        loadBindBCGlfw();
        glfwInit();
        window = glfwCreateWindow(100, 100, "test", null, null);
        glfwSetWindowUserPointer(window, cast(void*)this);
        glfwSetKeyCallback(window, &staticKeyCallback);
        glfwSetWindowSizeCallback(window, &staticSizeCallback);
        glfwGetWindowContentScale(window, &xscale, &yscale);
        writeln(xscale, ", ", yscale);
        staticSizeCallback(window, 100, 100);
        glfwMakeContextCurrent(window);
        loadBindBCOpenGL();
        writeln("OGLVendor:   ", glGetString(GL_VENDOR).to!string);
        writeln("OGLRenderer: ", glGetString(GL_RENDERER).to!string);
        writeln("OGLVersion:  ", glGetString(GL_VERSION).to!string);
        writeln("OGLExt:      ", glGetString(GL_EXTENSIONS).to!string);
    }
    ~this() {
        glfwTerminate();
    }
    void keyCallback(int key, int scancode, int action, int mods) {
        if (key == 'A') {
            observer.strafeLeft();
        }
        if (key == 'D') {
            observer.strafeRight();
        }
    }
    void sizeCallback(int width, int height) {
        this.width = width;
        this.height = height;
    }
    int getWidth() {
        return cast(int)(width * xscale);
    }
    int getHeight() {
        return cast(int)(height * yscale);
    }
}

extern (C) {
    void staticKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow {
        try {
            Window w = cast(Window)glfwGetWindowUserPointer(window);
            w.keyCallback(key, scancode, action, mods);
        } catch (Throwable t) {
        }
    }
    void staticSizeCallback(GLFWwindow* window, int width, int height) nothrow {
        try {
            Window w = cast(Window)glfwGetWindowUserPointer(window);
            w.sizeCallback(width, height);
        } catch (Throwable t) {
        }
    }
}


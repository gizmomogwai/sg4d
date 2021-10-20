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
    writeln(result);
    if (result == GLSupport.gl21) {
        writeln("yes .. .gl41 support is on");
    }  else {
        throw new Exception("need opengl 2.1 support");
    }
}


class Window {
    Observer observer;
    GLFWwindow* window;
    int width;
    int height;
    this(Observer observer) {
        this.observer = observer;
        loadBindBCGlfw();
        glfwInit();
        window = glfwCreateWindow(100, 100, "test", null, null);
        glfwSetWindowUserPointer(window, cast(void*)this);
        glfwSetKeyCallback(window, &staticKeyCallback);
        glfwSetWindowSizeCallback(window, &staticSizeCallback);
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
            observer.left();
        }
        if (key == 'D') {
            observer.right();
        }
    }
    void sizeCallback(int width, int height) {
        this.width = width;
        this.height = height;
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


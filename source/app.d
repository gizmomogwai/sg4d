import std.stdio;
import bindbc.glfw;
import core.thread;
import std.conv;

import glfwloader = bindbc.loader.sharedlib;
import bindbc.opengl;

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

extern (C) {
    void staticKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow {
        try {
            writeln("key: ", key);
        } catch (Throwable t) {
        }
    }
}

void main(string[] args) {
    loadBindBCGlfw();

    glfwInit();
    auto window = glfwCreateWindow(100, 100, "test", null, null);

    glfwSetKeyCallback(window, &staticKeyCallback);
    glfwMakeContextCurrent(window);

    loadBindBCOpenGL();

    writeln("OGLVendor:   ", glGetString(GL_VENDOR).to!string);
    writeln("OGLRenderer: ", glGetString(GL_RENDERER).to!string);
    writeln("OGLVersion:  ", glGetString(GL_VERSION).to!string);
    writeln("OGLExt:      ", glGetString(GL_EXTENSIONS).to!string);
    import sg;
    Root root = new Root("root");
    Observer observer = new Observer("observer", null, new ParallelProjection());
    TransformationNode rotation = new TransformationNode("rotation", new Transformation());
    Shape teapot = new Shape("cube");
    rotation.addChild(teapot);
    observer.addChild(rotation);
    root.addChild(observer);
    PrintVisitor v = new PrintVisitor();
    root.accept(v);

    OGLRenderVisitor ogl = new OGLRenderVisitor();
    while (!glfwWindowShouldClose(window)) {
        root.accept(ogl);

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glfwTerminate();
}

import std.stdio;
import core.thread;
import std.conv;

import sg;
import window;

void main(string[] args) {
    Root root = new Root("root");
    auto projection = args[1] == "parallel" ?
        new ParallelProjection() :
        new CameraProjection();
    Observer observer = new Observer("observer", projection);
    TransformationNode rotation = new TransformationNode("rotation", new Transformation());

    Window w = new Window(observer);
    Shape teapot = new Shape("cube");
    rotation.addChild(teapot);
    rotation.addChild(new Behavior("rotY", () {static float rot = 0; rotation.transformation.rotY(rot); rot = cast(float)(rot+0.1);}));
    observer.addChild(rotation);
    root.addChild(observer);
    PrintVisitor v = new PrintVisitor();
    root.accept(v);

    OGLRenderVisitor ogl = new OGLRenderVisitor(w);
    BehaviorVisitor behavior = new BehaviorVisitor();

    while (!glfwWindowShouldClose(w.window)) {
        root.accept(behavior);
        root.accept(ogl);

        glfwSwapBuffers(w.window);
        glfwPollEvents();
    }
}

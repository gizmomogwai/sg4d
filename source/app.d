import std.stdio;
import core.thread;
import std.conv;

import sg;
import window;

void main(string[] args) {
    auto root = new Root("root");
    auto projection = args[1] == "parallel" ?
        new ParallelProjection(-10000, 10000) :
        new CameraProjection();
    auto observer = new Observer("observer", projection);
    auto rotation = new TransformationNode("rotation", mat4.identity());

    auto window = new Window(observer);
    auto shape = new Shape("cube");
    rotation.addChild(shape);
    rotation.addChild(new Behavior("rotY", () {static float rot = 0; rotation.transformation = mat4.yrotation(rot); rot = cast(float)(rot+0.01);}));
    observer.addChild(rotation);
    root.addChild(observer);
    PrintVisitor v = new PrintVisitor();
    root.accept(v);

    OGLRenderVisitor ogl = new OGLRenderVisitor(window);
    BehaviorVisitor behavior = new BehaviorVisitor();

    while (!glfwWindowShouldClose(window.window)) {
        root.accept(behavior);
        root.accept(ogl);

        glfwSwapBuffers(window.window);
        glfwPollEvents();
    }
}

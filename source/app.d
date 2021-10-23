import std.stdio;
import core.thread;
import std.conv;

import sg;
import window;

void main(string[] args)
{
    auto root = new Root("root");
    auto projection = args[1] == "parallel" ? new ParallelProjection(1, 1000) : new CameraProjection(1,
            1000);
    auto observer = new Observer("observer", projection);
    auto translation = new TransformationNode("translation", mat4.translation(0, 0, 0));
    auto rotation = new TransformationNode("rotation", mat4.identity());

    auto window = new Window(observer, root);
    auto shape = new Shape("cube");
    rotation.addChild(shape);
    rotation.addChild(new Behavior("rotY", () {
            static float rot = 0;
            rotation.transformation = mat4.rotation(rot, vec3(1, 1, 1));
            rot = cast(float)(rot + 0.01);
        }));
    translation.addChild(rotation);
    observer.addChild(translation);
    root.addChild(observer);
    PrintVisitor v = new PrintVisitor();
    root.accept(v);

    OGLRenderVisitor ogl = new OGLRenderVisitor(window);
    BehaviorVisitor behavior = new BehaviorVisitor();

    while (!glfwWindowShouldClose(window.window))
    {
        root.accept(behavior);
        root.accept(ogl);

        glfwSwapBuffers(window.window);
        glfwPollEvents();
    }
}

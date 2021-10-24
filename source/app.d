import std.stdio;
import core.thread;
import std.conv;
import std.string;

import sg;
import window;

auto cube(string textureFile, float x, float y, float z, float rotationSpeed)
{
    auto translation = new TransformationNode("translation-" ~ textureFile,
            mat4.translation(x, y, z));
    auto rotation = new TransformationNode("rotation-" ~ textureFile, mat4.identity());
    IFImage image = read_image(textureFile, 3);
    if (image.e)
    {
        throw new Exception("%s".format(IF_ERROR[image.e]));
    }
    auto shape = new Shape("cube-" ~ textureFile, new CubeGeometry(1),
            new Appearance([new Texture(image)]));
    rotation.addChild(shape);
    float rot = 0;
    rotation.addChild(new Behavior("rotY-" ~ textureFile, () {
            rotation.transformation = mat4.rotation(rot, vec3(1, 1, 1));
            rot = cast(float)(rot + rotationSpeed);
        }));
    translation.addChild(rotation);
    return translation;
}

void main(string[] args)
{
    auto root = new Root("root");
    auto projection = args[1] == "parallel" ? new ParallelProjection(1, 1000) : new CameraProjection(1,
            1000);
    auto observer = new Observer("observer", projection);
    observer.addChild(cube("image1.jpg", 0, 0, 0, 0.01));
    observer.addChild(cube("image2.jpg", 3, 0, 0, 0.02));

    auto window = new Window(observer, root, 800, 600);
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
